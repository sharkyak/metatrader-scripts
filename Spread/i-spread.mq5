//+------------------------------------------------------------------+ 
//|                                                     i-Spread.mq5 | 
//|                         Copyright � 2013, ��� ����� �. aka KimIV | 
//|                                              http://www.kimiv.ru | 
//+------------------------------------------------------------------+ 
#property copyright "Copyright � 2013, ��� ����� �. aka KimIV"
#property link "http://www.kimiv.ru"
//--- ����� ������ ����������
#property version   "1.00"
//--- ��������� ���������� � ��������� ����
#property indicator_separate_window  
//--- ���������� ������������ �������
#property indicator_buffers 3 
//--- ������������ ��� ����������� ����������
#property indicator_plots   3
//+-----------------------------------+
//|  ��������� ��������� ����������   |
//+-----------------------------------+
//--- ��������� ���������� � ���� �����
#property indicator_type1   DRAW_LINE
//--- � �������� ����� ����� ���������� ����������� Red ����
#property indicator_color1 clrRed
//--- ����� ���������� - ����������� ������
#property indicator_style1  STYLE_SOLID
//--- ������� ����� ���������� ����� 2
#property indicator_width1  2
//--- ����������� ����� ����������
#property indicator_label1  "Max"
//--- ��������� ���������� � ���� �����
#property indicator_type2   DRAW_LINE
//--- � �������� ����� ����� ���������� ����������� Gold ����
#property indicator_color2 clrGold
//--- ����� ���������� - ����������� ������
#property indicator_style2  STYLE_SOLID
//--- ������� ����� ���������� ����� 2
#property indicator_width2  2
//--- ����������� ����� ����������
#property indicator_label2  "Current"
//--- ��������� ���������� � ���� �����
#property indicator_type3   DRAW_LINE
//--- � �������� ����� ����� ���������� ����������� Blue ����
#property indicator_color3 clrBlue
//--- ����� ���������� - ����������� ������
#property indicator_style3  STYLE_SOLID
//--- ������� ����� ���������� ����� 2
#property indicator_width3  2
//--- ����������� ����� ����������
#property indicator_label3  "Min"
//+----------------------------------------------+
//| ������� ��������� ����������                 |
//+----------------------------------------------+
input bool   WriteInFile = false;   // ���������� � ����
input string FileName    = "";      // ��� �����
input int Shift=0;                  // ����� ���������� �� ����������� � �����
//+----------------------------------------------+
//--- ������������ ������
double buf0[],buf1[],buf2[];
//--- ���������� ���������� ������ ������� ������
string FileName_;
int min_rates_total;
datetime prevH1,prevH4,prevD1;
double maxH1,maxH4,maxD1,prevSpread,minH1,minH4,minD1;
//+------------------------------------------------------------------+    
//| Custom indicator initialization function                         | 
//+------------------------------------------------------------------+  
void OnInit()
  {
//--- ������������� ��������
   min_rates_total=3;
   FileName_=FileName;
   if(StringLen(FileName_)==0) FileName_="spr_"+StringLower(Symbol())+"_"+GetStringTimeframe(Period())+".csv";
//--- ����������� ������������� ������� � ������������ �����
   SetIndexBuffer(0,buf0,INDICATOR_DATA);
//--- ������������� ������ ���������� 1 �� ����������� �� AroonShift
   PlotIndexSetInteger(0,PLOT_SHIFT,Shift);
//--- ������������� ������ ������ ������� ��������� ���������� 1
   PlotIndexSetInteger(0,PLOT_DRAW_BEGIN,min_rates_total);
//--- ��������� �������� ����������, ������� �� ����� ������ �� �������
   PlotIndexSetDouble(0,PLOT_EMPTY_VALUE,EMPTY_VALUE);
//--- ����������� ������������� ������� � ������������ �����
   SetIndexBuffer(1,buf1,INDICATOR_DATA);
//--- ������������� ������ ���������� 2 �� �����������
   PlotIndexSetInteger(1,PLOT_SHIFT,Shift);
//--- ������������� ������ ������ ������� ��������� ���������� 2
   PlotIndexSetInteger(1,PLOT_DRAW_BEGIN,min_rates_total);
//--- ��������� �������� ����������, ������� �� ����� ������ �� �������
   PlotIndexSetDouble(1,PLOT_EMPTY_VALUE,EMPTY_VALUE);
//--- ����������� ������������� ������� � ������������ �����
   SetIndexBuffer(2,buf2,INDICATOR_DATA);
//--- ������������� ������ ���������� 3 �� �����������
   PlotIndexSetInteger(2,PLOT_SHIFT,Shift);
//--- ������������� ������ ������ ������� ��������� ���������� 3
   PlotIndexSetInteger(2,PLOT_DRAW_BEGIN,min_rates_total);
//--- ��������� �������� ����������, ������� �� ����� ������ �� �������
   PlotIndexSetDouble(2,PLOT_EMPTY_VALUE,EMPTY_VALUE);
//--- �������� ����� ��� ����������� � ��������� ������� � �� ����������� ���������
   IndicatorSetString(INDICATOR_SHORTNAME,"i-Spread");
//--- ����������� �������� ����������� �������� ����������
   IndicatorSetInteger(INDICATOR_DIGITS,0);
//--- ���������� �������������
  }
//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+    
void OnDeinit(const int reason)
  {
//---
   Comment("");
//---
  }
//+------------------------------------------------------------------+  
//| Custom indicator iteration function                              | 
//+------------------------------------------------------------------+  
int OnCalculate(const int rates_total,    // ���������� ������� � ����� �� ������� ����
                const int prev_calculated,// ���������� ������� � ����� �� ���������� ����
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
//--- �������� ���������� ����� �� ������������� ��� �������
   if(rates_total<min_rates_total) return(0);
//---
   int bar0=rates_total-1;
//--- ������ ���������� ������ first ��� ����� ��������� �����
   if(prev_calculated>rates_total || prev_calculated<=0) // �������� �� ������ ����� ������� ����������
     {
      for(int bar=0; bar<=bar0 && !IsStopped(); bar++)
        {
         buf0[bar]=EMPTY_VALUE;
         buf1[bar]=EMPTY_VALUE;
         buf2[bar]=EMPTY_VALUE;
        }
     }
//---
   if(prev_calculated!=rates_total)
     {
      buf0[bar0]=0;
      buf2[bar0]=99999999;
     }
//---
   double sp=spread[bar0];
   string st="";
   datetime iTimeH1[1],iTimeH4[1],iTimeD1[1];
//---
   if(CopyTime(Symbol(),PERIOD_H1,time[bar0],1,iTimeH1)<=0) return(0);
   if(CopyTime(Symbol(),PERIOD_H4,time[bar0],1,iTimeH4)<=0) return(0);
   if(CopyTime(Symbol(),PERIOD_D1,time[bar0],1,iTimeD1)<=0) return(0);
//---
   buf1[bar0]=sp;
   if(buf0[bar0]==EMPTY_VALUE) buf0[bar0]=sp;
   if(sp>buf0[bar0]) buf0[bar0]=sp;
   if(sp<buf2[bar0] && sp) buf2[bar0]=sp;
//---
   if(prevH1<iTimeH1[0])
     {
      maxH1=sp;
      minH1=sp;
     }
   prevH1=iTimeH1[0];
   if(maxH1<sp) maxH1=sp;
   if(minH1>sp) minH1=sp;
//---
   if(prevH4<iTimeH4[0])
     {
      maxH4=sp;
      minH4=sp;
     }
   prevH4=iTimeH4[0];
   if(maxH4<sp) maxH4=sp;
   if(minH4>sp) minH4=sp;
//---
   if(prevD1<iTimeD1[0])
     {
      maxD1=sp;
      minD1=sp;
     }
   prevD1=iTimeD1[0];
   if(maxD1<sp) maxD1=sp;
   if(minD1>sp) minD1=sp;
//---
   StringConcatenate(st,"Maximum on H1 = ",DoubleToString(maxH1,2),"\n"
                     ,"Maximum on H4 = ",DoubleToString(maxH4,2),"\n"
                     ,"Maximum on D1 = ",DoubleToString(maxD1,2),"\n"
                     ,"Current spread = ",DoubleToString(sp,2),"\n"
                     ,"Minimum on D1 = ",DoubleToString(minD1,2),"\n"
                     ,"Minimum on H4 = ",DoubleToString(minH4,2),"\n"
                     ,"Minimum on H1 = ",DoubleToString(minH1,2),"\n"
                     );
   Comment(st);
//---
   if(WriteInFile)
     {
      if(prevSpread!=sp)
        {
         StringConcatenate(st,TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),";",DoubleToString(sp,2));
         WritingLineInFile(FileName_,st);
        }
     }
   prevSpread=sp;
//---    
   return(rates_total);
  }
//+----------------------------------------------------------------------------+
//|                                                                            |
//|  ���������������� �������                                                  |
//|                                                                            |
//+----------------------------------------------------------------------------+
//|  ��������� ���������� � ���� ������                                        |
//+----------------------------------------------------------------------------+
string GetStringTimeframe(ENUM_TIMEFRAMES timeframe)
  {return(StringSubstr(EnumToString(timeframe),7,-1));}
//+----------------------------------------------------------------------------+
//|  �����    : ��� ����� �. aka KimIV,  http://www.kimiv.ru                   |
//+----------------------------------------------------------------------------+
//|  ������   : 01.09.2005                                                     |
//|  �������� : ���������� ������ � ������ ��������                            |
//+----------------------------------------------------------------------------+
string StringLower(string s)
  {
//---
   int c,i,k=StringLen(s),n;
   for(i=0; i<k; i++)
     {
      n=0;
      c=StringGetCharacter(s, i);
      if(c>64 && c<91) n=c+32;     // A-Z -> a-z
      if(c>191 && c<224) n=c+32;   // �-� -> �-�
      if(c==168) n=184;            //  �  ->  �
      if(n>0) StringSetCharacter(s,i,ushort(n));
     }
//---
   return(s);
  }
//+----------------------------------------------------------------------------+
//|  �����    : ��� ����� �. aka KimIV,  http://www.kimiv.ru                   |
//+----------------------------------------------------------------------------+
//|  ������   : 01.09.2005                                                     |
//+----------------------------------------------------------------------------+
//|  �������� : ������ ������ � ����                                           |
//|  ���������:                                                                |
//|    FileName - ��� �����                                                    |
//|    text     - ������                                                       |
//+----------------------------------------------------------------------------+
void WritingLineInFile(string File_Name,string text)
  {
//---
   int file_handle=FileOpen(File_Name,FILE_READ|FILE_WRITE," ");

   if(file_handle>0)
     {
      FileSeek(file_handle,0,SEEK_END);
      FileWrite(file_handle,text);
      FileClose(file_handle);
     }
//---
  }
//+------------------------------------------------------------------+
