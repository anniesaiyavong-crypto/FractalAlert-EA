// Detects confirmed Bill Williams Fractals and sends Telegram alerts with chart screenshots
#property copyright "Asanay"
#property version   "1.1"

// Input Parameters
input group "--- Telegram Settings ---"
input string   InpTelegramToken     = "";      // Bot Token (from @BotFather)
input string   InpTelegramChatID    = "";      // Chat ID (user or group)

input group "--- Fractal Settings ---"
input int      InpFractalLookback   = 50;      // Max bars to search for confirmed fractal

input group "--- Screenshot Settings ---"
input int      InpChartWidth        = 1280;    // Screenshot Width (px)
input int      InpChartHeight       = 720;     // Screenshot Height (px)
input int      InpMaxImages         = 10;      // Max stored screenshots before deleting oldest

// Global Variables
int            m_fractalHandle;
datetime       m_lastBarTime;
int            m_imageCounter;           // Tracks total screenshots taken (for rotation)
datetime       m_lastUpperFractalTime;   // Bar time of last alerted upper fractal
datetime       m_lastLowerFractalTime;   // Bar time of last alerted lower fractal

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

   m_lastBarTime = 0;
   m_imageCounter = 0;
   m_lastUpperFractalTime = 0;
   m_lastLowerFractalTime = 0;

   Print("FractalAlert initialized on ", _Symbol, " ", EnumToString(_Period));
   Print("  Telegram Chat ID: ", InpTelegramChatID);
   Print("  Max screenshots: ", InpMaxImages);

   // Send startup message
   SendTelegramText("FractalAlert EA started on " + _Symbol + " " + EnumToString(_Period));

   return INIT_SUCCEEDED;
}

// Expert deinitialization function
void OnDeinit(const int reason)
{
   if(m_fractalHandle != INVALID_HANDLE)
      IndicatorRelease(m_fractalHandle);

   Print("FractalAlert deinitialized. Reason: ", reason);
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

   // Copy buffer starting from bar 0 with AsSeries = true
   // index 0 = current open bar
   // index 1 = previous closed bar
   // index 2 = confirmed fractal candidate bar
   if(CopyBuffer(m_fractalHandle, bufferIndex, 0, count, fractalBuf) < count)
   {
      Print("WARNING: Failed to copy fractal buffer ", bufferIndex, ", error: ", GetLastError());
      return false;
   }

   if(CopyTime(_Symbol, _Period, 0, count, timeBuf) < count)
   {
      Print("WARNING: Failed to copy time buffer, error: ", GetLastError());
      return false;
   }

   // Search from bar 2 (the earliest bar that can be a confirmed 5-bar fractal)
   for(int i = 2; i < count; i++)
   {
      if(fractalBuf[i] != EMPTY_VALUE && fractalBuf[i] != 0.0)
      {
         fractalPrice = fractalBuf[i];
         fractalTime  = timeBuf[i];
         return true;
      }
   }

   return false;
}

// Take a chart screenshot saved to MQL5/Files/ and return the filename
string TakeChartScreenshot()
{
   // Build filename with rotation (fractal_0.png ... fractal_9.png)
   int fileIndex = m_imageCounter % InpMaxImages;
   string filename = "fractal_" + IntegerToString(fileIndex) + ".png";

   // Delete the old file if it exists (rotation cleanup)
   if(FileIsExist(filename))
      FileDelete(filename);

   // Capture chart screenshot
   if(!ChartScreenShot(0, filename, InpChartWidth, InpChartHeight))
   {
      Print("ERROR: ChartScreenShot failed. Code: ", GetLastError());
      return "";
   }

   m_imageCounter++;
   Print("Screenshot saved: ", filename, " (slot ", fileIndex, "/", InpMaxImages, ")");
   return filename;
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
   // Remove null terminator that StringToCharArray appends
   ArrayResize(postArray, ArraySize(postArray) - 1);

   int res = WebRequest(
      "POST",
      url,
      "Content-Type: application/x-www-form-urlencoded\r\n",
      NULL,
      5000,
      postArray,
      ArraySize(postArray),
      resultArray,
      resultHeaders
   );

   if(res != 200)
   {
      string response = CharArrayToString(resultArray, 0, WHOLE_ARRAY, CP_UTF8);
      Print("Telegram sendMessage failed. HTTP ", res, " | ", response);
      return false;
   }

   return true;
}

// Send a photo to Telegram using multipart/form-data
bool SendTelegramPhoto(string filename, string caption)
{
   string url = "https://api.telegram.org/bot" + InpTelegramToken + "/sendPhoto";

   // Read the image file from MQL5/Files/
   int fileHandle = FileOpen(filename, FILE_READ | FILE_BIN);
   if(fileHandle == INVALID_HANDLE)
   {
      Print("ERROR: Cannot open file ", filename, " for Telegram upload.");
      return false;
   }

   int fileSize = (int)FileSize(fileHandle);
   char fileData[];
   ArrayResize(fileData, fileSize);
   FileReadArray(fileHandle, fileData, 0, fileSize);
   FileClose(fileHandle);

   // Build multipart/form-data body manually
   string boundary = "----MQL5FractalAlert";
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

   // Convert text parts to char array
   char bodyStart[];
   StringToCharArray(body, bodyStart, 0, WHOLE_ARRAY, CP_UTF8);
   ArrayResize(bodyStart, ArraySize(bodyStart) - 1); // Remove null terminator

   // Build closing boundary
   string closingStr = crlf + "--" + boundary + "--" + crlf;
   char bodyEnd[];
   StringToCharArray(closingStr, bodyEnd, 0, WHOLE_ARRAY, CP_UTF8);
   ArrayResize(bodyEnd, ArraySize(bodyEnd) - 1);

   // Combine: bodyStart + fileData + bodyEnd
   char postData[];
   int totalSize = ArraySize(bodyStart) + ArraySize(fileData) + ArraySize(bodyEnd);
   ArrayResize(postData, totalSize);

   int offset = 0;
   ArrayCopy(postData, bodyStart, offset);
   offset += ArraySize(bodyStart);
   ArrayCopy(postData, fileData, offset);
   offset += ArraySize(fileData);
   ArrayCopy(postData, bodyEnd, offset);

   // Send request
   char resultArray[];
   string resultHeaders;
   string headers = "Content-Type: multipart/form-data; boundary=" + boundary + "\r\n";

   int res = WebRequest(
      "POST",
      url,
      headers,
      NULL,
      10000,
      postData,
      totalSize,
      resultArray,
      resultHeaders
   );

   if(res != 200)
   {
      string response = CharArrayToString(resultArray, 0, WHOLE_ARRAY, CP_UTF8);
      Print("Telegram sendPhoto failed. HTTP ", res, " | ", response);
      return false;
   }

   Print("Telegram photo sent successfully: ", filename);
   return true;
}

// Expert tick function
void OnTick()
{
   // New bar check — only check for fractals once per bar
   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   if(currentBarTime == m_lastBarTime)
      return;

   // On first run, initialize timestamps to the current latest fractals so it doesn't alert on historical ones
   if(m_lastBarTime == 0)
   {
      m_lastBarTime = currentBarTime;
      double dummyPrice;
      datetime initUpperTime = 0, initLowerTime = 0;
      if(GetLatestFractal(0, dummyPrice, initUpperTime))
         m_lastUpperFractalTime = initUpperTime;
      if(GetLatestFractal(1, dummyPrice, initLowerTime))
         m_lastLowerFractalTime = initLowerTime;

      Print("Initialized fractal baseline. Upper time: ", TimeToString(m_lastUpperFractalTime), 
            ", Lower time: ", TimeToString(m_lastLowerFractalTime));
      return;
   }

   m_lastBarTime = currentBarTime;

   // Check for NEW Upper Fractal (bearish arrow on high)
   double upperPrice = 0.0;
   datetime upperTime = 0;
   if(GetLatestFractal(0, upperPrice, upperTime))
   {
      if(upperTime > m_lastUpperFractalTime)
      {
         m_lastUpperFractalTime = upperTime;

         string message = "<b>Fractal Alert: BEARISH (Upper)</b>\n"
                        + "Symbol: " + _Symbol + "\n"
                        + "Timeframe: " + EnumToString(_Period) + "\n"
                        + "Fractal High: " + DoubleToString(upperPrice, _Digits) + "\n"
                        + "Fractal Bar Time: " + TimeToString(upperTime, TIME_DATE | TIME_MINUTES) + "\n"
                        + "Current Bid: " + DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_BID), _Digits) + "\n"
                        + "Alert Time: " + TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS);

         Print("New Upper Fractal detected at price ", upperPrice, " on bar ", TimeToString(upperTime));

         // Take screenshot and send to Telegram
         string screenshotFile = TakeChartScreenshot();
         if(screenshotFile != "")
            SendTelegramPhoto(screenshotFile, message);
         else
            SendTelegramText(message);
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

         string message = "<b>Fractal Alert: BULLISH (Lower)</b>\n"
                        + "Symbol: " + _Symbol + "\n"
                        + "Timeframe: " + EnumToString(_Period) + "\n"
                        + "Fractal Low: " + DoubleToString(lowerPrice, _Digits) + "\n"
                        + "Fractal Bar Time: " + TimeToString(lowerTime, TIME_DATE | TIME_MINUTES) + "\n"
                        + "Current Ask: " + DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_ASK), _Digits) + "\n"
                        + "Alert Time: " + TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS);

         Print("New Lower Fractal detected at price ", lowerPrice, " on bar ", TimeToString(lowerTime));

         // Take screenshot and send to Telegram
         string screenshotFile = TakeChartScreenshot();
         if(screenshotFile != "")
            SendTelegramPhoto(screenshotFile, message);
         else
            SendTelegramText(message);
      }
   }
}
