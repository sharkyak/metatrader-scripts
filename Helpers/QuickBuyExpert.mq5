#property copyright "Copyright 2025, Aleksand Kazakov"
#property version   "1.20"
#property description "Calculates lot size based on SL price and risk in USD, then opens a single BUY position. Minimal version."

#include <Trade\Trade.mqh>

//--- Expert Advisor Input Parameters
input double InpStopLossPrice = 0;      // Stop Loss Price Level
input double InpRiskSizeUSD   = 20.0;   // Risk Size in USD

//--- Global CTrade instance
CTrade trade;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Get current symbol information
   string currentSymbol = _Symbol;
   SymbolInfoDouble(currentSymbol, SYMBOL_ASK); // Ensure market watch is updated with the latest prices
   double askPrice = SymbolInfoDouble(currentSymbol, SYMBOL_ASK);
   
   //--- 1. VALIDATE INPUTS ---
   // Essential check: Stop Loss for a BUY must be below the entry price
   if(InpStopLossPrice >= askPrice)
   {
      Alert("Error: For a BUY order, the Stop Loss Price must be below the current Ask Price (", askPrice, "). EA will be removed.");
      return(INIT_FAILED);
   }
   
   //--- 2. CALCULATE LOT SIZE ---
   double lotSize = CalculateLotSize(currentSymbol, askPrice, InpStopLossPrice, InpRiskSizeUSD);
   
   if(lotSize <= 0)
   {
      // An alert is fired from the calculation function. Stop execution.
      return(INIT_FAILED);
   }
   
   Print("Calculated Lot Size: ", lotSize, " for Symbol: ", currentSymbol);
   
   //--- 3. OPEN BUY POSITION ---
   Print("Attempting to open BUY position...");
   
   // The trade will be placed with a default magic number of 0
   bool result = trade.Buy(lotSize, currentSymbol, askPrice, InpStopLossPrice, 0, "QuickBuy EA Order");
   
   if(result)
   {
      Print("BUY order successfully placed for ", currentSymbol, " with lot size ", lotSize);
      Alert("Success! BUY order placed for ", lotSize, " lots on ", currentSymbol);
   }
   else
   {
      Print("Failed to place BUY order. Result code: ", trade.ResultRetcode(), ", Message: ", trade.ResultComment());
      Alert("Error: Could not place BUY order. Check the Experts or Journal tab for details.");
      return(INIT_FAILED);
   }

   //--- Initialization completed successfully
   Print("QuickBuyExpert has finished its task and will now remain idle.");
   return(INIT_SUCCEEDED);
}

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
   double stopLossDistance = entryPrice - stopLossPrice;
   double lossPerLot = (stopLossDistance / tickSize) * tickValue;
   
   if(lossPerLot <= 0)
   {
      Alert("Error: Could not calculate loss per lot. Check prices and symbol info.");
      return(0);
   }
   
   //--- Calculate the raw lot size
   double calculatedLot = riskAmount / lossPerLot;
   
   //--- Normalize the lot size according to broker's rules
   calculatedLot = floor(calculatedLot / volumeStep) * volumeStep;

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
//| Expert tick function - Intentionally left empty                  |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Do nothing after initialization
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //---
   Print("QuickBuyExpert removed. Reason code: ", reason);
}
//+------------------------------------------------------------------+