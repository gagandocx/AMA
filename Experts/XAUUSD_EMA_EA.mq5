//+------------------------------------------------------------------+
//|                                              XAUUSD_EMA_EA.mq5   |
//|                        XAUUSD M1 EMA Scalper Expert Advisor       |
//|                                                                    |
//| Trades XAUUSD on the 1-minute chart using a 9-period EMA.         |
//| BUY only ABOVE EMA: 2 consecutive M1 candles close above EMA      |
//|       and price is above EMA -> buy on next candle open.           |
//|       SL = Low of previous candle.                                 |
//| SELL only BELOW EMA: 2 consecutive M1 candles close below EMA      |
//|       and price is below EMA -> sell on next candle open.          |
//|       SL = High of previous candle.                                |
//| TP:   None fixed. Trade closes at current candle close.            |
//| Only 1 trade at a time. Price must be near EMA (discount zone).    |
//+------------------------------------------------------------------+
#property copyright "AMA EA"
#property link      ""
#property version   "1.00"
#property strict

//--- Input parameters
input int      EMA_Period       = 9;            // EMA Period
input int      EMA_Shift        = 0;            // EMA Shift
input double   LotSize          = 0.01;         // Lot size
input double   MaxEMADistance   = 50.0;         // Max distance from EMA in points (discount zone filter)
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
   Print("Max EMA Distance: ", MaxEMADistance, " points | Lot Size: ", LotSize);

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

   //--- Check if we have an open position - close it at candle close (previous candle just closed)
   if(HasOpenPosition())
   {
      CloseOpenPosition();
      return;  // Wait for next bar to open a new trade
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

   //--- Get high/low of the most recent completed bar (for SL)
   double high1 = iHigh(_Symbol, PERIOD_M1, 1);
   double low1  = iLow(_Symbol, PERIOD_M1, 1);

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
         double sl = high1;  // SL = High of previous candle
         OpenSell(sl);
      }
   }
   //--- BUY Signal: 2 consecutive candles close above EMA AND current price is above EMA
   else if(close1 > ema1 && close2 > ema2 && currentAsk > currentEMA)
   {
      //--- Check discount zone: price should be near EMA (not too far above)
      double distanceFromEMA = MathAbs(currentAsk - currentEMA) / point;
      if(distanceFromEMA <= MaxEMADistance)
      {
         double sl = low1;  // SL = Low of previous candle
         OpenBuy(sl);
      }
   }
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
   request.volume    = LotSize;
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
      Print("BUY order opened. Price: ", result.price, " SL: ", sl, " Ticket: ", result.order);
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
   request.volume    = LotSize;
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
      Print("SELL order opened. Price: ", result.price, " SL: ", sl, " Ticket: ", result.order);
      tradeOpenedThisBar = true;
   }
}

//+------------------------------------------------------------------+
