//+------------------------------------------------------------------+
//|                                              XAUUSD_EMA_EA.mq5   |
//|                    Multi-Symbol EMA Scalper Expert Advisor          |
//|                                                                    |
//| Trades any symbol on any timeframe using a 9-period EMA.           |
//| Works with forex, metals (XAUUSD), crypto (BTCUSD), and more.     |
//| Uses ATR-based distance filtering and SL buffer for auto-scaling.  |
//|                                                                    |
//| BUY only ABOVE EMA: 2 consecutive candles close above EMA         |
//|       and price is above EMA -> buy on next candle open.           |
//|       SL = Most recent swing low (fractal low).                    |
//| SELL only BELOW EMA: 2 consecutive candles close below EMA         |
//|       and price is below EMA -> sell on next candle open.          |
//|       SL = Most recent swing high (fractal high).                  |
//| TP:   None fixed. Trade closes at candle close ONLY if in profit.  |
//|       If in loss, trade stays open until SL hits or next candle     |
//|       close is in profit.                                           |
//| Only 1 trade at a time. Price must be near EMA (discount zone).    |
//+------------------------------------------------------------------+
#property copyright "AMA EA"
#property link      ""
#property version   "2.00"
#property strict

//--- Input parameters
input int      EMA_Period          = 9;            // EMA Period
input int      EMA_Shift           = 0;            // EMA Shift
input double   MinLotSize          = 0.20;         // Minimum lot size
input double   LotPerBalance       = 0.20;         // Lots per LotBalanceStep of balance
input double   LotBalanceStep      = 1000.0;       // Balance increment for lot increase (e.g. every $1000)
input double   MaxLotSize          = 10.0;         // Maximum lot size cap
input double   MaxEMADistanceATR   = 1.5;          // Max distance from EMA as ATR multiplier (discount zone filter)
input int      ATR_Period          = 14;           // ATR Period for distance/buffer calculations
input int      SwingLookback       = 100;          // How many bars back to search for swing high/low
input int      SwingBars           = 2;            // Number of bars on each side for fractal detection (Williams fractal)
input double   SLBufferATR         = 0.1;          // SL buffer as ATR multiplier (e.g. 0.1 = 10% of ATR)
input int      MagicNumber         = 123456;       // Magic number for order identification

//--- Global variables
int            emaHandle;                       // Handle for the EMA indicator
int            atrHandle;                       // Handle for the ATR indicator
datetime       lastBarTime;                     // Track last bar time to detect new bars
bool           tradeOpenedThisBar;             // Prevent multiple opens on same bar
datetime       lastWaitingLogTime;             // Track last "waiting for new bar" log time

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Create EMA indicator handle (uses chart's current timeframe)
   emaHandle = iMA(_Symbol, _Period, EMA_Period, EMA_Shift, MODE_EMA, PRICE_CLOSE);
   if(emaHandle == INVALID_HANDLE)
   {
      Print("Failed to create EMA indicator handle. Error: ", GetLastError());
      return(INIT_FAILED);
   }

   //--- Create ATR indicator handle (uses chart's current timeframe)
   atrHandle = iATR(_Symbol, _Period, ATR_Period);
   if(atrHandle == INVALID_HANDLE)
   {
      Print("Failed to create ATR indicator handle. Error: ", GetLastError());
      return(INIT_FAILED);
   }

   //--- Set the EMA to display on the chart (red line)
   //--- We use ChartIndicatorAdd to show it on the main chart window
   ChartIndicatorAdd(0, 0, emaHandle);

   lastBarTime = 0;
   tradeOpenedThisBar = false;
   lastWaitingLogTime = 0;

   Print("Multi-Symbol EMA EA initialized successfully on ", _Symbol, " ", EnumToString(_Period));
   Print("EMA Period: ", EMA_Period, " | Shift: ", EMA_Shift, " | Method: EMA | Apply: Close");
   Print("ATR Period: ", ATR_Period, " | Max EMA Distance: ", MaxEMADistanceATR, "x ATR | SL Buffer: ", SLBufferATR, "x ATR");
   Print("Dynamic Lot Sizing: Min=", MinLotSize, " | Per ", LotBalanceStep, " balance=", LotPerBalance, " lots | Max=", MaxLotSize);
   Print("Initial calculated lot size: ", CalculateLotSize());

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                    |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Remove indicator from chart
   if(emaHandle != INVALID_HANDLE)
   {
      ChartIndicatorDelete(0, 0, "MA(" + IntegerToString(EMA_Period) + ")");
      IndicatorRelease(emaHandle);
   }

   if(atrHandle != INVALID_HANDLE)
   {
      IndicatorRelease(atrHandle);
   }

   Print("Multi-Symbol EMA EA deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Get current ATR value                                              |
//+------------------------------------------------------------------+
double GetATRValue(int shift = 1)
{
   double atrValues[];
   ArraySetAsSeries(atrValues, true);
   if(CopyBuffer(atrHandle, 0, shift, 1, atrValues) < 1)
   {
      Print("[DIAG] Failed to copy ATR buffer. Error: ", GetLastError());
      return 0;
   }
   return atrValues[0];
}

//+------------------------------------------------------------------+
//| Expert tick function                                                |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Detect new bar
   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   if(currentBarTime == lastBarTime)
   {
      //--- Log "Waiting for new bar..." once per minute
      datetime now = TimeCurrent();
      if(now - lastWaitingLogTime >= 60)
      {
         Print("[DIAG] Waiting for new bar... (last bar: ", TimeToString(lastBarTime, TIME_DATE|TIME_MINUTES), ")");
         lastWaitingLogTime = now;
      }
      return;  // Not a new bar, skip
   }

   lastBarTime = currentBarTime;
   tradeOpenedThisBar = false;
   Print("[DIAG] ===== New bar detected at ", TimeToString(currentBarTime, TIME_DATE|TIME_MINUTES|TIME_SECONDS), " =====");

   //--- Check if we have an open position - only close at candle close if in profit
   if(HasOpenPosition())
   {
      if(IsPositionInProfit())
      {
         CloseOpenPosition();
         Print("[DIAG] Position closed at candle close - was in profit.");
      }
      else
      {
         Print("[DIAG] Position in loss - holding. Waiting for next candle close or SL hit.");
      }
      return;  // Either closed in profit or holding in loss - do not open new trade
   }

   //--- Get ATR value for distance and buffer calculations
   double atrValue = GetATRValue(1);
   if(atrValue == 0)
   {
      Print("[DIAG] ATR value is 0 or unavailable. Skipping this bar.");
      return;
   }

   //--- No open position, check for entry signals
   //--- Get EMA values for the last 3 completed bars (index 1, 2, 3)
   double emaValues[];
   ArraySetAsSeries(emaValues, true);
   if(CopyBuffer(emaHandle, 0, 1, 3, emaValues) < 3)
   {
      Print("[DIAG] Failed to copy EMA buffer. Error: ", GetLastError());
      return;
   }

   //--- Get close prices for the last 2 completed bars
   double close1 = iClose(_Symbol, _Period, 1);  // Most recent completed bar
   double close2 = iClose(_Symbol, _Period, 2);  // Bar before that

   //--- EMA values corresponding to bars
   double ema1 = emaValues[0];  // EMA at bar index 1 (most recent completed)
   double ema2 = emaValues[1];  // EMA at bar index 2

   //--- Current price (for discount zone check)
   double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double currentEMA = 0;
   double emaCurrentBar[];
   ArraySetAsSeries(emaCurrentBar, true);
   if(CopyBuffer(emaHandle, 0, 0, 1, emaCurrentBar) >= 1)
      currentEMA = emaCurrentBar[0];
   else
   {
      Print("[DIAG] Failed to copy current EMA buffer. Skipping.");
      return;
   }

   //--- Calculate max allowed distance from EMA using ATR
   double maxDistance = MaxEMADistanceATR * atrValue;

   //--- Determine signal direction
   bool sellSignal = (close1 < ema1 && close2 < ema2 && currentBid < currentEMA);
   bool buySignal  = (close1 > ema1 && close2 > ema2 && currentAsk > currentEMA);

   //--- Log signal check details
   string signalStr = "NONE";
   if(sellSignal) signalStr = "SELL";
   else if(buySignal) signalStr = "BUY";

   Print("[DIAG] Signal check: close1=", DoubleToString(close1, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)),
         " ema1=", DoubleToString(ema1, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)),
         " close2=", DoubleToString(close2, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)),
         " ema2=", DoubleToString(ema2, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)),
         " -> ", signalStr);
   Print("[DIAG]   CurrentAsk=", DoubleToString(currentAsk, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)),
         " CurrentBid=", DoubleToString(currentBid, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)),
         " CurrentEMA=", DoubleToString(currentEMA, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)),
         " ATR=", DoubleToString(atrValue, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)));

   if(!sellSignal && !buySignal)
   {
      Print("[DIAG] No signal conditions met. Waiting for next bar.");
      return;
   }

   //--- SELL Signal: 2 consecutive candles close below EMA AND current price is below EMA
   if(sellSignal)
   {
      //--- Check discount zone: price should be near EMA (not too far below)
      double distanceFromEMA = MathAbs(currentBid - currentEMA);
      Print("[DIAG] SELL discount zone check: Distance from EMA = ", DoubleToString(distanceFromEMA, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)),
            " (max allowed: ", DoubleToString(maxDistance, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)), " = ", MaxEMADistanceATR, "x ATR)");

      if(distanceFromEMA <= maxDistance)
      {
         Print("[DIAG] Discount zone PASSED. Looking for swing high for SL...");
         double sl = FindLastSwingHigh();  // SL = Most recent swing high (fractal high)
         if(sl == 0)
         {
            Print("[DIAG] No swing high found within lookback. Skipping SELL.");
         }
         else
         {
            double slBuffer = SLBufferATR * atrValue;
            sl += slBuffer;  // Add ATR-based buffer above swing high
            Print("[DIAG] Opening SELL with SL=", DoubleToString(sl, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)),
                  " (buffer=", DoubleToString(slBuffer, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)), ")");
            OpenSell(sl);
         }
      }
      else
      {
         Print("[DIAG] Discount zone FAILED. Price too far from EMA. Distance=",
               DoubleToString(distanceFromEMA, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)),
               " > MaxAllowed=", DoubleToString(maxDistance, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)),
               ". Trade SKIPPED.");
      }
   }
   //--- BUY Signal: 2 consecutive candles close above EMA AND current price is above EMA
   else if(buySignal)
   {
      //--- Check discount zone: price should be near EMA (not too far above)
      double distanceFromEMA = MathAbs(currentAsk - currentEMA);
      Print("[DIAG] BUY discount zone check: Distance from EMA = ", DoubleToString(distanceFromEMA, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)),
            " (max allowed: ", DoubleToString(maxDistance, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)), " = ", MaxEMADistanceATR, "x ATR)");

      if(distanceFromEMA <= maxDistance)
      {
         Print("[DIAG] Discount zone PASSED. Looking for swing low for SL...");
         double sl = FindLastSwingLow();  // SL = Most recent swing low (fractal low)
         if(sl == 0)
         {
            Print("[DIAG] No swing low found within lookback. Skipping BUY.");
         }
         else
         {
            double slBuffer = SLBufferATR * atrValue;
            sl -= slBuffer;  // Subtract ATR-based buffer below swing low
            Print("[DIAG] Opening BUY with SL=", DoubleToString(sl, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)),
                  " (buffer=", DoubleToString(slBuffer, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)), ")");
            OpenBuy(sl);
         }
      }
      else
      {
         Print("[DIAG] Discount zone FAILED. Price too far from EMA. Distance=",
               DoubleToString(distanceFromEMA, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)),
               " > MaxAllowed=", DoubleToString(maxDistance, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)),
               ". Trade SKIPPED.");
      }
   }
}

//+------------------------------------------------------------------+
//| Find the most recent swing high (fractal high)                     |
//| A fractal high is a bar whose high is STRICTLY greater than the    |
//| highs of SwingBars bars on each side (true Williams fractal).      |
//| Returns 0 if no swing high found within lookback range.            |
//+------------------------------------------------------------------+
double FindLastSwingHigh()
{
   //--- Start searching from bar index SwingBars+1 (need SwingBars bars on the right/recent side)
   //--- The minimum bar that can be a confirmed fractal is SwingBars+1 (bars 1..SwingBars are on its right)
   int startBar = SwingBars + 1;
   int endBar   = SwingLookback;

   Print("FindLastSwingHigh: Searching bars ", startBar, " to ", endBar, " with SwingBars=", SwingBars);

   for(int i = startBar; i <= endBar; i++)
   {
      double highI = iHigh(_Symbol, _Period, i);
      bool isFractal = true;

      //--- Check SwingBars bars on each side - STRICT greater than required
      for(int j = 1; j <= SwingBars; j++)
      {
         double highLeft  = iHigh(_Symbol, _Period, i + j);  // Older bars (left side)
         double highRight = iHigh(_Symbol, _Period, i - j);  // Newer bars (right side)

         if(highI <= highLeft || highI <= highRight)
         {
            isFractal = false;
            break;
         }
      }

      if(isFractal)
      {
         //--- Log detailed info about the fractal found
         Print("=== SWING HIGH FOUND ===");
         Print("  Bar index: ", i, " | High: ", highI);
         Print("  Time: ", TimeToString(iTime(_Symbol, _Period, i)));
         for(int j = 1; j <= SwingBars; j++)
         {
            Print("  Left[", j, "] bar ", i+j, " high=", iHigh(_Symbol, _Period, i+j),
                  " | Right[", j, "] bar ", i-j, " high=", iHigh(_Symbol, _Period, i-j));
         }
         Print("========================");
         return highI;
      }
   }

   Print("FindLastSwingHigh: No fractal high found within ", endBar, " bars.");
   return 0;  // No swing high found
}

//+------------------------------------------------------------------+
//| Find the most recent swing low (fractal low)                       |
//| A fractal low is a bar whose low is STRICTLY lower than the lows   |
//| of SwingBars bars on each side (true Williams fractal).            |
//| Returns 0 if no swing low found within lookback range.             |
//+------------------------------------------------------------------+
double FindLastSwingLow()
{
   //--- Start searching from bar index SwingBars+1 (need SwingBars bars on the right/recent side)
   int startBar = SwingBars + 1;
   int endBar   = SwingLookback;

   Print("FindLastSwingLow: Searching bars ", startBar, " to ", endBar, " with SwingBars=", SwingBars);

   for(int i = startBar; i <= endBar; i++)
   {
      double lowI = iLow(_Symbol, _Period, i);
      bool isFractal = true;

      //--- Check SwingBars bars on each side - STRICT less than required
      for(int j = 1; j <= SwingBars; j++)
      {
         double lowLeft  = iLow(_Symbol, _Period, i + j);  // Older bars (left side)
         double lowRight = iLow(_Symbol, _Period, i - j);  // Newer bars (right side)

         if(lowI >= lowLeft || lowI >= lowRight)
         {
            isFractal = false;
            break;
         }
      }

      if(isFractal)
      {
         //--- Log detailed info about the fractal found
         Print("=== SWING LOW FOUND ===");
         Print("  Bar index: ", i, " | Low: ", lowI);
         Print("  Time: ", TimeToString(iTime(_Symbol, _Period, i)));
         for(int j = 1; j <= SwingBars; j++)
         {
            Print("  Left[", j, "] bar ", i+j, " low=", iLow(_Symbol, _Period, i+j),
                  " | Right[", j, "] bar ", i-j, " low=", iLow(_Symbol, _Period, i-j));
         }
         Print("========================");
         return lowI;
      }
   }

   Print("FindLastSwingLow: No fractal low found within ", endBar, " bars.");
   return 0;  // No swing low found
}

//+------------------------------------------------------------------+
//| Check if there is an open position for this EA                     |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         {
            return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Check if the open position is in profit                            |
//+------------------------------------------------------------------+
bool IsPositionInProfit()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         {
            double profit = PositionGetDouble(POSITION_PROFIT);
            double swap   = PositionGetDouble(POSITION_SWAP);
            //--- Consider total profit including swap
            double totalProfit = profit + swap;
            return (totalProfit > 0);
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Close the open position for this EA                                |
//+------------------------------------------------------------------+
void CloseOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         {
            long posType = PositionGetInteger(POSITION_TYPE);
            double volume = PositionGetDouble(POSITION_VOLUME);

            MqlTradeRequest request = {};
            MqlTradeResult  result  = {};

            request.action    = TRADE_ACTION_DEAL;
            request.symbol    = _Symbol;
            request.volume    = volume;
            request.magic     = MagicNumber;
            request.deviation = 10;

            if(posType == POSITION_TYPE_BUY)
            {
               request.type  = ORDER_TYPE_SELL;
               request.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            }
            else if(posType == POSITION_TYPE_SELL)
            {
               request.type  = ORDER_TYPE_BUY;
               request.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            }

            request.position = ticket;

            if(!OrderSend(request, result))
            {
               Print("Failed to close position. Ticket: ", ticket, " Error: ", GetLastError(),
                     " Retcode: ", result.retcode);
            }
            else
            {
               Print("Position closed. Ticket: ", ticket, " Price: ", result.price);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate dynamic lot size based on account balance                 |
//| Scales lot size as balance grows for compounding effect             |
//+------------------------------------------------------------------+
double CalculateLotSize()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);

   //--- Calculate lot size: LotPerBalance lots for every LotBalanceStep in balance
   double lots = MathFloor(balance / LotBalanceStep) * LotPerBalance;

   //--- Enforce minimum lot size
   if(lots < MinLotSize)
      lots = MinLotSize;

   //--- Enforce maximum lot size
   if(lots > MaxLotSize)
      lots = MaxLotSize;

   //--- Normalize to broker's lot step
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(lotStep > 0)
      lots = MathFloor(lots / lotStep) * lotStep;

   //--- Final check against broker minimums and maximums
   double brokerMinLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double brokerMaxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   if(lots < brokerMinLot)
      lots = brokerMinLot;
   if(lots > brokerMaxLot)
      lots = brokerMaxLot;

   return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
//| Open a BUY position                                                |
//+------------------------------------------------------------------+
void OpenBuy(double sl)
{
   if(tradeOpenedThisBar)
      return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   //--- Normalize SL
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   sl = NormalizeDouble(sl, digits);

   MqlTradeRequest request = {};
   MqlTradeResult  result  = {};

   request.action    = TRADE_ACTION_DEAL;
   request.symbol    = _Symbol;
   request.volume    = CalculateLotSize();
   request.type      = ORDER_TYPE_BUY;
   request.price     = ask;
   request.sl        = sl;
   request.tp        = 0;  // No fixed TP
   request.magic     = MagicNumber;
   request.deviation = 10;
   request.comment   = "EMA Buy";

   if(!OrderSend(request, result))
   {
      Print("BUY order failed. Error: ", GetLastError(), " Retcode: ", result.retcode);
   }
   else
   {
      Print("BUY order opened. Price: ", result.price, " SL: ", sl,
            " Lots: ", request.volume, " Ticket: ", result.order);
      Print("  >> SL placed at swing low level (with ATR buffer). Entry=", result.price, " SL=", sl,
            " Distance=", NormalizeDouble(MathAbs(result.price - sl), digits));
      tradeOpenedThisBar = true;
   }
}

//+------------------------------------------------------------------+
//| Open a SELL position                                               |
//+------------------------------------------------------------------+
void OpenSell(double sl)
{
   if(tradeOpenedThisBar)
      return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   //--- Normalize SL
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   sl = NormalizeDouble(sl, digits);

   MqlTradeRequest request = {};
   MqlTradeResult  result  = {};

   request.action    = TRADE_ACTION_DEAL;
   request.symbol    = _Symbol;
   request.volume    = CalculateLotSize();
   request.type      = ORDER_TYPE_SELL;
   request.price     = bid;
   request.sl        = sl;
   request.tp        = 0;  // No fixed TP
   request.magic     = MagicNumber;
   request.deviation = 10;
   request.comment   = "EMA Sell";

   if(!OrderSend(request, result))
   {
      Print("SELL order failed. Error: ", GetLastError(), " Retcode: ", result.retcode);
   }
   else
   {
      Print("SELL order opened. Price: ", result.price, " SL: ", sl,
            " Lots: ", request.volume, " Ticket: ", result.order);
      Print("  >> SL placed at swing high level (with ATR buffer). Entry=", result.price, " SL=", sl,
            " Distance=", NormalizeDouble(MathAbs(sl - result.price), digits));
      tradeOpenedThisBar = true;
   }
}

//+------------------------------------------------------------------+
