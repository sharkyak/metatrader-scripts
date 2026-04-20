#property copyright "Copyright 2025, Aleksandr Kazakov"
#property version   "1.00"
#property description "Sets Stop Loss to breakeven on the open position for the current chart symbol."

#include <Trade\Trade.mqh>

CTrade trade;

void OnStart()
{
   string currentSymbol = _Symbol;
   int digits = (int)SymbolInfoInteger(currentSymbol, SYMBOL_DIGITS);

   //--- Find open position on this symbol
   int totalPositions = PositionsTotal();
   bool found = false;

   for(int i = 0; i < totalPositions; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;

      if(PositionGetString(POSITION_SYMBOL) != currentSymbol) continue;

      found = true;

      double openPrice = NormalizeDouble(PositionGetDouble(POSITION_PRICE_OPEN), digits);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      long posType = PositionGetInteger(POSITION_TYPE);

      //--- Check if SL is already at or beyond BE
      if(posType == POSITION_TYPE_BUY && currentSL >= openPrice && currentSL > 0)
      {
         Alert("SL is already at or beyond BE (SL: ", currentSL, ", Open: ", openPrice, "). No change.");
         return;
      }
      if(posType == POSITION_TYPE_SELL && currentSL <= openPrice && currentSL > 0)
      {
         Alert("SL is already at or beyond BE (SL: ", currentSL, ", Open: ", openPrice, "). No change.");
         return;
      }

      //--- Set SL to BE
      if(trade.PositionModify(ticket, openPrice, currentTP))
      {
         Print("SL set to BE (", openPrice, ") for ", currentSymbol);
         Alert("Success! SL set to BE at ", openPrice, " on ", currentSymbol);
      }
      else
      {
         Print("Failed to modify position. Result code: ", trade.ResultRetcode(), ", Message: ", trade.ResultComment());
         Alert("Error: Could not set SL to BE. Check the Journal tab for details.");
      }
      return;
   }

   if(!found)
   {
      Alert("No open position found on ", currentSymbol);
   }
}