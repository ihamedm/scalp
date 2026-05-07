//+------------------------------------------------------------------+
//|                                            GridHedgeEA_V13.mq5   |
//|                     
//+------------------------------------------------------------------+
#property copyright "Hamed Movasaqpoor"
#property link      ""
#property version   "1.03"

#include <Trade\Trade.mqh>

//------------------------- ENUM for trade direction (internal) -------------------------
enum ENUM_ORDER_DIR
  {
   BUY_STOP,
   SELL_STOP
  };

//------------------------- INPUT PARAMETERS -------------------------
input group "=== تنظیمات کلی ==="
input bool     EnableTrading      = true;               // فعال‌سازی اولیه
input bool     ResetGridOnStart   = true;               // حذف سفارشات قبلی و شروع دوباره
input int      MagicNumber        = 202502;             // شماره جادویی اکسپرت
input double   TotalProfitTarget  = 10.0;               // سود کل به دلار (بستن همه)
input double   TotalStopLoss      = -50.0;              // ضرر کل به دلار (عدد منفی)
input double   PipSize            = 10.0;               // هر پیپ چند نقطه (برای جفت‌ارز ۱۰)

input group "=== خرید ۱ (Buy #1) ==="
input double   Buy1_StepPips = 0.5;   // فاصله از Ask (پیپ)
input double   Buy1_Lot      = 0.01;   // حجم
input double   Buy1_SL       = 2.0;    // حد ضرر به دلار (۰ = بدون حد)
input double   Buy1_TP       = 1.0;    // حد سود به دلار

input group "=== خرید ۲ (Buy #2) ==="
input double   Buy2_StepPips = 10.0;
input double   Buy2_Lot      = 0.01;
input double   Buy2_SL       = 2.0;
input double   Buy2_TP       = 1.0;

input group "=== خرید ۳ (Buy #3) ==="
input double   Buy3_StepPips = 15.0;
input double   Buy3_Lot      = 0.02;
input double   Buy3_SL       = 3.0;
input double   Buy3_TP       = 2.0;

input group "=== خرید ۴ (Buy #4) ==="
input double   Buy4_StepPips = 15.0;
input double   Buy4_Lot      = 0.02;
input double   Buy4_SL       = 3.0;
input double   Buy4_TP       = 2.0;

input group "=== خرید ۵ (Buy #5) ==="
input double   Buy5_StepPips = 20.0;
input double   Buy5_Lot      = 0.03;
input double   Buy5_SL       = 4.0;
input double   Buy5_TP       = 3.0;

input group "=== خرید ۶ (Buy #6) ==="
input double   Buy6_StepPips = 20.0;
input double   Buy6_Lot      = 0.03;
input double   Buy6_SL       = 4.0;
input double   Buy6_TP       = 3.0;

input group "=== فروش ۱ (Sell #1) ==="
input double   Sell1_StepPips = 0.5;
input double   Sell1_Lot      = 0.01;
input double   Sell1_SL       = 2.0;
input double   Sell1_TP       = 1.0;

input group "=== فروش ۲ (Sell #2) ==="
input double   Sell2_StepPips = 10.0;
input double   Sell2_Lot      = 0.01;
input double   Sell2_SL       = 2.0;
input double   Sell2_TP       = 1.0;

input group "=== فروش ۳ (Sell #3) ==="
input double   Sell3_StepPips = 15.0;
input double   Sell3_Lot      = 0.02;
input double   Sell3_SL       = 3.0;
input double   Sell3_TP       = 2.0;

input group "=== فروش ۴ (Sell #4) ==="
input double   Sell4_StepPips = 15.0;
input double   Sell4_Lot      = 0.02;
input double   Sell4_SL       = 3.0;
input double   Sell4_TP       = 2.0;

input group "=== فروش ۵ (Sell #5) ==="
input double   Sell5_StepPips = 20.0;
input double   Sell5_Lot      = 0.03;
input double   Sell5_SL       = 4.0;
input double   Sell5_TP       = 3.0;

input group "=== فروش ۶ (Sell #6) ==="
input double   Sell6_StepPips = 20.0;
input double   Sell6_Lot      = 0.03;
input double   Sell6_SL       = 4.0;
input double   Sell6_TP       = 3.0;

//------------------------- GLOBAL VARIABLES -------------------------
CTrade GridTrade;                 // شیء معاملاتی
double pointValue;                // ارزش هر نقطه (نرخ P/L) برای یک لات
bool   isTradingActive = false;  // وضعیت واقعی فعال بودن (قابل تغییر)
bool   tradingDone     = false;  // آیا بستن کلی انجام شده؟

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize == 0 || tickValue == 0)
     {
      Print("خطا: عدم دسترسی به اطلاعات TickSize/TickValue");
      return(INIT_FAILED);
     }
   pointValue = tickValue / tickSize;

   tradingDone = false;
   isTradingActive = EnableTrading;

   if(!isTradingActive)
     {
      Print("EnableTrading = false؛ معامله‌ای باز نمی‌شود.");
      return(INIT_SUCCEEDED);
     }

   if(ResetGridOnStart)
      DeleteAllOrdersAndPositions();

   PlaceGrid();
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(!isTradingActive || tradingDone)
      return;

   CheckTotalProfitLoss();
  }

//+------------------------------------------------------------------+
//| حذف تمام سفارشات معلق و بستن پوزیشن‌های باز با این Magic         |
//+------------------------------------------------------------------+
void DeleteAllOrdersAndPositions()
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(OrderSelect(ticket))
        {
         if(OrderGetInteger(ORDER_MAGIC) == MagicNumber &&
            OrderGetInteger(ORDER_TYPE) <= ORDER_TYPE_SELL_STOP)
           {
            if(!GridTrade.OrderDelete(ticket))
               Print("خطا در حذف سفارش معلق #", ticket, " : ", GetLastError());
           }
        }
     }

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
        {
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber)
           {
            if(!GridTrade.PositionClose(ticket))
               Print("خطا در بستن پوزیشن #", ticket, " : ", GetLastError());
           }
        }
     }
  }



//+------------------------------------------------------------------+
//| قرار دادن شبکه ۶ Buy Stop و ۶ Sell Stop (با اصلاح SL/TP فروش)    |
//+------------------------------------------------------------------+
void PlaceGrid()
  {
   long stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   // ---- خریدها (Buy Stop) ----
   double prevBuy = 0;
   for(int i = 0; i < 6; i++)
     {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(i == 0) prevBuy = ask;

      double price, sl, tp;
      double lot, stepPips, slDollar, tpDollar;

      switch(i)
        {
         case 0: stepPips = Buy1_StepPips; lot = Buy1_Lot; slDollar = Buy1_SL; tpDollar = Buy1_TP; break;
         case 1: stepPips = Buy2_StepPips; lot = Buy2_Lot; slDollar = Buy2_SL; tpDollar = Buy2_TP; break;
         case 2: stepPips = Buy3_StepPips; lot = Buy3_Lot; slDollar = Buy3_SL; tpDollar = Buy3_TP; break;
         case 3: stepPips = Buy4_StepPips; lot = Buy4_Lot; slDollar = Buy4_SL; tpDollar = Buy4_TP; break;
         case 4: stepPips = Buy5_StepPips; lot = Buy5_Lot; slDollar = Buy5_SL; tpDollar = Buy5_TP; break;
         case 5: stepPips = Buy6_StepPips; lot = Buy6_Lot; slDollar = Buy6_SL; tpDollar = Buy6_TP; break;
        }

      price = ask + stepPips * PipSize * _Point;

      // فاصله ایمن از Ask برای Buy Stop
      double minEntryDist = (stopsLevel + 2) * _Point;
      if(price - ask < minEntryDist)
         price = ask + minEntryDist;

      // Buy: SL = پایین‌تر (false), TP = بالاتر (true)
      sl = (slDollar > 0) ? CalculatePriceLevel(price, slDollar, lot, false) : 0;
      tp = (tpDollar > 0) ? CalculatePriceLevel(price, tpDollar, lot, true) : 0;

      PlacePendingOrder(ORDER_TYPE_BUY_STOP, lot, price, sl, tp, "BuyStop_" + IntegerToString(i+1));
      Print("BuyStop ", i+1, " | Ask=", ask, " | Entry=", price,
            " | SL=", sl, " TP=", tp);
      prevBuy = price;
     }

   // ---- فروش‌ها (Sell Stop) ----
   double prevSell = 0;
   for(int i = 0; i < 6; i++)
     {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(i == 0) prevSell = bid;

      double price, sl, tp;
      double lot, stepPips, slDollar, tpDollar;

      switch(i)
        {
         case 0: stepPips = Sell1_StepPips; lot = Sell1_Lot; slDollar = Sell1_SL; tpDollar = Sell1_TP; break;
         case 1: stepPips = Sell2_StepPips; lot = Sell2_Lot; slDollar = Sell2_SL; tpDollar = Sell2_TP; break;
         case 2: stepPips = Sell3_StepPips; lot = Sell3_Lot; slDollar = Sell3_SL; tpDollar = Sell3_TP; break;
         case 3: stepPips = Sell4_StepPips; lot = Sell4_Lot; slDollar = Sell4_SL; tpDollar = Sell4_TP; break;
         case 4: stepPips = Sell5_StepPips; lot = Sell5_Lot; slDollar = Sell5_SL; tpDollar = Sell5_TP; break;
         case 5: stepPips = Sell6_StepPips; lot = Sell6_Lot; slDollar = Sell6_SL; tpDollar = Sell6_TP; break;
        }

      price = bid - stepPips * PipSize * _Point;

      double minEntryDist = (stopsLevel + 2) * _Point;
      if(bid - price < minEntryDist)
         price = bid - minEntryDist;

      // Sell: SL = بالاتر (true), TP = پایین‌تر (false)  <-- تصحیح اینجا
      sl = (slDollar > 0) ? CalculatePriceLevel(price, slDollar, lot, true) : 0;   // SL بالا
      tp = (tpDollar > 0) ? CalculatePriceLevel(price, tpDollar, lot, false) : 0;  // TP پایین

      PlacePendingOrder(ORDER_TYPE_SELL_STOP, lot, price, sl, tp, "SellStop_" + IntegerToString(i+1));
      Print("SellStop ", i+1, " | Bid=", bid, " | Entry=", price,
            " | SL=", sl, " TP=", tp);
      prevSell = price;
     }

   Print("شبکه کامل ۱۲ سفارش با موفقیت قرار داده شد.");
  }

//+------------------------------------------------------------------+
//| ارسال سفارش معلق (Buy Stop / Sell Stop) – نسخه پایدار           |
//+------------------------------------------------------------------+
bool PlacePendingOrder(ENUM_ORDER_TYPE type, double lot, double entry,
                       double sl, double tp, string comment)
  {
   Sleep(30); // مکث کوتاه برای جلوگیری از رد درخواست‌ها

   MqlTradeRequest request = {};
   MqlTradeResult  result  = {};
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   request.action    = TRADE_ACTION_PENDING;
   request.symbol    = _Symbol;
   request.volume    = lot;
   request.price     = NormalizeDouble(entry, digits);
   request.type      = type;
   request.sl        = (sl > 0) ? NormalizeDouble(sl, digits) : 0;
   request.tp        = (tp > 0) ? NormalizeDouble(tp, digits) : 0;
   request.magic     = MagicNumber;
   request.comment   = comment;
   request.type_filling = ORDER_FILLING_RETURN;   // <-- تغییر کلیدی
   request.type_time    = ORDER_TIME_GTC;
   request.deviation    = 0;                     // برای سفارش معلق انحراف نداریم

   if(!OrderSend(request, result))
     {
      Print("OrderSend error: ", GetLastError(), " | Volume: ", lot,
            " Entry: ", entry, " SL: ", sl, " TP: ", tp,
            " | retcode=", result.retcode);
      return false;
     }

   Print("سفارش ", comment, " (Ticket ", result.order, ") با موفقیت ثبت شد. ",
         "Entry=", entry, " Lot=", lot, " SL=", sl, " TP=", tp);
   return true;
  }

//+------------------------------------------------------------------+
//| محاسبه سطح قیمت SL/TP بر اساس دلار (اصلاح‌شده)                  |
//+------------------------------------------------------------------+
double CalculatePriceLevel(double entryPrice, double dollarAmount, double lot, bool isTP)
  {
   if(dollarAmount <= 0 || lot <= 0)
      return 0;

   // محاسبه صحیح ارزش یک پیپ
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double pipValue =
   (tickValue / SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE))
   * (_Point * PipSize)
   * lot;
   
   if(pipValue == 0) return 0;

   double pipDistance = dollarAmount / pipValue;
   double priceOffset = pipDistance * PipSize * _Point; // تبدیل به قیمت

   double level;
   if(isTP)
      level = entryPrice + priceOffset;
   else
      level = entryPrice - priceOffset;

   // رعایت حداقل فاصله مجاز (STOPS_LEVEL + 2 پیپ)
   long stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist = (stopsLevel + 2) * _Point; // حداقل فاصله مجاز

   if(isTP && (level - entryPrice) < minDist)
      level = entryPrice + minDist;
   else if(!isTP && (entryPrice - level) < minDist)
      level = entryPrice - minDist;

   return NormalizeDouble(level, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
  }

//+------------------------------------------------------------------+
//| بررسی سود/زیان کل و بستن همه در صورت رسیدن به هدف               |
//+------------------------------------------------------------------+
void CheckTotalProfitLoss()
  {
   double totalProfit = 0.0;
   int posCount = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
        {
         totalProfit += PositionGetDouble(POSITION_PROFIT);
         posCount++;
        }
     }

   if(totalProfit >= TotalProfitTarget && posCount > 0)
     {
      Print("رسیدن به سود کل ", TotalProfitTarget, " دلار. بستن همه پوزیشن‌ها...");
      CloseAll();
      tradingDone = true;
      isTradingActive = false;
     }
   else if(totalProfit <= TotalStopLoss && posCount > 0)
     {
      Print("رسیدن به ضرر کل ", TotalStopLoss, " دلار. بستن همه پوزیشن‌ها...");
      CloseAll();
      tradingDone = true;
      isTradingActive = false;
     }
  }

//+------------------------------------------------------------------+
//| بستن همه پوزیشن‌ها و حذف سفارشات معلق (با همین Magic)          |
//+------------------------------------------------------------------+
void CloseAll()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
        {
         if(!GridTrade.PositionClose(ticket))
            Print("خطا در بستن پوزیشن ", ticket);
        }
     }

   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(OrderSelect(ticket) && OrderGetInteger(ORDER_MAGIC) == MagicNumber)
        {
         if(!GridTrade.OrderDelete(ticket))
            Print("خطا در حذف سفارش ", ticket);
        }
     }

   Print("تمام پوزیشن‌ها و سفارشات بسته شدند.");
  }
//+------------------------------------------------------------------+
