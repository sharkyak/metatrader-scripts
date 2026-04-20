#property copyright "Copyright 2025, Aleksandr Kazakov"
#property version   "1.00"
#property description "Calculates lot size based on SL price and risk in USD, then opens a single BUY position with optional TP."
#property script_show_inputs

#include <Trade\Trade.mqh>

//--- Script Input Parameters
input double InpStopLossPrice = 0;      // Stop Loss Price Level
input double InpRiskSizeUSD   = 20.0;   // Risk Size in USD
input bool   InpSetTP         = true;   // Set Take Profit?
input double InpRR            = 1.0;    // Risk:Reward Ratio

//--- Global CTrade instance
CTrade trade;

//+------------------------------------------------------------------+
//| Function to calculate the appropriate lot size                   |
//+------------------------------------------------------------------+
double CalculateLotSize(string symbol, ENUM_ORDER_TYPE orderType, double entryPrice, double stopLossPrice, double riskAmount)
{
   //--- Use OrderCalcProfit to get the loss per 1 lot if SL is hit
   double profit = 0;
   if(!OrderCalcProfit(orderType, symbol, 1.0, entryPrice, stopLossPrice, profit))
   {
      Alert("Error: OrderCalcProfit failed for ", symbol, ". Error: ", GetLastError());
      return(0);
   }

   double lossPerLot = MathAbs(profit);
   if(lossPerLot <= 0)
   {
      Alert("Error: Could not calculate loss per lot. Check prices and symbol info.");
      return(0);
   }

   //--- Calculate the raw lot size
   double calculatedLot = riskAmount / lossPerLot;

   //--- Normalize the lot size according to broker's rules
   double volumeStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   double volumeMin = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double volumeMax = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);

   int lotDecimals = 0;
   if(volumeStep == 0.01) lotDecimals = 2;
   else if(volumeStep == 0.1) lotDecimals = 1;
   else if(volumeStep == 1.0) lotDecimals = 0;
   else lotDecimals = 8;

   //--- Calculate max volume based on free margin (with 5% reserve for slippage)
   double marginPerLot = 0;
   if(OrderCalcMargin(orderType, symbol, 1.0, entryPrice, marginPerLot) && marginPerLot > 0)
   {
      double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      double maxVolumeByMargin = (freeMargin * 0.95) / marginPerLot;
      maxVolumeByMargin = NormalizeDouble(MathFloor(maxVolumeByMargin / volumeStep) * volumeStep, lotDecimals);
      if(maxVolumeByMargin < volumeMax)
         volumeMax = maxVolumeByMargin;
      Print("Free margin: ", freeMargin, ", Margin per lot: ", marginPerLot, ", Max volume by margin (95%): ", maxVolumeByMargin);
   }
   else
   {
      Alert("Warning: Could not calculate margin per lot. Using broker max volume only.");
   }

   calculatedLot = MathFloor(calculatedLot / volumeStep) * volumeStep;
   calculatedLot = NormalizeDouble(calculatedLot, lotDecimals);

   //--- Check against min and max lot size
   if(calculatedLot < volumeMin)
   {
      Alert("Warning: Calculated lot size (", calculatedLot, ") is smaller than the minimum allowed (", volumeMin, "). The minimum lot size will be used instead.");
      calculatedLot = volumeMin;
   }

   if(calculatedLot > volumeMax)
   {
      Alert("Warning: Calculated lot size (", calculatedLot, ") exceeds max allowed by margin/broker (", volumeMax, "). Clamping to maximum.");
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

   // Refresh symbol data to ensure latest prices
   double askPrice = 0;
   if(!SymbolInfoDouble(currentSymbol, SYMBOL_ASK, askPrice))
   {
      Alert("Error: Failed to get Ask price for ", currentSymbol);
      return;
   }
   int digits = (int)SymbolInfoInteger(currentSymbol, SYMBOL_DIGITS);

   //--- 1. VALIDATE INPUTS ---
   // Essential check: Stop Loss for a BUY must be below the entry price
   if(InpStopLossPrice <= 0)
   {
      Alert("Error: Please specify a valid Stop Loss Price > 0.");
      return;
   }

   if(InpStopLossPrice >= askPrice)
   {
      Alert("Error: For a BUY order, the Stop Loss Price must be below the current Ask Price (", askPrice, ").");
      return;
   }

   // Normalize SL to prevent server rejection on some brokers
   double normSL = NormalizeDouble(InpStopLossPrice, digits);

   //--- 2. CALCULATE LOT SIZE ---
   double lotSize = CalculateLotSize(currentSymbol, ORDER_TYPE_BUY, askPrice, normSL, InpRiskSizeUSD);

   if(lotSize <= 0)
   {
      // An alert is fired from the calculation function. Stop execution.
      return;
   }

   //--- 3. CALCULATE TAKE PROFIT ---
   double tp = 0;
   if(InpSetTP)
   {
      tp = NormalizeDouble(askPrice + (askPrice - normSL) * InpRR, digits);
      Print("Take Profit: ", tp, " (RR: ", InpRR, ")");
   }

   Print("Calculated Lot Size: ", lotSize, " for Symbol: ", currentSymbol);

   //--- 4. OPEN BUY POSITION ---
   if(trade.Buy(lotSize, currentSymbol, askPrice, normSL, tp, "QuickBuyv2 Script Order"))
   {
      Print("BUY order successfully placed for ", currentSymbol, " with lot size ", lotSize);
      Alert("Success! BUY order placed for ", lotSize, " lots on ", currentSymbol);
   }
   else
   {
      Print("Failed to place BUY order. Result code: ", trade.ResultRetcode(), ", Message: ", trade.ResultComment());
      Alert("Error: Could not place BUY order. Check the Journal tab for details.");
   }
}