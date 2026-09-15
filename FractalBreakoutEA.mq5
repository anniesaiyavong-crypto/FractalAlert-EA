// FractalBreakoutEA.mq5
// Copyright 2026 Asanay
#property copyright "Asanay"
#property version   "1.0"

#include <Trade\Trade.mqh>

// Input Parameters
input group "--- Trade Settings ---"
input double   InpLotSize           = 0.1;    // Lot Size (Fixed)
input int      InpFixedSLPoints     = 0;      // Fixed Stop Loss in Points (0 = use Fractal SL)
input int      InpFixedTPPoints     = 0;      // Fixed Take Profit in Points (0 = no TP, trail only)
input int      InpMaxPositions      = 1;      // Max Concurrent Positions
input ulong    InpMagicNumber       = 100001; // Magic Number

input group "--- Fractal Settings ---"
input int      InpFractalLookback   = 20;     // Max bars to search for confirmed fractal

input group "--- Trend Filter: Bill Williams Alligator (Primary) ---"
input int      InpAlligatorJaw      = 13;     // Jaw Period (Blue)
input int      InpAlligatorJawShift = 8;      // Jaw Shift
input int      InpAlligatorTeeth    = 8;      // Teeth Period (Red)
input int      InpAlligatorTeethShift = 5;    // Teeth Shift
input int      InpAlligatorLips     = 5;      // Lips Period (Green)
input int      InpAlligatorLipsShift = 3;     // Lips Shift

input group "--- Trend Filter: Dual EMA (Higher-Timeframe Confirmation) ---"
input ENUM_TIMEFRAMES InpHTFTimeframe = PERIOD_H4;  // Higher Timeframe for EMA
input int      InpFastEMAPeriod     = 50;     // Fast EMA Period
input int      InpSlowEMAPeriod     = 200;    // Slow EMA Period

input group "--- Spread Filter ---"
input int      InpMaxSpreadPoints   = 50;     // Max Allowed Spread (Points, 0 = disabled)

input group "--- Trailing Stop ---"
input bool     InpUseTrailingStop   = true;   // Trail SL by New Fractal Levels

// Global Variables
CTrade         m_trade;

// Indicator handles
int            m_fractalHandle;
int            m_alligatorHandle;
int            m_htfFastEMAHandle;
int            m_htfSlowEMAHandle;

// State tracking
datetime       m_lastBarTime;

// Expert initialization function
int OnInit()
{
   // Configure trade object
   m_trade.SetExpertMagicNumber(InpMagicNumber);
   m_trade.SetDeviationInPoints(10); // Max slippage for Gold

   // Create Fractal handle (Bill Williams Fractals)
   m_fractalHandle = iFractals(_Symbol, _Period);
   if(m_fractalHandle == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create Fractals handle. Code: ", GetLastError());
      return INIT_FAILED;
   }

   // Create Alligator handle
   m_alligatorHandle = iAlligator(_Symbol, _Period,
                                   InpAlligatorJaw, InpAlligatorJawShift,
                                   InpAlligatorTeeth, InpAlligatorTeethShift,
                                   InpAlligatorLips, InpAlligatorLipsShift,
                                   MODE_SMMA, PRICE_MEDIAN);
   if(m_alligatorHandle == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create Alligator handle. Code: ", GetLastError());
      return INIT_FAILED;
   }

   // Create Higher-Timeframe EMA handles
   m_htfFastEMAHandle = iMA(_Symbol, InpHTFTimeframe, InpFastEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   m_htfSlowEMAHandle = iMA(_Symbol, InpHTFTimeframe, InpSlowEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   if(m_htfFastEMAHandle == INVALID_HANDLE || m_htfSlowEMAHandle == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create HTF EMA handles. Code: ", GetLastError());
      return INIT_FAILED;
   }

   m_lastBarTime = 0;

   Print("FractalBreakoutEA initialized on ", _Symbol, " ", EnumToString(_Period));
   Print("  Alligator: Jaw=", InpAlligatorJaw, " Teeth=", InpAlligatorTeeth, " Lips=", InpAlligatorLips);
   Print("  HTF EMA: TF=", EnumToString(InpHTFTimeframe), " Fast=", InpFastEMAPeriod, " Slow=", InpSlowEMAPeriod);
   return INIT_SUCCEEDED;
}

// Expert deinitialization function
void OnDeinit(const int reason)
{
   if(m_fractalHandle != INVALID_HANDLE)     IndicatorRelease(m_fractalHandle);
   if(m_alligatorHandle != INVALID_HANDLE)   IndicatorRelease(m_alligatorHandle);
   if(m_htfFastEMAHandle != INVALID_HANDLE)  IndicatorRelease(m_htfFastEMAHandle);
   if(m_htfSlowEMAHandle != INVALID_HANDLE)  IndicatorRelease(m_htfSlowEMAHandle);

   Print("FractalBreakoutEA deinitialized. Reason: ", reason);
}

// Find the most recent confirmed fractal price level
// bufferIndex: 0 = Upper Fractal (high), 1 = Lower Fractal (low)
// Returns 0.0 if no fractal found within lookback range
double FindLastFractal(int bufferIndex)
{
   double fractalBuf[];
   ArraySetAsSeries(fractalBuf, true);

   // Copy fractal buffer values; start from index 2 (fractals need 2 bars to confirm)
   int startBar = 2;
   int count = InpFractalLookback;

   if(CopyBuffer(m_fractalHandle, bufferIndex, startBar, count, fractalBuf) < count)
   {
      Print("WARNING: Failed to copy fractal buffer ", bufferIndex);
      return 0.0;
   }

   // Search for the first non-empty value (most recent confirmed fractal)
   for(int i = 0; i < count; i++)
   {
      if(fractalBuf[i] != EMPTY_VALUE && fractalBuf[i] != 0.0)
         return fractalBuf[i];
   }

   return 0.0; // No fractal found
}

// Check if current spread is within allowed limit
bool IsSpreadOK()
{
   if(InpMaxSpreadPoints <= 0)
      return true; // Filter disabled

   long spreadPoints = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spreadPoints > InpMaxSpreadPoints)
   {
      Print("Spread filter: current spread ", spreadPoints, " > max ", InpMaxSpreadPoints, ". Skipping.");
      return false;
   }
   return true;
}

// Get trend direction using Alligator + HTF EMA confirmation
// Returns: +1 = Uptrend, -1 = Downtrend, 0 = No clear trend
int GetTrendDirection()
{
   //--- Step 1: Read Alligator values (primary filter on current timeframe)
   // Buffer 0 = Jaw (Blue), Buffer 1 = Teeth (Red), Buffer 2 = Lips (Green)
   double jaw[], teeth[], lips[];
   ArraySetAsSeries(jaw, true);
   ArraySetAsSeries(teeth, true);
   ArraySetAsSeries(lips, true);

   if(CopyBuffer(m_alligatorHandle, 0, 0, 2, jaw)   < 2 ||
      CopyBuffer(m_alligatorHandle, 1, 0, 2, teeth) < 2 ||
      CopyBuffer(m_alligatorHandle, 2, 0, 2, lips)  < 2)
   {
      Print("WARNING: Failed to read Alligator buffers.");
      return 0;
   }

   // Alligator Uptrend: Lips > Teeth > Jaw (mouth opening upward)
   // Alligator Downtrend: Lips < Teeth < Jaw (mouth opening downward)
   int alligatorDirection = 0;
   if(lips[1] > teeth[1] && teeth[1] > jaw[1])
      alligatorDirection = +1;  // Bullish
   else if(lips[1] < teeth[1] && teeth[1] < jaw[1])
      alligatorDirection = -1;  // Bearish
   else
      return 0; // Alligator is tangled/sleeping — no trade

   //--- Step 2: Read HTF EMA values (higher-timeframe confirmation)
   double fastEMA[], slowEMA[];
   ArraySetAsSeries(fastEMA, true);
   ArraySetAsSeries(slowEMA, true);

   if(CopyBuffer(m_htfFastEMAHandle, 0, 0, 2, fastEMA) < 2 ||
      CopyBuffer(m_htfSlowEMAHandle, 0, 0, 2, slowEMA) < 2)
   {
      Print("WARNING: Failed to read HTF EMA buffers.");
      return 0;
   }

   int emaDirection = 0;
   if(fastEMA[0] > slowEMA[0])
      emaDirection = +1;  // HTF Bullish
   else if(fastEMA[0] < slowEMA[0])
      emaDirection = -1;  // HTF Bearish

   //--- Step 3: Both must agree
   if(alligatorDirection == emaDirection)
      return alligatorDirection;

   return 0; // Conflicting signals — no trade
}

// Count open positions for this EA (by magic number)
int CountPositionsByMagic()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber &&
            PositionGetString(POSITION_SYMBOL) == _Symbol)
            count++;
      }
   }
   return count;
}

// Open a Buy order
void OpenBuyOrder(double fractalSL)
{
   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   // Determine Stop Loss
   double sl = 0.0;
   if(InpFixedSLPoints > 0)
      sl = ask - InpFixedSLPoints * point;  // Fixed SL
   else if(fractalSL > 0.0)
      sl = fractalSL;                       // Dynamic fractal SL

   // Determine Take Profit
   double tp = 0.0;
   if(InpFixedTPPoints > 0)
      tp = ask + InpFixedTPPoints * point;

   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);

   if(!m_trade.Buy(InpLotSize, _Symbol, ask, sl, tp, "FractalEA Buy"))
   {
      Print("Buy FAILED. Code: ", m_trade.ResultRetcode(),
            " - ", m_trade.ResultRetcodeDescription());
   }
   else
   {
      Print("Buy OPENED. Ticket: ", m_trade.ResultOrder(),
            " | Price: ", ask, " | SL: ", sl, " | TP: ", tp);
   }
}

// Open a Sell order
void OpenSellOrder(double fractalSL)
{
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   // Determine Stop Loss
   double sl = 0.0;
   if(InpFixedSLPoints > 0)
      sl = bid + InpFixedSLPoints * point;  // Fixed SL
   else if(fractalSL > 0.0)
      sl = fractalSL;                       // Dynamic fractal SL

   // Determine Take Profit
   double tp = 0.0;
   if(InpFixedTPPoints > 0)
      tp = bid - InpFixedTPPoints * point;

   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);

   if(!m_trade.Sell(InpLotSize, _Symbol, bid, sl, tp, "FractalEA Sell"))
   {
      Print("Sell FAILED. Code: ", m_trade.ResultRetcode(),
            " - ", m_trade.ResultRetcodeDescription());
   }
   else
   {
      Print("Sell OPENED. Ticket: ", m_trade.ResultOrder(),
            " | Price: ", bid, " | SL: ", sl, " | TP: ", tp);
   }
}

// Trail stop loss to new fractal levels for all open positions
void TrailStopByFractals()
{
   if(!InpUseTrailingStop)
      return;

   double upperFractal = FindLastFractal(0); // Latest confirmed Upper Fractal (high)
   double lowerFractal = FindLastFractal(1); // Latest confirmed Lower Fractal (low)

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;

      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      long posType   = PositionGetInteger(POSITION_TYPE);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);

      if(posType == POSITION_TYPE_BUY)
      {
         // Trail Buy SL upward using Lower Fractal (support)
         if(lowerFractal > 0.0 && lowerFractal > currentSL && lowerFractal < SymbolInfoDouble(_Symbol, SYMBOL_BID))
         {
            double newSL = NormalizeDouble(lowerFractal, _Digits);
            if(m_trade.PositionModify(ticket, newSL, currentTP))
               Print("TRAIL Buy SL moved to ", newSL, " (Lower Fractal)");
         }
      }
      else if(posType == POSITION_TYPE_SELL)
      {
         // Trail Sell SL downward using Upper Fractal (resistance)
         if(upperFractal > 0.0 && (currentSL == 0.0 || upperFractal < currentSL) && upperFractal > SymbolInfoDouble(_Symbol, SYMBOL_ASK))
         {
            double newSL = NormalizeDouble(upperFractal, _Digits);
            if(m_trade.PositionModify(ticket, newSL, currentTP))
               Print("TRAIL Sell SL moved to ", newSL, " (Upper Fractal)");
         }
      }
   }
}

// Expert tick function
void OnTick()
{
   // Always check trailing stop on every tick (regardless of new bar)
   TrailStopByFractals();

   // New bar check — only process signals once per bar
   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   if(currentBarTime == m_lastBarTime)
      return;
   m_lastBarTime = currentBarTime;

   //--- Check position limit
   if(CountPositionsByMagic() >= InpMaxPositions)
      return;

   //--- Check spread filter
   if(!IsSpreadOK())
      return;

   //--- Get trend direction (Alligator + HTF EMA must agree)
   int trend = GetTrendDirection();
   if(trend == 0)
      return; // No clear trend or conflicting signals

   //--- Find last confirmed fractal levels
   double upperFractal = FindLastFractal(0); // Resistance level (Upper/Bearish Fractal High)
   double lowerFractal = FindLastFractal(1); // Support level (Lower/Bullish Fractal Low)

   if(upperFractal == 0.0 || lowerFractal == 0.0)
   {
      Print("No confirmed fractals found within lookback range.");
      return;
   }

   //--- Get the close price of the last completed bar (index 1)
   double lastClose = iClose(_Symbol, _Period, 1);
   // Also get the close of the bar before that (index 2) to detect breakout crossing
   double prevClose = iClose(_Symbol, _Period, 2);

   //--- Buy Signal: Uptrend + Price breaks above Upper Fractal level
   if(trend == +1)
   {
      // Breakout detection: previous bar closed below/at the level, last bar closed above it
      if(prevClose <= upperFractal && lastClose > upperFractal)
      {
         Print("BUY SIGNAL: Breakout above Upper Fractal ", upperFractal,
               " | Close[1]=", lastClose, " | Trend=UP");
         OpenBuyOrder(lowerFractal); // SL at Lower Fractal (support)
      }
   }
   //--- Sell Signal: Downtrend + Price breaks below Lower Fractal level
   else if(trend == -1)
   {
      // Breakout detection: previous bar closed above/at the level, last bar closed below it
      if(prevClose >= lowerFractal && lastClose < lowerFractal)
      {
         Print("SELL SIGNAL: Breakout below Lower Fractal ", lowerFractal,
               " | Close[1]=", lastClose, " | Trend=DOWN");
         OpenSellOrder(upperFractal); // SL at Upper Fractal (resistance)
      }
   }
}

