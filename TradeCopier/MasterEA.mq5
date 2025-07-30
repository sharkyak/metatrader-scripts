//+------------------------------------------------------------------+
//|                     MasterEA.mq5                                 |
//|    Эксперт для записи рыночных ордеров в файл                    |
//+------------------------------------------------------------------+
#property strict

input int SyncIntervalSeconds = 2;

string TEMP_PATH;
string FINAL_PATH;

// --- Initialization ---
int OnInit()
{
   TEMP_PATH  = "mt5_copy_orders.tmp";
   FINAL_PATH = "mt5_copy_orders.txt";

   EventSetTimer(SyncIntervalSeconds);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
}

void OnTimer()
{
   string data = "";

   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;

      string symbol     = PositionGetString(POSITION_SYMBOL);
      int    type       = (int)PositionGetInteger(POSITION_TYPE);
      double volume     = PositionGetDouble(POSITION_VOLUME);
      double price_open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl         = PositionGetDouble(POSITION_SL);
      double tp         = PositionGetDouble(POSITION_TP);
      long   magic      = PositionGetInteger(POSITION_MAGIC);

      Print("📤 Экспорт позиции: ", symbol, " ", DoubleToString(volume, 2),
            " lot, type=", type, " magic=", magic);

      data += StringFormat("%s|%d|%.2f|%.5f|%.5f|%.5f|%d\n",
                           symbol, type, volume, price_open, sl, tp, magic);
   }

   //--- запись во временный файл
   int handle = FileOpen(TEMP_PATH, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(handle != INVALID_HANDLE)
   {
      FileWriteString(handle, data);
      FileClose(handle);

      FileDelete(FINAL_PATH, FILE_COMMON);
      bool copied = FileCopy(TEMP_PATH, FILE_COMMON,
                             FINAL_PATH, FILE_COMMON);
      if(copied)
      {
         //Print("✅ Обновлён файл: ", FINAL_PATH);
      }
      else
         Print("❌ Ошибка копирования файла!");
   }
   else
   {
      Print("❌ Ошибка открытия файла: ", GetLastError());
   }
}
