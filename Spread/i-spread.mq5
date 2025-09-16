//+------------------------------------------------------------------+
//|                                                     i-Spread.mq5 |
//|                         Copyright © 2013, ��� ����� �. aka KimIV |
//|                                              http://www.kimiv.ru |
//|                                      (Code revised by Gemini AI) |
//+------------------------------------------------------------------+
#property copyright "Copyright © 2013, KimIV (Revised by Gemini AI)"
#property link      "http://www.kimiv.ru"
#property version   "1.50"
#property description "This indicator displays the current, maximum, and minimum spread in a separate window."
#property indicator_separate_window
#property indicator_buffers 3
#property indicator_plots   3

//--- Plot: Maximum Spread
#property indicator_label1  "Max"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrRed
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

//--- Plot: Current Spread
#property indicator_label2  "Current"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrGold
#property indicator_style2  STYLE_SOLID
#property indicator_width2  2

//--- Plot: Minimum Spread
#property indicator_label3  "Min"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrBlue
#property indicator_style3  STYLE_SOLID
#property indicator_width3  2

//--- Input Parameters ---
input bool   WriteInFile = false; // Write spread data to a file
input string FileName    = "";    // File name for spread data
input int    Shift       = 0;     // Shift indicator plots (in bars)

//--- Indicator Buffers ---
double ExtMaxBuffer[];
double ExtCurrentBuffer[];
double ExtMinBuffer[];

//--- Global Variables ---
string   g_file_name;
datetime g_prev_h1, g_prev_h4, g_prev_d1;
double   g_max_h1, g_max_h4, g_max_d1;
double   g_min_h1, g_min_h4, g_min_d1;
double   g_prev_spread;
double   g_point_to_pip_factor; // Factor to convert points to pips

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
void OnInit()
{
   //--- Set up buffer bindings ---
   SetIndexBuffer(0, ExtMaxBuffer,     INDICATOR_DATA);
   SetIndexBuffer(1, ExtCurrentBuffer, INDICATOR_DATA);
   SetIndexBuffer(2, ExtMinBuffer,     INDICATOR_DATA);

   //--- Set plot properties ---
   for(int i = 0; i < 3; i++)
   {
      PlotIndexSetInteger(i, PLOT_SHIFT,        Shift);
      PlotIndexSetInteger(i, PLOT_DRAW_BEGIN,   1);
      PlotIndexSetDouble(i,  PLOT_EMPTY_VALUE,  EMPTY_VALUE);
   }

   //--- Set indicator name and precision ---
   IndicatorSetString(INDICATOR_SHORTNAME, "i-Spread");
   IndicatorSetInteger(INDICATOR_DIGITS, 1); // Display with 1 decimal place

   //--- Initialize file name ---
   g_file_name = FileName;
   if(StringLen(g_file_name) == 0)
   {
      string symbolName = Symbol();
      StringToLower(symbolName);
      g_file_name = "spread_" + symbolName + "_" + EnumToString(Period()) + ".csv";
   }
   
   //--- **FIXED**: Determine the factor for converting points to pips ---
   g_point_to_pip_factor = 1.0;
   if(_Digits == 3 || _Digits == 5)
   {
      g_point_to_pip_factor = 10.0;
   }

   //--- Initialize min/max tracking values ---
   g_min_h1 = 99999;
   g_min_h4 = 99999;
   g_min_d1 = 99999;
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                     |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Comment(""); // Clean up the comment on the chart
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   /*
    NOTE: MQL5 does not store historical spread data. The spread for historical bars is usually zero.
    This indicator will begin tracking the spread history from the moment it is attached to the chart.
   */

   int start;
   if(prev_calculated == 0) // First run
   {
      start = 1; 
      // Initialize buffers to empty
      ArrayInitialize(ExtMaxBuffer, EMPTY_VALUE);
      ArrayInitialize(ExtCurrentBuffer, EMPTY_VALUE);
      ArrayInitialize(ExtMinBuffer, EMPTY_VALUE);
   }
   else
   {
      start = prev_calculated - 1; // Subsequent runs
   }
   
   //--- Main calculation loop ---
   for(int i = start; i < rates_total; i++)
   {
      //--- **FIXED**: Correctly calculate spread in pips ---
      double current_spread = (double)spread[i] / g_point_to_pip_factor;

      //--- Set current spread value ---
      ExtCurrentBuffer[i] = current_spread;

      //--- Handle max and min spread calculation ---
      if (i > 0)
      {
         // Carry over previous values by default
         ExtMaxBuffer[i] = ExtMaxBuffer[i-1];
         ExtMinBuffer[i] = ExtMinBuffer[i-1];

         // If previous min was empty, initialize it
         if (ExtMinBuffer[i-1] == EMPTY_VALUE || ExtMinBuffer[i-1] == 0)
         {
            ExtMinBuffer[i] = current_spread;
         }

         // Update max value if current spread is higher
         if (current_spread > ExtMaxBuffer[i])
         {
            ExtMaxBuffer[i] = current_spread;
         }
         // Update min value if current spread is lower (and not zero)
         if (current_spread < ExtMinBuffer[i] && current_spread > 0)
         {
            ExtMinBuffer[i] = current_spread;
         }
      }
      else // For the very first bar
      {
         ExtMaxBuffer[i] = current_spread;
         ExtMinBuffer[i] = current_spread;
      }
   }
   
   //--- Update comment with spread info for the current bar ---
   UpdateComment(rates_total);
   
   //--- Write to file if enabled ---
   if(WriteInFile)
   {
      double last_spread = (double)spread[rates_total - 1] / g_point_to_pip_factor;
      if(g_prev_spread != last_spread)
      {
         string text_to_write = TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + ";" + DoubleToString(last_spread, 1);
         WriteLineToFile(g_file_name, text_to_write);
      }
      g_prev_spread = last_spread;
   }
   
   return(rates_total);
}

//+------------------------------------------------------------------+
//| Updates the on-chart comment with spread details.                |
//+------------------------------------------------------------------+
void UpdateComment(int rates_total)
{
   //--- **FIXED**: Correctly calculate current spread in pips ---
   double current_spread = (double)SymbolInfoInteger(Symbol(), SYMBOL_SPREAD) / g_point_to_pip_factor;
   
   //--- Get times for H1, H4, D1 timeframes ---
   datetime time_h1[], time_h4[], time_d1[];
   if(CopyTime(Symbol(), PERIOD_H1, 0, 1, time_h1) <= 0) return;
   if(CopyTime(Symbol(), PERIOD_H4, 0, 1, time_h4) <= 0) return;
   if(CopyTime(Symbol(), PERIOD_D1, 0, 1, time_d1) <= 0) return;

   //--- Update H1 min/max ---
   if(g_prev_h1 < time_h1[0])
   {
      g_max_h1 = current_spread;
      g_min_h1 = current_spread;
   }
   g_prev_h1 = time_h1[0];
   if(g_max_h1 < current_spread) g_max_h1 = current_spread;
   if(g_min_h1 > current_spread && current_spread > 0) g_min_h1 = current_spread;

   //--- Update H4 min/max ---
   if(g_prev_h4 < time_h4[0])
   {
      g_max_h4 = current_spread;
      g_min_h4 = current_spread;
   }
   g_prev_h4 = time_h4[0];
   if(g_max_h4 < current_spread) g_max_h4 = current_spread;
   if(g_min_h4 > current_spread && current_spread > 0) g_min_h4 = current_spread;

   //--- Update D1 min/max ---
   if(g_prev_d1 < time_d1[0])
   {
      g_max_d1 = current_spread;
      g_min_d1 = current_spread;
   }
   g_prev_d1 = time_d1[0];
   if(g_max_d1 < current_spread) g_max_d1 = current_spread;
   if(g_min_d1 > current_spread && current_spread > 0) g_min_d1 = current_spread;
   
   //--- **FIXED**: Build and display the comment string with correct formatting (1 decimal place) ---
   string comment_string = StringFormat(
      "Max H1: %.1f  |  Max H4: %.1f  |  Max D1: %.1f\n" +
      "--- Current Spread: %.1f ---\n" +
      "Min H1: %.1f  |  Min H4: %.1f  |  Min D1: %.1f",
      g_max_h1, g_max_h4, g_max_d1,
      current_spread,
      g_min_h1, g_min_h4, g_min_d1
   );
   Comment(comment_string);
}

//+------------------------------------------------------------------+
//| Writes a line of text to the end of a specified file.            |
//+------------------------------------------------------------------+
void WriteLineToFile(string file_name, string text)
{
   //--- Open the file in read/write mode using the correct flags
   int file_handle = FileOpen(file_name, FILE_READ | FILE_WRITE | FILE_ANSI);

   if(file_handle != INVALID_HANDLE)
   {
      //--- Go to the end of the file to append data
      FileSeek(file_handle, 0, SEEK_END);
      
      //--- Write the pre-formatted string and add a new line
      FileWriteString(file_handle, text + "\r\n");
      
      //--- Close the file handle
      FileClose(file_handle);
   }
}
//+------------------------------------------------------------------+