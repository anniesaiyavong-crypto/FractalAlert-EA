// Detects confirmed Bill Williams Fractals and sends Telegram alerts with chart screenshots
#property copyright "Asanay"
#property version   "1.3"

// Input Parameters
input group "--- Telegram Settings ---"
input string   InpTelegramToken     = "";      // Bot Token (from @BotFather)
input string   InpTelegramChatID    = "";      // Chat ID (user or group)

input group "--- Fractal Settings ---"
input int      InpFractalLookback   = 50;      // Max bars to search for confirmed fractal

input group "--- ATR Settings ---"
input int      InpATRPeriod         = 14;      // ATR Period (default: 14)

input group "--- Message Settings ---"
input bool     InpShowPrice         = false;   // Include price in alert (e.g. M5 2650.50)
input bool     InpShowSymbol        = false;   // Include symbol in alert (e.g. XAUUSD M5)

input group "--- Screenshot Settings ---"
input int      InpChartWidth        = 1280;    // Screenshot Width (px)
input int      InpChartHeight       = 720;     // Screenshot Height (px)
input int      InpMaxImages         = 10;      // Max stored screenshots before deleting oldest

// Global Variables
int            m_fractalHandle;
int            m_atrHandle;
datetime       m_lastBarTime;
int            m_imageCounter;           // Tracks total screenshots taken (for rotation)
datetime       m_lastUpperFractalTime;   // Bar time of last alerted upper fractal
datetime       m_lastLowerFractalTime;   // Bar time of last alerted lower fractal

// Helper function to format timeframe cleanly (e.g. PERIOD_M5 -> M5)
string GetPeriodString(ENUM_TIMEFRAMES period)
{
   string s = EnumToString(period);
   if(StringFind(s, "PERIOD_") == 0)
      return StringSubstr(s, 7);
   return s;
}

// Expert initialization function
int OnInit()
{
   // Validate Telegram settings
   if(InpTelegramToken == "" || InpTelegramChatID == "")
   {
      Print("ERROR: Telegram Bot Token and Chat ID are required.");
      return INIT_FAILED;
   }

   // Create Fractal handle
   m_fractalHandle = iFractals(_Symbol, _Period);
   if(m_fractalHandle == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create Fractals handle. Code: ", GetLastError());
      return INIT_FAILED;
   }

   // Create ATR handle
   m_atrHandle = iATR(_Symbol, _Period, InpATRPeriod);
   if(m_atrHandle == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create ATR handle. Code: ", GetLastError());
      return INIT_FAILED;
   }

   m_lastBarTime          = 0;
   m_imageCounter         = 0;
   m_lastUpperFractalTime = 0;
   m_lastLowerFractalTime = 0;

   Print("FractalAlert initialized on ", _Symbol, " ", GetPeriodString(_Period));
   Print("  ATR Period: ", InpATRPeriod);
   Print("  Telegram Chat ID: ", InpTelegramChatID);
   Print("  Max screenshots: ", InpMaxImages);

   // Send startup message
   SendTelegramText("FractalAlert EA started on " + _Symbol + " " + GetPeriodString(_Period));

   return INIT_SUCCEEDED;
}

// Expert deinitialization function
void OnDeinit(const int reason)
{
   if(m_fractalHandle != INVALID_HANDLE)
      IndicatorRelease(m_fractalHandle);

   if(m_atrHandle != INVALID_HANDLE)
      IndicatorRelease(m_atrHandle);

   Print("FractalAlert deinitialized. Reason: ", reason);
}

// Get current ATR value
double GetCurrentATR()
{
   double atrBuf[];
   ArraySetAsSeries(atrBuf, true);
   if(CopyBuffer(m_atrHandle, 0, 0, 1, atrBuf) < 1)
      return 0.0;
   return atrBuf[0];
}

// Find the most recent confirmed fractal price and bar time
// bufferIndex: 0 = Upper Fractal (high), 1 = Lower Fractal (low)
// Returns true if a confirmed fractal was found within lookback
bool GetLatestFractal(int bufferIndex, double &fractalPrice, datetime &fractalTime)
{
   double fractalBuf[];
   ArraySetAsSeries(fractalBuf, true);

   datetime timeBuf[];
   ArraySetAsSeries(timeBuf, true);

   int count = InpFractalLookback;
   if(count < 5) count = 5;

   if(CopyBuffer(m_fractalHandle, bufferIndex, 0, count, fractalBuf) < count)
      return false;

   if(CopyTime(_Symbol, _Period, 0, count, timeBuf) < count)
      return false;

   // Search from bar 1 backwards.
   // Catches any active fractal arrow on the chart
   for(int i = 1; i < count; i++)
   {
      if(fractalBuf[i] != EMPTY_VALUE && fractalBuf[i] > 0.0 && fractalBuf[i] < 10000000.0)
      {
         fractalPrice = fractalBuf[i];
         fractalTime  = timeBuf[i];
         return true;
      }
   }

   return false;
}

// Take a chart screenshot saved to MQL5/Files/ and wait until file is ready
string TakeChartScreenshot()
{
   int fileIndex = m_imageCounter % InpMaxImages;
   string filename = "fractal_" + IntegerToString(fileIndex) + ".png";

   // Delete old file in slot if it exists
   if(FileIsExist(filename))
      FileDelete(filename);

   // Request chart screenshot (asynchronous queue in MT5 chart engine)
   if(!ChartScreenShot(0, filename, InpChartWidth, InpChartHeight, ALIGN_RIGHT))
   {
      Print("WARNING: ChartScreenShot request failed. Code: ", GetLastError());
      return "";
   }

   m_imageCounter++;

   // Wait for MT5 chart thread to finish rendering and writing file to disk (up to 2 seconds)
   for(int attempt = 0; attempt < 20; attempt++)
   {
      Sleep(100);
      if(FileIsExist(filename))
      {
         int h = FileOpen(filename, FILE_READ | FILE_BIN);
         if(h != INVALID_HANDLE)
         {
            ulong sz = FileSize(h);
            FileClose(h);
            if(sz > 0)
            {
               Print("Screenshot ready: ", filename, " (", sz, " bytes, slot ", fileIndex, "/", InpMaxImages, ")");
               return filename;
            }
         }
      }
   }

   Print("WARNING: Screenshot timed out waiting for file write: ", filename);
   return "";
}

// Send a text message to Telegram
bool SendTelegramText(string message)
{
   string url = "https://api.telegram.org/bot" + InpTelegramToken + "/sendMessage";

   // Build POST body
   string postData = "chat_id=" + InpTelegramChatID + "&text=" + message + "&parse_mode=HTML";

   char postArray[];
   char resultArray[];
   string resultHeaders;

   StringToCharArray(postData, postArray, 0, WHOLE_ARRAY, CP_UTF8);
   ArrayResize(postArray, ArraySize(postArray) - 1); // Remove null terminator

   string headers = "Content-Type: application/x-www-form-urlencoded\r\n";

   int res = WebRequest(
      "POST",
      url,
      headers,
      10000,
      postArray,
      resultArray,
      resultHeaders
   );

   if(res != 200)
   {
      string response = CharArrayToString(resultArray, 0, WHOLE_ARRAY, CP_UTF8);
      Print("Telegram sendMessage failed. HTTP ", res, " | ", response, " | Code: ", GetLastError());
      return false;
   }

   return true;
}

// Send a photo to Telegram using multipart/form-data
bool SendTelegramPhoto(string filename, string caption)
{
   string url = "https://api.telegram.org/bot" + InpTelegramToken + "/sendPhoto";

   int fileHandle = FileOpen(filename, FILE_READ | FILE_BIN);
   if(fileHandle == INVALID_HANDLE)
   {
      Print("ERROR: Cannot open file ", filename, " for Telegram upload. Code: ", GetLastError());
      return false;
   }

   int fileSize = (int)FileSize(fileHandle);
   if(fileSize <= 0)
   {
      FileClose(fileHandle);
      Print("ERROR: File ", filename, " is empty.");
      return false;
   }

   char fileData[];
   ArrayResize(fileData, fileSize);
   FileReadArray(fileHandle, fileData, 0, fileSize);
   FileClose(fileHandle);

   string boundary = "----MQL5FractalAlert" + IntegerToString((int)TimeLocal());
   string crlf = "\r\n";

   // Part 1: chat_id
   string body = "--" + boundary + crlf;
   body += "Content-Disposition: form-data; name=\"chat_id\"" + crlf + crlf;
   body += InpTelegramChatID + crlf;

   // Part 2: caption
   body += "--" + boundary + crlf;
   body += "Content-Disposition: form-data; name=\"caption\"" + crlf + crlf;
   body += caption + crlf;

   // Part 3: parse_mode
   body += "--" + boundary + crlf;
   body += "Content-Disposition: form-data; name=\"parse_mode\"" + crlf + crlf;
   body += "HTML" + crlf;

   // Part 4: photo file header
   body += "--" + boundary + crlf;
   body += "Content-Disposition: form-data; name=\"photo\"; filename=\"" + filename + "\"" + crlf;
   body += "Content-Type: image/png" + crlf + crlf;

   char bodyStart[];
   StringToCharArray(body, bodyStart, 0, WHOLE_ARRAY, CP_UTF8);
   ArrayResize(bodyStart, ArraySize(bodyStart) - 1);

   string closingStr = crlf + "--" + boundary + "--" + crlf;
   char bodyEnd[];
   StringToCharArray(closingStr, bodyEnd, 0, WHOLE_ARRAY, CP_UTF8);
   ArrayResize(bodyEnd, ArraySize(bodyEnd) - 1);

   char postData[];
   int totalSize = ArraySize(bodyStart) + ArraySize(fileData) + ArraySize(bodyEnd);
   ArrayResize(postData, totalSize);

   int offset = 0;
   ArrayCopy(postData, bodyStart, offset);
   offset += ArraySize(bodyStart);
   ArrayCopy(postData, fileData, offset);
   offset += ArraySize(fileData);
   ArrayCopy(postData, bodyEnd, offset);

   char resultArray[];
   string resultHeaders;
   string headers = "Content-Type: multipart/form-data; boundary=" + boundary + "\r\n";

   int res = WebRequest(
      "POST",
      url,
      headers,
      15000,
      postData,
      resultArray,
      resultHeaders
   );

   if(res != 200)
   {
      string response = CharArrayToString(resultArray, 0, WHOLE_ARRAY, CP_UTF8);
      Print("Telegram sendPhoto failed. HTTP ", res, " | Response: ", response, " | Code: ", GetLastError());
      return false;
   }

   Print("Telegram photo sent successfully: ", filename);
   return true;
}

// Expert tick function
void OnTick()
{
   // On first run, wait until indicator buffer is ready, then initialize baseline
   if(m_lastBarTime == 0)
   {
      double dummyPrice;
      datetime initUpperTime = 0, initLowerTime = 0;
      bool upperOk = GetLatestFractal(0, dummyPrice, initUpperTime);
      bool lowerOk = GetLatestFractal(1, dummyPrice, initLowerTime);

      if(!upperOk && !lowerOk)
      {
         // Wait for indicator buffer calculation
         return;
      }

      m_lastUpperFractalTime = initUpperTime;
      m_lastLowerFractalTime = initLowerTime;
      m_lastBarTime = iTime(_Symbol, _Period, 0);

      Print("Initialized fractal baseline. Upper bar: ", TimeToString(m_lastUpperFractalTime),
            ", Lower bar: ", TimeToString(m_lastLowerFractalTime));
      return;
   }

   // Check for NEW Upper Fractal (bearish arrow on high)
   double upperPrice = 0.0;
   datetime upperTime = 0;
   if(GetLatestFractal(0, upperPrice, upperTime))
   {
      if(upperTime > m_lastUpperFractalTime)
      {
         m_lastUpperFractalTime = upperTime;

         double atr = GetCurrentATR();
         string tfStr = GetPeriodString(_Period);

         string message = "HIGH-" + DoubleToString(atr, 2) + "\n" + tfStr;
         if(InpShowSymbol)
            message = "HIGH-" + DoubleToString(atr, 2) + "\n" + _Symbol + " " + tfStr;
         if(InpShowPrice)
            message += " " + DoubleToString(upperPrice, _Digits);

         Print(">>> NEW Upper Fractal at ", upperPrice, " on bar ", TimeToString(upperTime), " (ATR: ", DoubleToString(atr, 2), ")");

         // Try sending screenshot photo, fallback to text if photo fails
         bool sent = false;
         string screenshotFile = TakeChartScreenshot();
         if(screenshotFile != "")
            sent = SendTelegramPhoto(screenshotFile, message);

         if(!sent)
         {
            Print("Falling back to text message alert...");
            SendTelegramText(message);
         }
      }
   }

   // Check for NEW Lower Fractal (bullish arrow on low)
   double lowerPrice = 0.0;
   datetime lowerTime = 0;
   if(GetLatestFractal(1, lowerPrice, lowerTime))
   {
      if(lowerTime > m_lastLowerFractalTime)
      {
         m_lastLowerFractalTime = lowerTime;

         double atr = GetCurrentATR();
         string tfStr = GetPeriodString(_Period);

         string message = "LOW-" + DoubleToString(atr, 2) + "\n" + tfStr;
         if(InpShowSymbol)
            message = "LOW-" + DoubleToString(atr, 2) + "\n" + _Symbol + " " + tfStr;
         if(InpShowPrice)
            message += " " + DoubleToString(lowerPrice, _Digits);

         Print(">>> NEW Lower Fractal at ", lowerPrice, " on bar ", TimeToString(lowerTime), " (ATR: ", DoubleToString(atr, 2), ")");

         // Try sending screenshot photo, fallback to text if photo fails
         bool sent = false;
         string screenshotFile = TakeChartScreenshot();
         if(screenshotFile != "")
            sent = SendTelegramPhoto(screenshotFile, message);

         if(!sent)
         {
            Print("Falling back to text message alert...");
            SendTelegramText(message);
         }
      }
   }
}
