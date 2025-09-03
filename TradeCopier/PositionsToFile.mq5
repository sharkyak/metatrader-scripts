//+------------------------------------------------------------------+
//|                                               PositionToFile.mq5 |
//|                      Copyright 2025, Ваш программист-помощник AI |
//|                                           https://www.google.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Ваш программист-помощник AI"
#property link      "https://www.google.com"
#property version   "1.60" // Без генерации имен.
#property indicator_chart_window
#property indicator_plots 0

//--- Входные параметры
input int    TimerPeriodSeconds = 1;                  // Период работы в секундах
input string PositionsFileName  = "open_positions.csv"; // Имя основного файла
input string TempFileName       = "open_positions.tmp"; // Имя временного файла

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
  {
   EventSetTimer(TimerPeriodSeconds);
   Print("Индикатор записи позиций запущен. Основной файл: ", PositionsFileName, ", Временный файл: ", TempFileName);
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   FileDelete(PositionsFileName, FILE_COMMON);
   FileDelete(TempFileName, FILE_COMMON);
   Print("Индикатор записи позиций остановлен. Файлы удалены.");
  }
//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
  {
   CheckOpenPositions();
  }
//+------------------------------------------------------------------+
//| Проверка и запись открытых позиций в файл                        |
//+------------------------------------------------------------------+
void CheckOpenPositions()
  {
   if(PositionsTotal() == 0)
     {
      if(FileIsExist(PositionsFileName, FILE_COMMON))
         FileDelete(PositionsFileName, FILE_COMMON);
      return;
     }

   int file_handle = FileOpen(TempFileName, FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON, ",");

   if(file_handle == INVALID_HANDLE)
     {
      Print("Ошибка открытия временного файла ", TempFileName, " в общей папке. Код ошибки: ", GetLastError());
      return;
     }

   for(int i = 0; i < PositionsTotal(); i++)
     {
      ulong position_ticket = PositionGetTicket(i);
      if(position_ticket > 0)
        {
         string symbol = PositionGetString(POSITION_SYMBOL);
         long type = PositionGetInteger(POSITION_TYPE);
         double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
         double volume = PositionGetDouble(POSITION_VOLUME);
         string type_str = (type == POSITION_TYPE_BUY) ? "buy" : "sell";

         FileWrite(file_handle,
                   (string)position_ticket,
                   symbol,
                   type_str,
                   DoubleToString(open_price, _Digits),
                   DoubleToString(volume, 2));
        }
     }

   FileClose(file_handle);

   if(!FileMove(TempFileName, FILE_COMMON, PositionsFileName, FILE_COMMON|FILE_REWRITE))
     {
      Print("Ошибка переименования временного файла в общей папке. Код ошибки: ", GetLastError());
     }
  }

//+------------------------------------------------------------------+
//| OnCalculate - Обязательная функция для индикатора                |
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
   return(rates_total);
  }
//+------------------------------------------------------------------+