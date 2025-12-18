#property copyright "Copyright 2025, Aleksand Kazakov"
#property version   "1.21"
#property description "Calculates lot size based on SL price and risk in USD, then opens a single SELL position."
#property script_show_inputs

#include <Trade\Trade.mqh>

//--- Script Input Parameters
input double InpStopLossPrice = 0;      // Stop Loss Price Level
input double InpRiskSizeUSD   = 20.0;   // Risk Size in USD

//--- Global CTrade instance
CTrade trade;

//+------------------------------------------------------------------+
//| Function to calculate the appropriate lot size                   |
//+------------------------------------------------------------------+
double CalculateLotSize(string symbol, double entryPrice, double stopLossPrice, double riskAmount)
{
   //--- Get symbol properties
   double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double volumeStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   double volumeMin = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double volumeMax = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   
   if(tickSize <= 0 || tickValue <= 0)
   {
      Alert("Error: Invalid symbol properties (Tick Size/Value) for ", symbol, ". Cannot calculate lot size.");
      return(0);
   }

   //--- Calculate the loss in account currency if 1 lot is traded
   // Formula: (Distance / TickSize) * TickValue
   // For a SELL, SL is above entry, so distance = SL - Entry
   double stopLossDistance = stopLossPrice - entryPrice;
   double lossPerLot = (stopLossDistance / tickSize) * tickValue;
   
   if(lossPerLot <= 0)
   {
      Alert("Error: Could not calculate loss per lot. Check prices and symbol info.");
      return(0);
   }
   
   //--- Calculate the raw lot size
   double calculatedLot = riskAmount / lossPerLot;
   
   //--- Normalize the lot size according to broker's rules
   // Using MathFloor to safely round down to the nearest step
   calculatedLot = MathFloor(calculatedLot / volumeStep) * volumeStep;
   
   // Ensure lot is normalized to standard decimals to avoid floating point anomalies (e.g. 0.0300000001)
   double lotDecimals = 0;
   if(volumeStep == 0.01) lotDecimals = 2;
   else if(volumeStep == 0.1) lotDecimals = 1;
   else if(volumeStep == 1.0) lotDecimals = 0;
   else lotDecimals = 8; // Fallback
   
   if(lotDecimals <= 2) calculatedLot = NormalizeDouble(calculatedLot, (int)lotDecimals);

   //--- Check against min and max lot size
   if(calculatedLot < volumeMin)
   {
      Alert("Warning: Calculated lot size (", calculatedLot, ") is smaller than the minimum allowed (", volumeMin, "). The minimum lot size will be used instead.");
      calculatedLot = volumeMin;
   }
   
   if(calculatedLot > volumeMax)
   {
      Alert("Warning: Calculated lot size (", calculatedLot, ") is larger than the maximum allowed (", volumeMax, "). The maximum lot size will be used instead.");
      calculatedLot = volumeMax;
   }
   
   return(calculatedLot);
}

//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void OnStart()
{
   //--- Get current symbol information
   string currentSymbol = _Symbol;
   
   // Refresh symbol data
   // Refresh symbol data
   double bidPrice = 0;
   if(!SymbolInfoDouble(currentSymbol, SYMBOL_BID, bidPrice)) 
   {
      Alert("Error: Failed to get Bid price for ", currentSymbol);
      return;
   }
   int digits = (int)SymbolInfoInteger(currentSymbol, SYMBOL_DIGITS);
   
   //--- 1. VALIDATE INPUTS ---
   // Essential check: Stop Loss for a SELL must be ABOVE the entry price
   if(InpStopLossPrice <= 0)
   {
      Alert("Error: Please specify a valid Stop Loss Price > 0.");
      return;
   }
   
   if(InpStopLossPrice <= bidPrice)
   {
      Alert("Error: For a SELL order, the Stop Loss Price must be above the current Bid Price (", bidPrice, ").");
      return;
   }
   
   // Normalize SL to prevent server rejection on some brokers
   double normSL = NormalizeDouble(InpStopLossPrice, digits);
   
   //--- 2. CALCULATE LOT SIZE ---
   // Note: We use 'bidPrice' for SELL entry
   double lotSize = CalculateLotSize(currentSymbol, bidPrice, normSL, InpRiskSizeUSD);
   
   if(lotSize <= 0)
   {
      // An alert is fired from the calculation function. Stop execution.
      return;
   }
   
   Print("Calculated Lot Size: ", lotSize, " for Symbol: ", currentSymbol);
   
   //--- 3. OPEN SELL POSITION ---
   Print("Attempting to open SELL position...");
   
   // trade.Sell(volume, symbol, price, sl, tp, comment)
   // Using normalized SL
   if(trade.Sell(lotSize, currentSymbol, bidPrice, normSL, 0, "QuickSell Script Order"))
   {
      Print("SELL order successfully placed for ", currentSymbol, " with lot size ", lotSize);
      Alert("Success! SELL order placed for ", lotSize, " lots on ", currentSymbol);
   }
   else
   {
      Print("Failed to place SELL order. Result code: ", trade.ResultRetcode(), ", Message: ", trade.ResultComment());
      Alert("Error: Could not place SELL order. Check the Journal tab for details.");
   }
}