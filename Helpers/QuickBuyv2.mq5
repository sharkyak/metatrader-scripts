#property copyright "Copyright 2025, Aleksandr Kazakov"
#property version   "1.01"
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
//| Ensure symbol selected and rates available                       |
//+------------------------------------------------------------------+
bool EnsureSymbolReady(const string symbol)
{
   if(!SymbolSelect(symbol, true))
   {
      Alert("Error: Cannot select symbol ", symbol, " in Market Watch. Error: ", GetLastError());
      return false;
   }

   // Force fresh quote
   MqlTick tick;
   for(int i = 0; i < 5; i++)
   {
      if(SymbolInfoTick(symbol, tick) && tick.ask > 0.0 && tick.bid > 0.0)
         return true;
      Sleep(50);
   }

   Alert("Error: No valid tick data for ", symbol, ". Error: ", GetLastError());
   return false;
}

//+------------------------------------------------------------------+
//| Lot decimals from volume step                                    |
//+------------------------------------------------------------------+
int GetLotDecimals(const double volumeStep)
{
   if(volumeStep <= 0.0)
      return 2;

   int decimals = 0;
   double step = volumeStep;
   while(decimals < 8 && MathAbs(step - MathRound(step)) > 1e-12)
   {
      step *= 10.0;
      decimals++;
   }
   return decimals;
}

//+------------------------------------------------------------------+
//| Loss per 1.0 lot if SL hit (account currency)                    |
//+------------------------------------------------------------------+
double CalcLossPerLot(const string symbol, const ENUM_ORDER_TYPE orderType,
                      const double entryPrice, const double stopLossPrice)
{
   // Prefer OrderCalcProfit (handles currency conversion correctly)
   double profit = 0.0;
   if(OrderCalcProfit(orderType, symbol, 1.0, entryPrice, stopLossPrice, profit))
   {
      double loss = MathAbs(profit);
      if(loss > 0.0)
         return loss;
      Print("OrderCalcProfit returned 0 profit. entry=", entryPrice,
            " sl=", stopLossPrice, " — trying tick fallback.");
   }
   else
   {
      Print("OrderCalcProfit failed. Error: ", GetLastError(),
            " — trying tick fallback.");
   }

   // Fallback: distance in ticks * tick value (loss side)
   double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tickValue <= 0.0)
      tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);

   if(tickSize <= 0.0 || tickValue <= 0.0)
   {
      Print("Tick fallback failed. tickSize=", tickSize, " tickValue=", tickValue,
            " tickValueLoss=", SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE_LOSS),
            " tickValueBase=", SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE));
      return 0.0;
   }

   double priceDiff = MathAbs(entryPrice - stopLossPrice);
   double ticks = priceDiff / tickSize;
   double lossPerLot = ticks * tickValue;

   Print("Tick fallback loss/lot: ", lossPerLot,
         " (diff=", priceDiff, " ticks=", ticks, " tickValue=", tickValue, ")");

   return lossPerLot;
}

//+------------------------------------------------------------------+
//| Function to calculate the appropriate lot size                   |
//+------------------------------------------------------------------+
double CalculateLotSize(string symbol, ENUM_ORDER_TYPE orderType, double entryPrice, double stopLossPrice, double riskAmount)
{
   if(entryPrice <= 0.0 || stopLossPrice <= 0.0 || MathAbs(entryPrice - stopLossPrice) < _Point * 0.5)
   {
      Alert("Error: Invalid entry/SL for lot calc. entry=", entryPrice, " sl=", stopLossPrice);
      return 0.0;
   }

   double lossPerLot = CalcLossPerLot(symbol, orderType, entryPrice, stopLossPrice);
   if(lossPerLot <= 0.0)
   {
      Alert("Error: Could not calculate loss per lot. Check prices and symbol info. entry=",
            entryPrice, " sl=", stopLossPrice);
      return 0.0;
   }

   //--- Calculate the raw lot size
   double calculatedLot = riskAmount / lossPerLot;

   //--- Normalize the lot size according to broker's rules
   double volumeStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   double volumeMin  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double volumeMax  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);

   if(volumeStep <= 0.0)
   {
      Alert("Error: Invalid SYMBOL_VOLUME_STEP for ", symbol);
      return 0.0;
   }

   int lotDecimals = GetLotDecimals(volumeStep);

   //--- Calculate max volume based on free margin (with 5% reserve for slippage)
   double marginPerLot = 0.0;
   if(OrderCalcMargin(orderType, symbol, 1.0, entryPrice, marginPerLot) && marginPerLot > 0.0)
   {
      double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      double maxVolumeByMargin = (freeMargin * 0.95) / marginPerLot;
      maxVolumeByMargin = NormalizeDouble(MathFloor(maxVolumeByMargin / volumeStep) * volumeStep, lotDecimals);
      if(maxVolumeByMargin < volumeMax)
         volumeMax = maxVolumeByMargin;
      Print("Free margin: ", freeMargin, ", Margin per lot: ", marginPerLot,
            ", Max volume by margin (95%): ", maxVolumeByMargin);
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
      Alert("Warning: Calculated lot size (", calculatedLot,
            ") is smaller than the minimum allowed (", volumeMin,
            "). The minimum lot size will be used instead.");
      calculatedLot = volumeMin;
   }

   if(calculatedLot > volumeMax)
   {
      Alert("Warning: Calculated lot size (", calculatedLot,
            ") exceeds max allowed by margin/broker (", volumeMax,
            "). Clamping to maximum.");
      calculatedLot = volumeMax;
   }

   Print("Loss per lot: ", lossPerLot, ", Risk: ", riskAmount, ", Lot: ", calculatedLot);
   return calculatedLot;
}

//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void OnStart()
{
   string currentSymbol = _Symbol;

   if(!EnsureSymbolReady(currentSymbol))
      return;

   double askPrice = SymbolInfoDouble(currentSymbol, SYMBOL_ASK);
   if(askPrice <= 0.0)
   {
      Alert("Error: Failed to get Ask price for ", currentSymbol);
      return;
   }
   int digits = (int)SymbolInfoInteger(currentSymbol, SYMBOL_DIGITS);

   //--- 1. VALIDATE INPUTS ---
   if(InpStopLossPrice <= 0.0)
   {
      Alert("Error: Please specify a valid Stop Loss Price > 0.");
      return;
   }

   if(InpStopLossPrice >= askPrice)
   {
      Alert("Error: For a BUY order, the Stop Loss Price must be below the current Ask Price (",
            askPrice, ").");
      return;
   }

   // Normalize SL to prevent server rejection on some brokers
   double normSL = NormalizeDouble(InpStopLossPrice, digits);
   if(normSL >= askPrice)
   {
      Alert("Error: Normalized SL (", normSL, ") is not below Ask (", askPrice, ").");
      return;
   }

   //--- 2. CALCULATE LOT SIZE ---
   double lotSize = CalculateLotSize(currentSymbol, ORDER_TYPE_BUY, askPrice, normSL, InpRiskSizeUSD);

   if(lotSize <= 0.0)
      return;

   //--- 3. CALCULATE TAKE PROFIT ---
   double tp = 0.0;
   if(InpSetTP)
   {
      tp = NormalizeDouble(askPrice + (askPrice - normSL) * InpRR, digits);
      Print("Take Profit: ", tp, " (RR: ", InpRR, ")");
   }

   Print("Calculated Lot Size: ", lotSize, " for Symbol: ", currentSymbol,
         " entry=", askPrice, " sl=", normSL);

   //--- 4. OPEN BUY POSITION ---
   if(trade.Buy(lotSize, currentSymbol, askPrice, normSL, tp, "QuickBuyv2 Script Order"))
   {
      Print("BUY order successfully placed for ", currentSymbol, " with lot size ", lotSize);
      Alert("Success! BUY order placed for ", lotSize, " lots on ", currentSymbol);
   }
   else
   {
      Print("Failed to place BUY order. Result code: ", trade.ResultRetcode(),
            ", Message: ", trade.ResultComment());
      Alert("Error: Could not place BUY order. Check the Journal tab for details.");
   }
}
