#property copyright "Copyright 2025, Aleksandr Kazakov"
#property version   "1.00"
#property description "Sets SL to breakeven and closes 50% of the position on the current chart symbol."

#include <Trade\Trade.mqh>

CTrade trade;
const double closePercent = 0.50;

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
      double volume = PositionGetDouble(POSITION_VOLUME);
      long posType = PositionGetInteger(POSITION_TYPE);

      //--- Set SL to BE (skip if already at or beyond BE)
      bool slAtOrBeyondBE = false;
      if(posType == POSITION_TYPE_BUY && currentSL >= openPrice && currentSL > 0)
         slAtOrBeyondBE = true;
      if(posType == POSITION_TYPE_SELL && currentSL <= openPrice && currentSL > 0)
         slAtOrBeyondBE = true;

      if(!slAtOrBeyondBE)
      {
         if(trade.PositionModify(ticket, openPrice, currentTP))
            Print("SL set to BE (", openPrice, ") for ", currentSymbol);
         else
         {
            Print("Failed to set SL to BE. Result code: ", trade.ResultRetcode(), ", Message: ", trade.ResultComment());
            Alert("Error: Could not set SL to BE. Check the Journal tab for details.");
         }
      }

      //--- Partial close
      double volumeStep = SymbolInfoDouble(currentSymbol, SYMBOL_VOLUME_STEP);
      double volumeMin = SymbolInfoDouble(currentSymbol, SYMBOL_VOLUME_MIN);

      int lotDecimals = 0;
      if(volumeStep == 0.01) lotDecimals = 2;
      else if(volumeStep == 0.1) lotDecimals = 1;
      else if(volumeStep == 1.0) lotDecimals = 0;
      else lotDecimals = 8;

      double closeVolume = NormalizeDouble(MathFloor(volume * closePercent / volumeStep) * volumeStep, lotDecimals);

      if(closeVolume < volumeMin)
      {
         Alert("Close volume (", closeVolume, ") is below minimum (", volumeMin, "). Skipping partial close.");
         return;
      }

      if(trade.PositionClosePartial(ticket, closeVolume))
      {
         Print("Closed ", closePercent * 100, "% (", closeVolume, " lots) of ", currentSymbol);
         Alert("Success! Closed ", closeVolume, " lots (", closePercent * 100, "%) on ", currentSymbol);
      }
      else
      {
         Print("Failed to partially close. Result code: ", trade.ResultRetcode(), ", Message: ", trade.ResultComment());
         Alert("Error: Could not partially close position. Check the Journal tab for details.");
      }
      return;
   }

   if(!found)
   {
      Alert("No open position found on ", currentSymbol);
   }
}