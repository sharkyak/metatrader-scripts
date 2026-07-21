//+------------------------------------------------------------------+
//|                                              Spread_Current.mq5  |
//|                         Minimal current-spread display (low mem) |
//+------------------------------------------------------------------+
#property copyright "https://t.me/ForexEaPremium"
#property link      "https://t.me/ForexEaPremium"
#property version   "1.00"
#property description "Shows current spread only. Zero buffers, minimal RAM."

#property indicator_chart_window
#property indicator_plots 0

input color            InpColor   = clrRed;              // Text color
input int              InpSize    = 18;                  // Font size
input string           InpFont    = "Arial";             // Font
input ENUM_BASE_CORNER InpCorner  = CORNER_LEFT_UPPER;   // Corner
input int              InpX       = 10;                  // X offset
input int              InpY       = 50;                  // Y offset

#define SPR_OBJ "SprCur"

//+------------------------------------------------------------------+
int OnInit()
{
   IndicatorSetString(INDICATOR_SHORTNAME, "Spread");

   if(!ObjectCreate(0, SPR_OBJ, OBJ_LABEL, 0, 0, 0))
      return INIT_FAILED;

   ENUM_ANCHOR_POINT anchor = ANCHOR_LEFT_UPPER;
   if(InpCorner == CORNER_LEFT_LOWER)       anchor = ANCHOR_LEFT_LOWER;
   else if(InpCorner == CORNER_RIGHT_LOWER) anchor = ANCHOR_RIGHT_LOWER;
   else if(InpCorner == CORNER_RIGHT_UPPER) anchor = ANCHOR_RIGHT_UPPER;

   ObjectSetInteger(0, SPR_OBJ, OBJPROP_CORNER,    InpCorner);
   ObjectSetInteger(0, SPR_OBJ, OBJPROP_ANCHOR,    anchor);
   ObjectSetInteger(0, SPR_OBJ, OBJPROP_XDISTANCE, InpX);
   ObjectSetInteger(0, SPR_OBJ, OBJPROP_YDISTANCE, InpY);
   ObjectSetInteger(0, SPR_OBJ, OBJPROP_COLOR,     InpColor);
   ObjectSetInteger(0, SPR_OBJ, OBJPROP_FONTSIZE,  InpSize);
   ObjectSetString (0, SPR_OBJ, OBJPROP_FONT,      InpFont);
   ObjectSetInteger(0, SPR_OBJ, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, SPR_OBJ, OBJPROP_HIDDEN,    true);
   ObjectSetInteger(0, SPR_OBJ, OBJPROP_BACK,      false);

   // seed once
   ObjectSetString(0, SPR_OBJ, OBJPROP_TEXT,
                   "Spread: " + IntegerToString((int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD)));
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectDelete(0, SPR_OBJ);
}

//+------------------------------------------------------------------+
//| No price[] copy path used — only live bid/ask via SymbolInfo.    |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const int begin,
                const double &price[])
{
   const int spread = (int)MathRound(
      (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point);

   ObjectSetString(0, SPR_OBJ, OBJPROP_TEXT, "Spread: " + IntegerToString(spread));
   return rates_total;
}
//+------------------------------------------------------------------+
