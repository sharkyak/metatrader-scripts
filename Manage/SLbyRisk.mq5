#property copyright "Copyright 2025, Aleksandr Kazakov"
#property version   "1.30"

#include <Trade\Trade.mqh>

//--- EA Inputs
input double RiskAmount        = 20.0; // Risk amount in deposit currency
input double RiskRewardRatio   = 2.0;  // Risk to Reward Ratio (e.g., 2 for 1:2)

//--- Global variables
const string GvPrefix = "EA_PROCESSED_";
CTrade       trade;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("ManageManualOrders EA started. Will monitor trades continuously.");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("ManageManualOrders EA stopped. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Iterate through all open positions on every tick
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      //--- Get position ticket
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         //--- Get position properties
         double sl = PositionGetDouble(POSITION_SL);
         string symbol = PositionGetString(POSITION_SYMBOL);

         //--- 1. Check if the order already has a stop loss
         if(sl > 0)
         {
            continue; // Already has SL, skip to the next position
         }

         //--- 2. Check if the order has already been processed by this EA
         if(GlobalVariableCheck(GvPrefix + (string)ticket))
         {
            continue; // Already processed, skip to the next position
         }
         
         //--- If we reached here, the order needs SL/TP. Process it.
         ProcessOrder(ticket, symbol);
      }
   }
}

//+------------------------------------------------------------------+
//| Process a single order to set SL and TP                          |
//+------------------------------------------------------------------+
void ProcessOrder(ulong ticket, string symbol)
{
   //--- Get position properties
   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double volume = PositionGetDouble(POSITION_VOLUME);
   ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

   //--- Get symbol properties for SL/TP calculation
   double tickValue, tickSize;
   long   digits = 0;

   //--- Add checks to ensure symbol info was retrieved successfully
   if(!SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE, tickValue) || 
      !SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE, tickSize)  ||
      !SymbolInfoInteger(symbol, SYMBOL_DIGITS, digits))
   {
      Print("Could not retrieve symbol info for ", symbol);
      return;
   }
   
   if(tickValue <= 0 || tickSize <= 0)
   {
      Print("Invalid tick value or tick size for symbol: ", symbol);
      return;
   }

   //--- Calculate SL and TP distances in price points
   double pointsToRisk = (RiskAmount / (tickValue * volume)) * tickSize;
   double slDistance = NormalizeDouble(pointsToRisk, (int)digits);
   double tpDistance = NormalizeDouble(slDistance * RiskRewardRatio, (int)digits);

   double newSL = 0;
   double newTP = 0;

   //--- Determine SL and TP price levels based on position type
   if(type == POSITION_TYPE_BUY)
   {
      newSL = openPrice - slDistance;
      newTP = openPrice + tpDistance;
   }
   else if(type == POSITION_TYPE_SELL)
   {
      newSL = openPrice + slDistance;
      newTP = openPrice - tpDistance;
   }

   //--- Send the modification request to the trade server
   if(trade.PositionModify(ticket, newSL, newTP))
   {
      Print("Successfully set SL and TP for ticket #", ticket);
      //--- Mark order as processed by setting a global variable
      GlobalVariableSet(GvPrefix + (string)ticket, 1);
   }
   else
   {
      Print("Error modifying position for ticket #", ticket, ". Error code: ", GetLastError());
   }
}