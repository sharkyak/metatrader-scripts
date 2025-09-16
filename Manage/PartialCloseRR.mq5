#include <Trade\Trade.mqh>

input double InputRR     = 3.0;   // Целевой RR
input double ClosePercent = 50.0; // Процент от объема для закрытия

CTrade trade;

// Локальное хранилище уже обработанных ордеров
ulong processed_orders[];

bool IsProcessed(ulong ticket)
{
   for (int i = 0; i < ArraySize(processed_orders); ++i)
      if (processed_orders[i] == ticket)
         return true;
   return false;
}

void MarkProcessed(ulong ticket)
{
   ArrayResize(processed_orders, ArraySize(processed_orders) + 1);
   processed_orders[ArraySize(processed_orders) - 1] = ticket;
}

void OnTick()
{
    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if (!PositionSelectByTicket(ticket)) continue;
        if (IsProcessed(ticket)) continue;

        string symbol     = PositionGetString(POSITION_SYMBOL);
        double volume     = PositionGetDouble(POSITION_VOLUME);
        double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
        double sl         = PositionGetDouble(POSITION_SL);
        int type          = (int)PositionGetInteger(POSITION_TYPE);

        if (sl == 0.0) continue;

        double current_price = 0.0;
        if (!SymbolInfoDouble(symbol, (type == POSITION_TYPE_BUY ? SYMBOL_BID : SYMBOL_ASK), current_price))
            continue;

        double rr = 0.0;
        if (type == POSITION_TYPE_BUY)
            rr = (current_price - open_price) / (open_price - sl);
        else
            rr = (open_price - current_price) / (sl - open_price);

        PrintFormat("ℹ️ Позиция #%I64u RR=%.2f (цель %.2f)", ticket, rr, InputRR);

        if (rr >= InputRR)
        {
            double close_volume = NormalizeDouble(volume * ClosePercent / 100.0, 2);

            PrintFormat("✅ RR=%.2f достигнут для %s (#%I64u), закрываем %.2f из %.2f",
                        rr, symbol, ticket, close_volume, volume);

            if (trade.PositionClosePartial(ticket, close_volume))
            {
                PrintFormat("✔ Успешно закрыли %.2f лота по #%I64u", close_volume, ticket);
                MarkProcessed(ticket);
            }
            else
            {
                PrintFormat("❌ Ошибка при частичном закрытии #%I64u: %s",
                            ticket, trade.ResultRetcodeDescription());
            }
        }
    }
}
