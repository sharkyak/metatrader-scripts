#property copyright "Copyright 2025, Aleksandr Kazakov"
#property version   "1.00"
#property description "Chart trade assistant with draggable SL, TP and entry lines."
#property strict

#include <Trade\Trade.mqh>

//--- Inputs
input double InpRiskSizeUSD     = 20.0;    // Risk size in USD
input double InpInitialDistance = 30.0;    // Initial SL/TP distance in chart price units
input int    InpDeviation       = 50;      // Maximum slippage in points
input ulong  InpMagicNumber           = 752927;  // Expert magic number
input bool   InpForceMinLot           = false;   // Force broker minimum volume if target risk is too small

//--- Chart object names
string g_prefix;
string g_panel;
string g_title;
string g_risk;
string g_volume;
string g_entry_value;
string g_sl_value;
string g_tp_value;
string g_status;
string g_buy_button;
string g_sell_button;
string g_rr2_button;
string g_rr3_button;
string g_buy_limit_button;
string g_sell_limit_button;
string g_entry_line;
string g_sl_line;
string g_tp_line;

//--- Runtime state
CTrade trade;
int    g_digits       = 0;
int    g_volume_digits = 2;
bool   g_ready        = false;
bool   g_entry_line_touched = false;

//+------------------------------------------------------------------+
//| Price and volume helpers                                         |
//+------------------------------------------------------------------+
double NormalizePrice(const double price)
{
   return NormalizeDouble(price, g_digits);
}

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
//| Ensure symbol data is ready                                      |
//+------------------------------------------------------------------+
bool EnsureSymbolReady(const string symbol)
{
   if(!SymbolSelect(symbol, true))
   {
      Print("Cannot select symbol ", symbol, ". Error: ", GetLastError());
      return false;
   }

   MqlTick tick;
   for(int i = 0; i < 50; i++)
   {
      bool haveTick = SymbolInfoTick(symbol, tick) && tick.ask > 0.0 && tick.bid > 0.0;
      double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
      if(haveTick && tickValue > 0.0)
         return true;
      Sleep(100);
   }

   Print("Symbol ", symbol, " is not ready. Tick value: ",
         SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE),
         ". Error: ", GetLastError());
   return false;
}

//+------------------------------------------------------------------+
//| Loss per 1.0 lot if SL is hit, using account currency            |
//+------------------------------------------------------------------+
double CalcLossPerLot(const string symbol, const ENUM_ORDER_TYPE orderType,
                      const double entryPrice, const double stopLossPrice)
{
   // Keep same primary calculation as QuickBuyv2.mq5.
   double profit = 0.0;
   if(OrderCalcProfit(orderType, symbol, 1.0, entryPrice, stopLossPrice, profit))
   {
      double loss = MathAbs(profit);
      if(loss > 0.0)
         return loss;
      Print("OrderCalcProfit returned 0. Trying tick fallback. Entry=",
            entryPrice, " SL=", stopLossPrice);
   }
   else
   {
      Print("OrderCalcProfit failed. Error: ", GetLastError(),
            ". Trying tick fallback.");
   }

   double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tickValue <= 0.0)
      tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);

   if(tickSize <= 0.0 || tickValue <= 0.0)
   {
      Print("Tick fallback failed. Tick size=", tickSize,
            " tick value=", tickValue);
      return 0.0;
   }

   double priceDiff = MathAbs(entryPrice - stopLossPrice);
   double ticks = priceDiff / tickSize;
   return ticks * tickValue;
}

//+------------------------------------------------------------------+
//| Calculate volume using QuickBuyv2 risk rules                     |
//+------------------------------------------------------------------+
double CalculateLotSize(const string symbol, const ENUM_ORDER_TYPE orderType,
                        const double entryPrice, const double stopLossPrice,
                        const double riskAmount, string &errorText)
{
   errorText = "";
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(entryPrice <= 0.0 || stopLossPrice <= 0.0 ||
      MathAbs(entryPrice - stopLossPrice) < point * 0.5)
   {
      errorText = "Invalid entry or SL price";
      return 0.0;
   }

   double lossPerLot = CalcLossPerLot(symbol, orderType, entryPrice, stopLossPrice);
   if(lossPerLot <= 0.0)
   {
      errorText = "Could not calculate loss per lot";
      return 0.0;
   }

   double volumeStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   double volumeMin  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double volumeMax  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   if(volumeStep <= 0.0 || volumeMin <= 0.0 || volumeMax <= 0.0)
   {
      errorText = "Invalid broker volume settings";
      return 0.0;
   }

   int lotDecimals = GetLotDecimals(volumeStep);
   g_volume_digits = lotDecimals;

   double calculatedLot = riskAmount / lossPerLot;

   // Same 5% free-margin reserve used by QuickBuyv2.mq5.
   double marginPerLot = 0.0;
   if(OrderCalcMargin(orderType, symbol, 1.0, entryPrice, marginPerLot) && marginPerLot > 0.0)
   {
      double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      double maxVolumeByMargin = (freeMargin * 0.95) / marginPerLot;
      maxVolumeByMargin = NormalizeDouble(
         MathFloor(maxVolumeByMargin / volumeStep) * volumeStep,
         lotDecimals);
      if(maxVolumeByMargin < volumeMax)
         volumeMax = maxVolumeByMargin;
   }

   calculatedLot = MathFloor(calculatedLot / volumeStep) * volumeStep;
   calculatedLot = NormalizeDouble(calculatedLot, lotDecimals);

   if(calculatedLot < volumeMin)
   {
      double minLotRisk = volumeMin * lossPerLot;
      if(!InpForceMinLot)
      {
         errorText = StringFormat("Risk too small for minimum volume %.2f (risk %.2f USD)",
                                  volumeMin, minLotRisk);
         return 0.0;
      }
      calculatedLot = volumeMin;
   }

   if(volumeMax < volumeMin)
   {
      errorText = "Free margin cannot support minimum volume";
      return 0.0;
   }

   if(calculatedLot > volumeMax)
      calculatedLot = volumeMax;

   return calculatedLot;
}

//+------------------------------------------------------------------+
//| Generic chart object properties                                  |
//+------------------------------------------------------------------+
void SetObjectPosition(const string name, const int x, const int y)
{
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
}

bool CreateLabel(const string name, const string text, const int x, const int y,
                 const color textColor, const int fontSize = 9)
{
   if(!ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0))
      return false;

   SetObjectPosition(name, x, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR, textColor);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 20);
   return true;
}

bool CreateButton(const string name, const string text, const int x, const int y,
                  const int width, const int height)
{
   if(!ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0))
      return false;

   SetObjectPosition(name, x, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, C'50,55,62');
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, C'105,110,118');
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 50);
   return true;
}

bool CreatePanel()
{
   if(!ObjectCreate(0, g_panel, OBJ_RECTANGLE_LABEL, 0, 0, 0))
      return false;

   SetObjectPosition(g_panel, 10, 20);
   ObjectSetInteger(0, g_panel, OBJPROP_XSIZE, 340);
   ObjectSetInteger(0, g_panel, OBJPROP_YSIZE, 315);
   ObjectSetInteger(0, g_panel, OBJPROP_BGCOLOR, C'27,31,36');
   ObjectSetInteger(0, g_panel, OBJPROP_BORDER_COLOR, C'80,86,94');
   ObjectSetInteger(0, g_panel, OBJPROP_BACK, false);
   ObjectSetInteger(0, g_panel, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, g_panel, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, g_panel, OBJPROP_ZORDER, 1);

   if(!CreateLabel(g_title, "TRADE ASSISTANT", 20, 29, clrWhite, 10))
      return false;
   if(!CreateLabel(g_risk, "Risk: 20.00 USD", 20, 56, C'205,210,216'))
      return false;
   if(!CreateLabel(g_volume, "Volume: --", 20, 81, C'255,215,90'))
      return false;
   if(!CreateLabel(g_entry_value, "Entry: --", 20, 106, C'205,210,216'))
      return false;
   if(!CreateLabel(g_sl_value, "SL: --", 20, 131, C'240,105,105'))
      return false;
   if(!CreateLabel(g_tp_value, "TP: --", 20, 156, C'105,220,140'))
      return false;

   if(!CreateButton(g_rr2_button, "2RR", 20, 185, 150, 28))
      return false;
   if(!CreateButton(g_rr3_button, "3RR", 180, 185, 150, 28))
      return false;
   if(!CreateButton(g_buy_button, "BUY", 20, 221, 150, 28))
      return false;
   if(!CreateButton(g_sell_button, "SELL", 180, 221, 150, 28))
      return false;
   if(!CreateButton(g_buy_limit_button, "BUY LIMIT", 20, 257, 150, 28))
      return false;
   if(!CreateButton(g_sell_limit_button, "SELL LIMIT", 180, 257, 150, 28))
      return false;
   if(!CreateLabel(g_status, "Move lines, then choose order", 20, 297, C'165,172,181', 8))
      return false;

   return true;
}

//+------------------------------------------------------------------+
//| Horizontal trade line                                            |
//+------------------------------------------------------------------+
bool CreateTradeLine(const string name, const string label, const double price,
                     const color lineColor)
{
   if(!ObjectCreate(0, name, OBJ_HLINE, 0, 0, NormalizePrice(price)))
      return false;

   ObjectSetInteger(0, name, OBJPROP_COLOR, lineColor);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   // Selected state makes line immediately draggable after EA starts.
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTED, true);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 5);
   ObjectSetString(0, name, OBJPROP_TEXT, label);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, label + " - drag to move");
   return true;
}

void SetLinePrice(const string name, const double price)
{
   ObjectSetDouble(0, name, OBJPROP_PRICE, NormalizePrice(price));
}

double GetLinePrice(const string name)
{
   return ObjectGetDouble(0, name, OBJPROP_PRICE);
}

void UpdateLineLabels()
{
   double entry = GetLinePrice(g_entry_line);
   double sl    = GetLinePrice(g_sl_line);
   double tp    = GetLinePrice(g_tp_line);

   ObjectSetString(0, g_entry_line, OBJPROP_TEXT,
                   "Entry " + DoubleToString(entry, g_digits));
   ObjectSetString(0, g_sl_line, OBJPROP_TEXT,
                   "SL " + DoubleToString(sl, g_digits));
   ObjectSetString(0, g_tp_line, OBJPROP_TEXT,
                   "TP " + DoubleToString(tp, g_digits));
}

//+------------------------------------------------------------------+
//| Create initial lines                                             |
//+------------------------------------------------------------------+
bool CreateInitialLines()
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick) || tick.bid <= 0.0 || tick.ask <= 0.0)
      return false;

   double distance = InpInitialDistance;

   // Initial SL/TP layout follows BUY direction. On GER40, a setting of
   // 30 means a 30.00 price distance from Ask.
   double entry = NormalizePrice(tick.ask);
   double sl = NormalizePrice(entry - distance);
   double tp = NormalizePrice(entry + distance);

   if(!CreateTradeLine(g_entry_line, "Entry", entry, C'255,205,80'))
      return false;
   if(!CreateTradeLine(g_sl_line, "SL", sl, C'240,90,90'))
      return false;
   if(!CreateTradeLine(g_tp_line, "TP", tp, C'80,210,125'))
      return false;

   UpdateLineLabels();
   return true;
}

//+------------------------------------------------------------------+
//| Remove all assistant objects                                    |
//+------------------------------------------------------------------+
void DeleteAssistantObjects()
{
   if(g_prefix == "")
      return;

   ObjectsDeleteAll(0, g_prefix);
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Set panel text                                                   |
//+------------------------------------------------------------------+
void SetStatus(const string text, const color textColor = C'165,172,181')
{
   ObjectSetString(0, g_status, OBJPROP_TEXT, text);
   ObjectSetInteger(0, g_status, OBJPROP_COLOR, textColor);
}

void UpdatePanel()
{
   if(!g_ready)
      return;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick) || tick.bid <= 0.0 || tick.ask <= 0.0)
      return;

   double entryLine = GetLinePrice(g_entry_line);
   double sl = GetLinePrice(g_sl_line);
   double tp = GetLinePrice(g_tp_line);

   ObjectSetString(0, g_risk, OBJPROP_TEXT,
                   "Risk: " + DoubleToString(InpRiskSizeUSD, 2) + " USD");
   ObjectSetString(0, g_entry_value, OBJPROP_TEXT,
                   "Entry: " + DoubleToString(entryLine, g_digits));
   ObjectSetString(0, g_sl_value, OBJPROP_TEXT,
                   "SL: " + DoubleToString(sl, g_digits));
   ObjectSetString(0, g_tp_value, OBJPROP_TEXT,
                   "TP: " + DoubleToString(tp, g_digits));

   // Infer preview order from line geometry. Entry becomes a pending-order
   // preview only after user drags it away from current market.
   ENUM_ORDER_TYPE previewType = ORDER_TYPE_BUY;
   double previewEntry = tick.ask;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   long stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double pendingDistance = MathMax(point, stopsLevel * point);
   bool buyLayout = (sl < entryLine && tp > entryLine);
   bool sellLayout = (sl > entryLine && tp < entryLine);

   if(g_entry_line_touched && buyLayout && entryLine < tick.ask - pendingDistance)
   {
      previewType = ORDER_TYPE_BUY_LIMIT;
      previewEntry = entryLine;
   }
   else if(g_entry_line_touched && sellLayout && entryLine > tick.bid + pendingDistance)
   {
      previewType = ORDER_TYPE_SELL_LIMIT;
      previewEntry = entryLine;
   }
   else if(sellLayout)
   {
      previewType = ORDER_TYPE_SELL;
      previewEntry = tick.bid;
   }

   double previewSL = sl;
   string errorText;
   double volume = CalculateLotSize(_Symbol, previewType, previewEntry,
                                   previewSL, InpRiskSizeUSD, errorText);

   if(volume > 0.0)
   {
      ObjectSetString(0, g_volume, OBJPROP_TEXT,
                      "Volume: " + DoubleToString(volume, g_volume_digits));
      ObjectSetInteger(0, g_volume, OBJPROP_COLOR, C'255,215,90');
   }
   else
   {
      ObjectSetString(0, g_volume, OBJPROP_TEXT, "Volume: --");
      ObjectSetInteger(0, g_volume, OBJPROP_COLOR, C'240,125,100');
   }

   UpdateLineLabels();
}

void SetRiskReward(const double rewardMultiple)
{
   double sl = GetLinePrice(g_sl_line);
   double tp = GetLinePrice(g_tp_line);

   if(sl <= 0.0 || tp <= 0.0 || MathAbs(sl - tp) < SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 0.5)
   {
      SetStatus("SL and TP must be different", C'240,125,100');
      return;
   }

   // Keep SL and TP fixed. Move Entry between them so reward:risk equals
   // the selected multiple for either buy or sell line orientation.
   double entry = (rewardMultiple * sl + tp) / (rewardMultiple + 1.0);
   SetLinePrice(g_entry_line, entry);
   g_entry_line_touched = true;
   UpdatePanel();
   SetStatus("RR 1:" + DoubleToString(rewardMultiple, 0) + " applied");
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Validate order geometry                                          |
//+------------------------------------------------------------------+
bool ValidateTrade(const ENUM_ORDER_TYPE type, double &entry, double &sl, double &tp,
                   string &errorText)
{
   errorText = "";
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick) || tick.bid <= 0.0 || tick.ask <= 0.0)
   {
      errorText = "No valid market quote";
      return false;
   }

   entry = GetLinePrice(g_entry_line);
   sl = GetLinePrice(g_sl_line);
   tp = GetLinePrice(g_tp_line);

   bool isBuy = (type == ORDER_TYPE_BUY || type == ORDER_TYPE_BUY_LIMIT);
   bool isLimit = (type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_SELL_LIMIT);

   if(isLimit)
   {
      if(isBuy && entry >= tick.ask)
      {
         errorText = "Buy Limit entry must be below Ask";
         return false;
      }
      if(!isBuy && entry <= tick.bid)
      {
         errorText = "Sell Limit entry must be above Bid";
         return false;
      }
   }
   else
   {
      entry = isBuy ? tick.ask : tick.bid;
   }

   if(isBuy)
   {
      if(sl >= entry)
      {
         errorText = "Buy SL must be below entry";
         return false;
      }
      if(tp <= entry)
      {
         errorText = "Buy TP must be above entry";
         return false;
      }
   }
   else
   {
      if(sl <= entry)
      {
         errorText = "Sell SL must be above entry";
         return false;
      }
      if(tp >= entry)
      {
         errorText = "Sell TP must be below entry";
         return false;
      }
   }

   entry = NormalizePrice(entry);
   sl = NormalizePrice(sl);
   tp = NormalizePrice(tp);

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   long stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDistance = stopsLevel * point;

   if(minDistance > 0.0)
   {
      if(isLimit)
      {
         double marketDistance = isBuy ? tick.ask - entry : entry - tick.bid;
         if(marketDistance < minDistance)
         {
            errorText = "Limit entry is too close to market";
            return false;
         }
      }

      if(MathAbs(entry - sl) < minDistance)
      {
         errorText = "SL is inside broker minimum distance";
         return false;
      }
      if(MathAbs(tp - entry) < minDistance)
      {
         errorText = "TP is inside broker minimum distance";
         return false;
      }
   }

   return true;
}

//+------------------------------------------------------------------+
//| Accepted trade-server result                                     |
//+------------------------------------------------------------------+
bool IsTradeAccepted(const uint retcode)
{
   return retcode == TRADE_RETCODE_DONE ||
          retcode == TRADE_RETCODE_PLACED ||
          retcode == TRADE_RETCODE_DONE_PARTIAL;
}

//+------------------------------------------------------------------+
//| Place selected order                                             |
//+------------------------------------------------------------------+
void PlaceOrder(const ENUM_ORDER_TYPE type)
{
   if(InpRiskSizeUSD <= 0.0)
   {
      SetStatus("Risk must be above zero", C'240,125,100');
      Alert("Trade Assistant: Risk must be above zero.");
      return;
   }

   double entry, sl, tp;
   string errorText;
   if(!ValidateTrade(type, entry, sl, tp, errorText))
   {
      SetStatus(errorText, C'240,125,100');
      Alert("Trade Assistant: ", errorText);
      return;
   }

   double volume = CalculateLotSize(_Symbol, type, entry, sl,
                                   InpRiskSizeUSD, errorText);
   if(volume <= 0.0)
   {
      SetStatus(errorText, C'240,125,100');
      Alert("Trade Assistant: ", errorText);
      return;
   }

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviation);

   string comment = "Trade Assistant";
   bool placed = false;

   if(type == ORDER_TYPE_BUY)
      placed = trade.Buy(volume, _Symbol, 0.0, sl, tp, comment);
   else if(type == ORDER_TYPE_SELL)
      placed = trade.Sell(volume, _Symbol, 0.0, sl, tp, comment);
   else if(type == ORDER_TYPE_BUY_LIMIT)
      placed = trade.BuyLimit(volume, entry, _Symbol, sl, tp,
                              ORDER_TIME_GTC, 0, comment);
   else if(type == ORDER_TYPE_SELL_LIMIT)
      placed = trade.SellLimit(volume, entry, _Symbol, sl, tp,
                               ORDER_TIME_GTC, 0, comment);

   uint retcode = trade.ResultRetcode();
   placed = placed && IsTradeAccepted(retcode);

   if(placed)
   {
      Print("Order placed. Symbol=", _Symbol, " type=", type,
            " volume=", volume, " entry=", entry, " sl=", sl, " tp=", tp,
            " retcode=", retcode);
      Alert("Trade Assistant: order placed. Volume ",
            DoubleToString(volume, g_volume_digits));
      ExpertRemove();
   }
   else
   {
      string result = trade.ResultComment();
      SetStatus("Order failed: " + result, C'240,125,100');
      Alert("Trade Assistant: order failed. Retcode ",
            IntegerToString((int)retcode), " - ", result);
   }
}

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   g_prefix = "TA_" + IntegerToString((long)ChartID()) + "_" +
              IntegerToString((long)InpMagicNumber) + "_";

   g_panel            = g_prefix + "Panel";
   g_title            = g_prefix + "Title";
   g_risk             = g_prefix + "Risk";
   g_volume           = g_prefix + "Volume";
   g_entry_value      = g_prefix + "EntryValue";
   g_sl_value         = g_prefix + "SLValue";
   g_tp_value         = g_prefix + "TPValue";
   g_status           = g_prefix + "Status";
   g_buy_button       = g_prefix + "Buy";
   g_sell_button      = g_prefix + "Sell";
   g_rr2_button       = g_prefix + "RR2";
   g_rr3_button       = g_prefix + "RR3";
   g_buy_limit_button = g_prefix + "BuyLimit";
   g_sell_limit_button = g_prefix + "SellLimit";
   g_entry_line       = g_prefix + "EntryLine";
   g_sl_line          = g_prefix + "SLLine";
   g_tp_line          = g_prefix + "TPLine";

   g_digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   if(InpInitialDistance <= 0.0)
   {
      Print("InpInitialDistance must be above zero.");
      return INIT_PARAMETERS_INCORRECT;
   }

   if(!EnsureSymbolReady(_Symbol))
      return INIT_FAILED;

   if(!CreatePanel() || !CreateInitialLines())
   {
      DeleteAssistantObjects();
      return INIT_FAILED;
   }

   g_ready = true;
   UpdatePanel();
   ChartRedraw();
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Tick updates                                                     |
//+------------------------------------------------------------------+
void OnTick()
{
   UpdatePanel();
}

//+------------------------------------------------------------------+
//| Chart events                                                     |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam,
                  const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(sparam == g_rr2_button)
         SetRiskReward(2.0);
      else if(sparam == g_rr3_button)
         SetRiskReward(3.0);
      else if(sparam == g_buy_button)
         PlaceOrder(ORDER_TYPE_BUY);
      else if(sparam == g_sell_button)
         PlaceOrder(ORDER_TYPE_SELL);
      else if(sparam == g_buy_limit_button)
         PlaceOrder(ORDER_TYPE_BUY_LIMIT);
      else if(sparam == g_sell_limit_button)
         PlaceOrder(ORDER_TYPE_SELL_LIMIT);

      if(ObjectFind(0, sparam) >= 0)
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      return;
   }

   if(id == CHARTEVENT_OBJECT_DRAG || id == CHARTEVENT_OBJECT_CHANGE)
   {
      if(sparam == g_entry_line || sparam == g_sl_line || sparam == g_tp_line)
      {
         if(sparam == g_entry_line)
            g_entry_line_touched = true;
         UpdatePanel();
         ChartRedraw();
      }
   }
}

//+------------------------------------------------------------------+
//| Cleanup                                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   DeleteAssistantObjects();
}
