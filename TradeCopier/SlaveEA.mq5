//+------------------------------------------------------------------+
//|                        SlaveEA.mq5                               |
//|   Синхронизация ордеров с мастер‑счёта через файл                |
//+------------------------------------------------------------------+
#property strict
#include <Trade\Trade.mqh>
CTrade trade;

input double  ScaleFactor         = 2.0;
input bool    ModifySLTP          = true;
input bool    CloseMissingOrders  = true;
input int     SyncIntervalSeconds = 2;

string FILE_PATH;

//‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑ парсер строки из файла
struct OrderData
{
   string symbol; int type; double volume; double price; double sl; double tp; long magic;
};

bool ParseLine(const string line, OrderData &o)
{
   string p[];
   if(StringSplit(line, '|', p) < 7)
      return false;
   o.symbol = p[0];
   o.type   = (int)StringToInteger(p[1]);
   o.volume = StringToDouble(p[2]) * ScaleFactor;
   o.price  = StringToDouble(p[3]);
   o.sl     = StringToDouble(p[4]);
   o.tp     = StringToDouble(p[5]);
   o.magic  = (long)StringToInteger(p[6]);

   // проверка символа
   if(!SymbolInfoInteger(o.symbol, SYMBOL_EXIST))
      return false;

   // округление и проверка объёма
   o.volume = NormalizeVolume(o.symbol, o.volume);
   if(o.volume <= 0)
      return false;

   return true;
}

double NormalizeVolume(const string symbol, double vol)
{
   double volumeStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   double volumeMin  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double volumeMax  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);

   vol = MathFloor(vol / volumeStep) * volumeStep;

   int lotDecimals = 0;
   if(volumeStep == 0.01) lotDecimals = 2;
   else if(volumeStep == 0.1) lotDecimals = 1;
   else if(volumeStep == 1.0) lotDecimals = 0;
   else lotDecimals = 8;

   vol = NormalizeDouble(vol, lotDecimals);

   if(vol < volumeMin) return 0;
   if(vol > volumeMax) return volumeMax;
   return vol;
}

//‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑ основные хэндлеры
int OnInit()
{
   FILE_PATH = "mt5_copy_orders.txt";
   EventSetTimer(SyncIntervalSeconds);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int r)
{
   EventKillTimer();
}

void OnTimer()
{
   int f = FileOpen(FILE_PATH, FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(f == INVALID_HANDLE)
      return;

   // читаем все строки файла
   OrderData orders[];
   int count = 0;
   while(!FileIsEnding(f))
   {
      string line = FileReadString(f);
      if(StringLen(line) == 0)
         continue;
      OrderData o;
      if(!ParseLine(line, o))
         continue;
      ArrayResize(orders, count + 1);
      orders[count] = o;
      count++;
   }
   FileClose(f);

   // синхронизация существующих позиций и открытие новых
   for(int i = 0; i < count; i++)
   {
      OrderData o = orders[i];
      bool found = false;

      for(int j = 0; j < PositionsTotal(); j++)
      {
         ulong ticket = PositionGetTicket(j);
         if(!PositionSelectByTicket(ticket))
            continue;
         if(PositionGetInteger(POSITION_TYPE) != o.type)
            continue;
         if(PositionGetString(POSITION_SYMBOL) != o.symbol)
            continue;

         found = true;
         double cur = PositionGetDouble(POSITION_VOLUME);

         // уменьшение объёма
         if(cur - o.volume > 0.0001)
         {
            double diff = NormalizeVolume(o.symbol, cur - o.volume);
            if(diff > 0)
            {
               Print("✂️ Частичное закрытие: ", o.symbol, " на ", DoubleToString(diff, 2), " lot");
               //trade.PositionClosePartial(ticket, diff);
            }
         }

         // увеличение объёма (доливка)
         if(o.volume - cur > 0.0001)
         {
            double diff = NormalizeVolume(o.symbol, o.volume - cur);
            if(diff > 0)
            {
               Print("➕ Доливка: ", o.symbol, " на ", DoubleToString(diff, 2), " lot");
               //trade.SetExpertMagicNumber(o.magic);
               //if(o.type == POSITION_TYPE_BUY)
               //   trade.Buy(diff, o.symbol, 0, o.sl, o.tp);
               //else
               //   trade.Sell(diff, o.symbol, 0, o.sl, o.tp);
            }
         }

         // модификация SL/TP
         if(ModifySLTP)
         {
            double curSL = PositionGetDouble(POSITION_SL);
            double curTP = PositionGetDouble(POSITION_TP);
            if(MathAbs(curSL - o.sl) > _Point || MathAbs(curTP - o.tp) > _Point)
            {
               Print("🔁 Изменён SL/TP: ", o.symbol, " SL=", DoubleToString(o.sl, 5), " TP=", DoubleToString(o.tp, 5));
               //trade.PositionModify(ticket, o.sl, o.tp);
            }
         }
         break;
      }

      if(!found)
      {
         Print("🆕 Новая позиция: ", o.symbol, " ", DoubleToString(o.volume, 2), " lot, type=", o.type);
         //trade.SetExpertMagicNumber(o.magic);
         //if(o.type == POSITION_TYPE_BUY)
         //   trade.Buy(o.volume, o.symbol, 0, o.sl, o.tp);
         //else
         //   trade.Sell(o.volume, o.symbol, 0, o.sl, o.tp);
      }
   }

   // закрытие лишних позиций
   if(CloseMissingOrders)
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(!PositionSelectByTicket(ticket))
            continue;
         string s = PositionGetString(POSITION_SYMBOL);
         int    t = (int)PositionGetInteger(POSITION_TYPE);

         bool exists = false;
         for(int j = 0; j < count; j++)
         {
            if(orders[j].symbol == s && orders[j].type == t)
            {
               exists = true;
               break;
            }
         }

         if(!exists)
         {
            Print("❌ Закрыта лишняя позиция: ", s, " type=", t);
            //trade.PositionClose(ticket);
         }
      }
   }
}
