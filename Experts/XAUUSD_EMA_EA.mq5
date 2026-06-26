//+------------------------------------------------------------------+
//|                                              XAUUSD_EMA_EA.mq5   |
//|                        XAUUSD M1 EMA Scalper Expert Advisor       |
//|                                                                    |
//| Trades XAUUSD on the 1-minute chart using a 9-period EMA.         |
//| BUY only ABOVE EMA: 2 consecutive M1 candles close above EMA      |
//|       and price is above EMA -> buy on next candle open.           |
//|       SL = Most recent swing low (fractal low).                    |
//| SELL only BELOW EMA: 2 consecutive M1 candles close below EMA      |
//|       and price is below EMA -> sell on next candle open.          |
//|       SL = Most recent swing high (fractal high).                  |
//| TP:   None fixed. Trade closes at candle close ONLY if in profit.  |
//|       If in loss, trade stays open until SL hits or next candle     |
//|       close is in profit.                                           |
//| Only 1 trade at a time. Price must be near EMA (discount zone).    |
//+------------------------------------------------------------------+
#property copyright "AMA EA"
#property link      ""
#property version   "1.00"
#property strict

//--- Input parameters
input int      EMA_Period       = 9;            // EMA Period
input int      EMA_Shift        = 0;            // EMA Shift
input double   MinLotSize       = 0.20;         // Minimum lot size
input double   LotPerBalance    = 0.20;         // Lots per LotBalanceStep of balance
input double   LotBalanceStep   = 1000.0;       // Balance increment for lot increase (e.g. every $1000)
input double   MaxLotSize       = 10.0;         // Maximum lot size cap
input double   MaxEMADistance   = 50.0;         // Max distance from EMA in points (discount zone filter)
input int      SwingLookback    = 50;           // How many bars back to search for swing high/low
input int      SwingBars        = 2;            // Number of bars on each side for fractal detection
input double   SLBufferPoints   = 5.0;          // Buffer in points beyond swing level for SL
input int      MagicNumber      = 123456;       // Magic number for order identification

//--- Global variables
int            emaHandle;                       // Handle for the EMA indicator
datetime       lastBarTime;                     // Track last bar time to detect new bars
bool           tradeOpenedThisBar;             // Prevent multiple opens on same bar

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Check symbol
   if(_Symbol != "XAUUSD")
   {
      Print("This EA is designed for XAUUSD only. Current symbol: ", _Symbol);
      return(INIT_FAILED);
   }

   //--- Check timeframe
   if(_Period != PERIOD_M1)
   {
      Print("This EA is designed for M1 timeframe only. Current timeframe: ", EnumToString(_Period));
      return(INIT_FAILED);
   }

   //--- Create EMA indicator handle
   emaHandle = iMA(_Symbol, PERIOD_M1, EMA_Period, EMA_Shift, MODE_EMA, PRICE_CLOSE);
   if(emaHandle == INVALID_HANDLE)
   {
      Print("Failed to create EMA indicator handle. Error: ", GetLastError());
      return(INIT_FAILED);
   }

   //--- Set the EMA to display on the chart (red line)
   //--- We use ChartIndicatorAdd to show it on the main chart window
   ChartIndicatorAdd(0, 0, emaHandle);

   lastBarTime = 0;
   tradeOpenedThisBar = false;

   Print("XAUUSD EMA EA initialized successfully.");
   Print("EMA Period: ", EMA_Period, " | Shift: ", EMA_Shift, " | Method: EMA | Apply: Close");
   Print("Max EMA Distance: ", MaxEMADistance, " points");
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

   Print("XAUUSD EMA EA deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                                |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Detect new bar
   datetime currentBarTime = iTime(_Symbol, PERIOD_M1, 0);
   if(currentBarTime == lastBarTime)
      return;  // Not a new bar, skip

   lastBarTime = currentBarTime;
   tradeOpenedThisBar = false;

   //--- Check if we have an open position - only close at candle close if in profit
   if(HasOpenPosition())
   {
      if(IsPositionInProfit())
      {
         CloseOpenPosition();
         Print("Position closed at candle close - was in profit.");
      }
      else
      {
         Print("Position in loss - holding. Waiting for next candle close or SL hit.");
      }
      return;  // Either closed in profit or holding in loss - do not open new trade
   }

   //--- No open position, check for entry signals
   //--- Get EMA values for the last 3 completed bars (index 1, 2, 3)
   double emaValues[];
   ArraySetAsSeries(emaValues, true);
   if(CopyBuffer(emaHandle, 0, 1, 3, emaValues) < 3)
   {
      Print("Failed to copy EMA buffer. Error: ", GetLastError());
      return;
   }

   //--- Get close prices for the last 2 completed bars
   double close1 = iClose(_Symbol, PERIOD_M1, 1);  // Most recent completed bar
   double close2 = iClose(_Symbol, PERIOD_M1, 2);  // Bar before that

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
      return;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   //--- SELL Signal: 2 consecutive candles close below EMA AND current price is below EMA
   if(close1 < ema1 && close2 < ema2 && currentBid < currentEMA)
   {
      //--- Check discount zone: price should be near EMA (not too far below)
      double distanceFromEMA = MathAbs(currentBid - currentEMA) / point;
      if(distanceFromEMA <= MaxEMADistance)
      {
         double sl = FindLastSwingHigh();  // SL = Most recent swing high (fractal high)
         if(sl == 0)
         {
            Print("No swing high found within lookback. Skipping SELL.");
         }
         else
         {
            sl += SLBufferPoints * point;  // Add buffer above swing high
            OpenSell(sl);
         }
      }
   }
   //--- BUY Signal: 2 consecutive candles close above EMA AND current price is above EMA
   else if(close1 > ema1 && close2 > ema2 && currentAsk > currentEMA)
   {
      //--- Check discount zone: price should be near EMA (not too far above)
      double distanceFromEMA = MathAbs(currentAsk - currentEMA) / point;
      if(distanceFromEMA <= MaxEMADistance)
      {
         double sl = FindLastSwingLow();  // SL = Most recent swing low (fractal low)
         if(sl == 0)
         {
            Print("No swing low found within lookback. Skipping BUY.");
         }
         else
         {
            sl -= SLBufferPoints * point;  // Add buffer below swing low
            OpenBuy(sl);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Find the most recent swing high (fractal high)                     |
//| A fractal high is a bar whose high is greater than the highs of    |
//| SwingBars bars on each side.                                        |
//| Returns 0 if no swing high found within lookback range.            |
//+------------------------------------------------------------------+
double FindLastSwingHigh()
{
   //--- Start searching from bar index SwingBars+1 (need SwingBars bars on the right/recent side)
   //--- The minimum bar that can be a confirmed fractal is SwingBars+1 (bars 1..SwingBars are on its right)
   int startBar = SwingBars + 1;
   int endBar   = SwingLookback;

   for(int i = startBar; i <= endBar; i++)
   {
      double highI = iHigh(_Symbol, PERIOD_M1, i);
      bool isFractal = true;

      //--- Check SwingBars bars on each side
      for(int j = 1; j <= SwingBars; j++)
      {
         double highLeft  = iHigh(_Symbol, PERIOD_M1, i + j);  // Older bars (left side)
         double highRight = iHigh(_Symbol, PERIOD_M1, i - j);  // Newer bars (right side)

         if(highI < highLeft || highI < highRight)
         {
            isFractal = false;
            break;
         }
      }

      if(isFractal)
      {
         Print("Swing High found at bar ", i, " High: ", highI);
         return highI;
      }
   }

   return 0;  // No swing high found
}

//+------------------------------------------------------------------+
//| Find the most recent swing low (fractal low)                       |
//| A fractal low is a bar whose low is lower than the lows of         |
//| SwingBars bars on each side.                                        |
//| Returns 0 if no swing low found within lookback range.             |
//+------------------------------------------------------------------+
double FindLastSwingLow()
{
   //--- Start searching from bar index SwingBars+1 (need SwingBars bars on the right/recent side)
   int startBar = SwingBars + 1;
   int endBar   = SwingLookback;

   for(int i = startBar; i <= endBar; i++)
   {
      double lowI = iLow(_Symbol, PERIOD_M1, i);
      bool isFractal = true;

      //--- Check SwingBars bars on each side
      for(int j = 1; j <= SwingBars; j++)
      {
         double lowLeft  = iLow(_Symbol, PERIOD_M1, i + j);  // Older bars (left side)
         double lowRight = iLow(_Symbol, PERIOD_M1, i - j);  // Newer bars (right side)

         if(lowI > lowLeft || lowI > lowRight)
         {
            isFractal = false;
            break;
         }
      }

      if(isFractal)
      {
         Print("Swing Low found at bar ", i, " Low: ", lowI);
         return lowI;
      }
   }

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
      tradeOpenedThisBar = true;
   }
}

//+------------------------------------------------------------------+
