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
   string p[]; if(StringSplit(line,'|',p)<7) return false;
   o.symbol=p[0]; o.type=(int)StringToInteger(p[1]);
   o.volume=StringToDouble(p[2])*ScaleFactor; o.price=StringToDouble(p[3]);
   o.sl=StringToDouble(p[4]); o.tp=StringToDouble(p[5]); o.magic=(long)StringToInteger(p[6]);
   return true;
}
void OpenOrder(const OrderData &o)
{
   trade.SetExpertMagicNumber(o.magic);
   (o.type==POSITION_TYPE_BUY)? trade.Buy(o.volume,o.symbol,o.price,o.sl,o.tp,NULL)
                              : trade.Sell(o.volume,o.symbol,o.price,o.sl,o.tp,NULL);
}

//‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑‑ основные хэндлеры
int OnInit(){ FILE_PATH="mt5_copy_orders.txt"; EventSetTimer(SyncIntervalSeconds); return INIT_SUCCEEDED; }
void OnDeinit(const int r){ EventKillTimer(); }

void OnTimer()
{
   Print("🔄 Синхронизация…");

   int f=FileOpen(FILE_PATH,FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(f==INVALID_HANDLE){
      Print("❌ FileOpen error: ",GetLastError());
      return;
   }

   string content=FileReadString(f); FileClose(f);
   string lines[]; StringSplit(content,'\n',lines);
   int count=ArraySize(lines);

   for(int i=0;i<count;i++)
   {
      OrderData o; if(!ParseLine(lines[i],o)) continue;
      bool found=false;

      for(int j=0;j<PositionsTotal();j++)
      {
         ulong ticket=PositionGetTicket(j);
         if(!PositionSelectByTicket(ticket)) continue;
         if(PositionGetInteger(POSITION_MAGIC)!=o.magic)   continue;
         if(PositionGetInteger(POSITION_TYPE)!=o.type)     continue;
         if(PositionGetString(POSITION_SYMBOL)!=o.symbol)  continue;

         found=true;
         double cur=PositionGetDouble(POSITION_VOLUME);

         //‑‑ уменьшение объёма
         if(cur-o.volume>0.0001){
            double diff=cur-o.volume;
            Print("✂️ Частично закрыта позиция: ",o.symbol," на ",DoubleToString(diff,2)," lot");
            trade.PositionClosePartial(o.symbol,diff);
         }

         if(ModifySLTP){
            double curSL=PositionGetDouble(POSITION_SL), curTP=PositionGetDouble(POSITION_TP);
            if(MathAbs(curSL-o.sl)>_Point||MathAbs(curTP-o.tp)>_Point){
               Print("🔁 Изменён SL/TP: ",o.symbol," SL=",DoubleToString(o.sl,5)," TP=",DoubleToString(o.tp,5));
               trade.PositionModify(o.symbol,o.sl,o.tp);
            }
         }
      }

      if(!found){
         Print("🆕 Новая позиция: ",o.symbol," ",DoubleToString(o.volume,2)," lot, type=",o.type," magic=",o.magic);
         OpenOrder(o);
      }
   }

   if(CloseMissingOrders)
   {
      for(int i=PositionsTotal()-1;i>=0;i--)
      {
         ulong ticket=PositionGetTicket(i);
         if(!PositionSelectByTicket(ticket)) continue;
         string s=PositionGetString(POSITION_SYMBOL); int t=(int)PositionGetInteger(POSITION_TYPE); long m=PositionGetInteger(POSITION_MAGIC);

         bool exists=false;
         for(int j=0;j<count;j++){ OrderData o; if(!ParseLine(lines[j],o)) continue;
            if(o.symbol==s&&o.type==t&&o.magic==m){ exists=true; break; } }

         if(!exists){
            Print("❌ Закрыта лишняя позиция: ",s," type=",t," magic=",m);
            trade.PositionClose(s);
         }
      }
   }
}
