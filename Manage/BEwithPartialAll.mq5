#property copyright "Copyright 2025, Aleksand Kazakov"
#property version   "2.1"
#property description "Переносит SL в BE при достижении целевого RR и опционально частично закрывает позицию. Пропускает позиции без SL."

#include <Trade/Trade.mqh>
CTrade trade;

// === Входные параметры
input double TARGET_RR = 2.0;           // Целевой риск/ревард
input bool MOVE_TO_BE_ONLY = false;     // TRUE: только SL->BE

// === Глобальные переменные для отслеживания обработанных тикетов через Global Variables
#define GV_PREFIX "processed_ticket_"

//+------------------------------------------------------------------+
//| OnTick: основной цикл обработки                                  |
//+------------------------------------------------------------------+
void OnTick()
{
   int total = PositionsTotal();
   for (int i = total - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (!PositionSelectByTicket(ticket))
         continue;

      if (IsProcessed(ticket))
         continue;

      string symbol  = PositionGetString(POSITION_SYMBOL);
      int type       = (int)PositionGetInteger(POSITION_TYPE);
      double entry   = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl      = PositionGetDouble(POSITION_SL);
      double tp      = PositionGetDouble(POSITION_TP);
      double volume  = PositionGetDouble(POSITION_VOLUME);

      // Если SL равен 0.0, значит он не установлен. Пропускаем эту позицию.
      if (sl == 0.0)
      {
         continue;
      }

      if (type != POSITION_TYPE_BUY && type != POSITION_TYPE_SELL)
         continue;

      double bid, ask;
      if (!SymbolInfoDouble(symbol, SYMBOL_BID, bid) || !SymbolInfoDouble(symbol, SYMBOL_ASK, ask))
         continue;

      double min_lot, lot_step;
      if (!SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN, min_lot) ||
          !SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP, lot_step))
         continue;

      double current_rr = 0.0;
      if (!HasReachedTargetRR(type, entry, sl, bid, ask, TARGET_RR, current_rr))
         continue;

      // Переносим SL в точку входа
      if (trade.PositionModify(symbol, entry, tp))
      {
         PrintFormat("✅ %s | Ticket #%d | RR %.2f достигнут — SL перенесён на %.5f", symbol, ticket, current_rr, entry);
      }
      else
      {
         PrintFormat("❌ %s | Ticket #%d | Ошибка переноса SL", symbol, ticket);
         continue;
      }

      if (!MOVE_TO_BE_ONLY)
      {
         double fraction = 1.0 / TARGET_RR;
         double volume_to_close = NormalizeLot(volume * fraction, lot_step);

         if (volume_to_close >= min_lot && volume_to_close < volume)
         {
            if (trade.PositionClosePartial(symbol, volume_to_close))
            {
               PrintFormat("🟡 %s | Ticket #%d | Частично закрыто %.2f лота из %.2f", symbol, ticket, volume_to_close, volume);
            }
            else
            {
               PrintFormat("❌ %s | Ticket #%d | Ошибка частичного закрытия %.2f лота", symbol, ticket, volume_to_close);
            }
         }
      }

      AddToProcessed(ticket);
   }
}

//+------------------------------------------------------------------+
//| Проверка достижения RR                                           |
//+------------------------------------------------------------------+
bool HasReachedTargetRR(int type, double entry_price, double initial_sl,
                        double bid, double ask, double target_rr,
                        double &out_rr)
{
   double risk = MathAbs(entry_price - initial_sl);
   if (risk < 1e-6)
      return false;

   double reward_now = 0.0;

   if (type == POSITION_TYPE_BUY)
      reward_now = bid - entry_price;
   else if (type == POSITION_TYPE_SELL)
      reward_now = entry_price - ask;

   out_rr = reward_now / risk;
   return out_rr >= target_rr;
}

//+------------------------------------------------------------------+
//| Проверка, был ли тикет уже обработан                             |
//+------------------------------------------------------------------+
bool IsProcessed(ulong ticket)
{
   string gv_name = GV_PREFIX + (string)ticket;
   return GlobalVariableCheck(gv_name);
}

//+------------------------------------------------------------------+
//| Добавить тикет в список обработанных                             |
//+------------------------------------------------------------------+
void AddToProcessed(ulong ticket)
{
   string gv_name = GV_PREFIX + (string)ticket;
   GlobalVariableSet(gv_name, TimeCurrent());
}

//+------------------------------------------------------------------+
//| Округление объёма к шагу                                         |
//+------------------------------------------------------------------+
double NormalizeLot(double volume, double step)
{
   return MathFloor(volume / step) * step;
}