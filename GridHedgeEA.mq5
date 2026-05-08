//+------------------------------------------------------------------+
//|                                 GridHedge_Trend_First.mq5         |
//|            یک پوزیشن فوری بر اساس روند + شبکه ۵ پیپ              |
//+------------------------------------------------------------------+
#property copyright "Hamed Movasaqpoor"
#property link      "hamed.movasaqpoor@gmail.com"
#property version   "2.00"

#include <Trade\Trade.mqh>

int Getg_PipSize(void);

//------------------------- INPUT PARAMETERS -------------------------
input group "=== تنظیمات کلی ==="
input bool     EnableTrading        = true;       // فعال‌سازی اولیه
input bool     ResetGridOnStart     = true;       // حذف سفارشات قبلی و شروع دوباره
input int      MagicNumber          = 202601;     // شماره جادویی
input double   TotalProfitTarget    = 10.0;       // سود کل (دلار) - بستن همه
input double   TotalStopLoss        = -50.0;      // ضرر کل (عدد منفی)


input group "=== تشخیص روند (پوزیشن اول) ==="
input bool     UseManualDirection   = false;      // انتخاب دستی جهت؟
input int      DirectionChoice      = 0;          // 0 = خرید, 1 = فروش (در صورت دستی)
input int      TrendMAPeriod        = 20;         // دوره EMA برای تشخیص خودکار
input int      TrendMAShift         = 0;          // شیفت EMA
input ENUM_MA_METHOD TrendMAMethod  = MODE_EMA;   // نوع میانگین

input group "=== شبکه سفارشات معلق ==="
input int      GridLevels           = 5;          // تعداد سفارشات Buy Stop و Sell Stop
input double   GridPipStep          = 5.0;        // فاصله بین پله‌ها (پیپ)

input group "=== مدیریت سرمایه و ریسک ==="
input double   DefaultLot           = 0.01;       // حجم ثابت همه پوزیشن‌ها
input double   SL_Dollar            = 2.0;        // حد ضرر به دلار (۰ = بدون حد)
input double   TP_Dollar            = 1.0;        // حد سود به دلار (۰ = بدون حد)
input group "=== مدیریت ریسک (ادامه) ==="
input int      MinStopPaddingPips   = 30;        // حداقل فاصله استاپ از قیمت (پیپ)

//------------------------- GLOBAL VARIABLES -------------------------
CTrade GridTrade;
double pointValue;
bool   isTradingActive = false;
bool   tradingDone     = false;
int    g_PipSize;

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
  {
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize == 0 || tickValue == 0)
     {
      Print("خطا: TickSize/TickValue در دسترس نیست");
      return(INIT_FAILED);
     }
   pointValue = tickValue / tickSize;

   tradingDone = false;
   isTradingActive = EnableTrading;
   
   g_PipSize = Getg_PipSize();

   if(!isTradingActive)
     {
      Print("EnableTrading = false؛ اجرا نمی‌شود.");
      return(INIT_SUCCEEDED);
     }

   if(ResetGridOnStart)
      DeleteAllOrdersAndPositions();

   // اجرای استراتژی
   ExecuteStrategy();

   return(INIT_SUCCEEDED);
  }
  
//+------------------------------------------------------------------+
//| تشخیص خودکار g_PipSize بر اساس تعداد ارقام اعشار نماد               |
//+------------------------------------------------------------------+
int Getg_PipSize()
  {
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   switch(digits)
     {
      case 2:  // طلا با ۲ رقم اعشار (مثل ۲۳۰۰.۰۰)
      case 3:  // طلا با ۳ رقم اعشار (مثل ۲۳۰۰.۰۰۰)
         return 10;  // هر ۱۰ پوینت = ۱ پیپ
      case 4:  // جفت ارزهای ۴ رقمی
         return 1;   // هر ۱ پوینت = ۱ پیپ
      case 5:  // جفت ارزهای ۵ رقمی
      default:
         return 10;  // هر ۱۰ پوینت = ۱ پیپ
     }
  }

//+------------------------------------------------------------------+
//| Tick function                                                    |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(!isTradingActive || tradingDone)
      return;

   CheckTotalProfitLoss();
  }

//+------------------------------------------------------------------+
//| حذف سفارشات و بستن پوزیشن‌ها                                     |
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
               Print("خطا در حذف سفارش ", ticket, " : ", GetLastError());
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
               Print("خطا در بستن پوزیشن ", ticket, " : ", GetLastError());
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| اجرای استراتژی: تشخیص جهت + پوزیشن فوری + شبکه معلق             |
//+------------------------------------------------------------------+
void ExecuteStrategy()
  {
   // ---- تشخیص جهت اولین پوزیشن ----
   int direction = -1; // -1 نامشخص
   if(UseManualDirection)
     {
      direction = (DirectionChoice == 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      Print("جهت دستی انتخاب شد: ", (direction == ORDER_TYPE_BUY ? "خرید" : "فروش"));
     }
   else
     {
      direction = DetectTrendFromEMA();
      if(direction == -1)
        {
         Print("خطا در تشخیص خودکار روند. اجرا متوقف شد.");
         return;
        }
      Print("جهت تشخیص‌داده‌شده بر اساس EMA(", TrendMAPeriod, "): ",
            (direction == ORDER_TYPE_BUY ? "خرید" : "فروش"));
     }

   // ---- باز کردن پوزیشن فوری (Market Order) ----
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double slPrice = 0, tpPrice = 0;

   if(direction == ORDER_TYPE_BUY)
     {
      slPrice = (SL_Dollar > 0) ? CalculatePriceLevel(ask, SL_Dollar, DefaultLot, false) : 0;
      tpPrice = (TP_Dollar > 0) ? CalculatePriceLevel(ask, TP_Dollar, DefaultLot, true) : 0;
      if(!PlaceMarketOrder(ORDER_TYPE_BUY, DefaultLot, slPrice, tpPrice, "Initial Buy"))
         Print("خطا در ثبت خرید فوری!");
     }
   else // SELL
     {
      slPrice = (SL_Dollar > 0) ? CalculatePriceLevel(bid, SL_Dollar, DefaultLot, true) : 0;
      tpPrice = (TP_Dollar > 0) ? CalculatePriceLevel(bid, TP_Dollar, DefaultLot, false) : 0;
      if(!PlaceMarketOrder(ORDER_TYPE_SELL, DefaultLot, slPrice, tpPrice, "Initial Sell"))
         Print("خطا در ثبت فروش فوری!");
     }

   // ---- قرار دادن شبکه سفارشات معلق (Buy Stops بالا و Sell Stops پایین) ----
   PlaceGrid();
  }

//+------------------------------------------------------------------+
//| تشخیص روند با EMA (روی تایم‌فریم جاری)                          |
//+------------------------------------------------------------------+
int DetectTrendFromEMA()
  {
   // ساخت هندل EMA
   int emaHandle = iMA(_Symbol, 0, TrendMAPeriod, TrendMAShift, TrendMAMethod, PRICE_CLOSE);
   if(emaHandle == INVALID_HANDLE)
     {
      Print("خطا در ساخت EMA handle: ", GetLastError());
      return -1;
     }

   double ema[1], close[1];
   if(CopyBuffer(emaHandle, 0, 0, 1, ema) != 1)
     {
      Print("خطا در خواندن بافر EMA");
      IndicatorRelease(emaHandle);
      return -1;
     }
   if(CopyClose(_Symbol, 0, 0, 1, close) != 1)
     {
      Print("خطا در خواندن قیمت بسته شدن");
      IndicatorRelease(emaHandle);
      return -1;
     }

   IndicatorRelease(emaHandle);

   // تصمیم‌گیری
   if(close[0] > ema[0])
      return ORDER_TYPE_BUY;
   else
      return ORDER_TYPE_SELL;
  }

//+------------------------------------------------------------------+
//| باز کردن پوزیشن بازار (Market Order) با احتیاط کامل              |
//+------------------------------------------------------------------+
bool PlaceMarketOrder(ENUM_ORDER_TYPE type, double lot, double sl, double tp, string comment)
  {
   Sleep(30);
   MqlTradeRequest request = {};
   MqlTradeResult  result  = {};
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);

   long stopsLevel  = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freezeLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double minStopDist = (stopsLevel + freezeLevel + MinStopPaddingPips * g_PipSize) * _Point;

   // اصلاح SL/TP برای رعایت حداقل فاصله
   if(type == ORDER_TYPE_BUY)
     {
      if(sl > 0 && (price - sl) < minStopDist) sl = price - minStopDist;
      if(tp > 0 && (tp - price) < minStopDist) tp = price + minStopDist;
     }
   else
     {
      if(sl > 0 && (sl - price) < minStopDist) sl = price + minStopDist;
      if(tp > 0 && (price - tp) < minStopDist) tp = price - minStopDist;
     }

   // تلاش اول: با SL/TP
   request.action    = TRADE_ACTION_DEAL;
   request.symbol    = _Symbol;
   request.volume    = lot;
   request.price     = NormalizeDouble(price, digits);
   request.type      = type;
   request.sl        = (sl > 0) ? NormalizeDouble(sl, digits) : 0;
   request.tp        = (tp > 0) ? NormalizeDouble(tp, digits) : 0;
   request.magic     = MagicNumber;
   request.comment   = comment;
   request.type_filling = ORDER_FILLING_FOK;
   request.deviation    = 10;

   if(OrderSend(request, result))
     {
      Print("پوزیشن ", comment, " (Ticket ", result.order, ") با موفقیت باز شد. ",
            "Price=", price, " Lot=", lot, " SL=", sl, " TP=", tp);
      return true;
     }
   else if(result.retcode == 10030 || result.retcode == 4756) // Invalid stops
     {
      Print("خطای استاپ (", result.retcode, "). تلاش بدون SL/TP...");
      // تلاش دوم: بدون استاپ
      request.sl = 0;
      request.tp = 0;
      if(OrderSend(request, result))
        {
         Print("پوزیشن ", comment, " (Ticket ", result.order, ") بدون استاپ باز شد. حالا استاپ‌ها را اضافه می‌کنیم.");
         if(sl > 0 || tp > 0)
           {
            // کمی صبر می‌کنیم
            Sleep(100);
            if(PositionSelectByTicket(result.order))
              {
               if(!GridTrade.PositionModify(result.order, sl, tp))
                  Print("اخطار: نتوانستیم SL/TP را اضافه کنیم. مجدداً تلاش می‌کنیم...");
               else
                  Print("SL/TP با موفقیت اضافه شد.");
              }
           }
         return true;
        }
     }

   // اگر هر دو روش شکست خورد
   Print("Market Order error: ", GetLastError(),
         " | Volume: ", lot, " Price: ", price,
         " SL: ", sl, " TP: ", tp,
         " | retcode=", result.retcode,
         " | STOPS_LEVEL=", stopsLevel, " FreezeLevel=", freezeLevel);
   return false;
  }

//+------------------------------------------------------------------+
//| قرار دادن شبکه سفارشات معلق (Buy/Sell Stop) با فاصله ثابت       |
//+------------------------------------------------------------------+
void PlaceGrid()
  {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   long stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist = (stopsLevel + 2) * _Point;

   // ---- Buy Stops (بالای Ask) ----
   double basePrice = ask;
   for(int i = 1; i <= GridLevels; i++)
     {
      double entry = basePrice + i * GridPipStep * g_PipSize * _Point;
      // اطمینان از فاصله کافی
      if(entry - ask < minDist)
         entry = ask + minDist;

      double sl = (SL_Dollar > 0) ? CalculatePriceLevel(entry, SL_Dollar, DefaultLot, false) : 0;
      double tp = (TP_Dollar > 0) ? CalculatePriceLevel(entry, TP_Dollar, DefaultLot, true) : 0;

      PlacePendingOrder(ORDER_TYPE_BUY_STOP, DefaultLot, entry, sl, tp, "BuyStop_" + IntegerToString(i));
     }

   // ---- Sell Stops (پایین Bid) ----
   basePrice = bid;
   for(int i = 1; i <= GridLevels; i++)
     {
      double entry = basePrice - i * GridPipStep * g_PipSize * _Point;
      if(bid - entry < minDist)
         entry = bid - minDist;

      double sl = (SL_Dollar > 0) ? CalculatePriceLevel(entry, SL_Dollar, DefaultLot, true) : 0;
      double tp = (TP_Dollar > 0) ? CalculatePriceLevel(entry, TP_Dollar, DefaultLot, false) : 0;

      PlacePendingOrder(ORDER_TYPE_SELL_STOP, DefaultLot, entry, sl, tp, "SellStop_" + IntegerToString(i));
     }

   Print("شبکه سفارشات معلق (", GridLevels, " خرید و ", GridLevels, " فروش) با موفقیت قرار داده شد.");
  }

//+------------------------------------------------------------------+
//| ارسال سفارش معلق (Buy Stop / Sell Stop)                         |
//+------------------------------------------------------------------+
bool PlacePendingOrder(ENUM_ORDER_TYPE type, double lot, double entry,
                       double sl, double tp, string comment)
  {
   Sleep(30);
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
   request.type_filling = ORDER_FILLING_RETURN;   // نسخه‌ای که کار می‌کند
   request.type_time    = ORDER_TIME_GTC;
   request.deviation    = 0;

   if(!OrderSend(request, result))
     {
      Print("OrderSend error: ", GetLastError(),
            " | Volume: ", lot, " Entry: ", entry,
            " SL: ", sl, " TP: ", tp,
            " | retcode=", result.retcode);
      return false;
     }

   Print("سفارش ", comment, " (Ticket ", result.order, ") با موفقیت ثبت شد. ",
         "Entry=", entry, " Lot=", lot, " SL=", sl, " TP=", tp);
   return true;
  }

//+------------------------------------------------------------------+
//| محاسبه سطح قیمت SL/TP از دلار                                    |
//+------------------------------------------------------------------+
double CalculatePriceLevel(double entryPrice, double dollarAmount, double lot, bool isTP)
  {
   if(dollarAmount <= 0 || lot <= 0) return 0;

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double pipValue  = lot * tickValue * g_PipSize;  // ارزش یک پیپ
   if(pipValue == 0) return 0;

   double pipDistance = dollarAmount / pipValue;
   double priceOffset = pipDistance * g_PipSize * _Point;

   double level = isTP ? entryPrice + priceOffset : entryPrice - priceOffset;

   long stopsLevel  = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freezeLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double minDist = (stopsLevel + freezeLevel + 5 * g_PipSize) * _Point;

   if(isTP && (level - entryPrice) < minDist)
      level = entryPrice + minDist;
   else if(!isTP && (entryPrice - level) < minDist)
      level = entryPrice - minDist;

   return NormalizeDouble(level, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
  }

//+------------------------------------------------------------------+
//| بررسی سود/زیان کل و بستن همه                                    |
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

   if(posCount > 0)
     {
      if(totalProfit >= TotalProfitTarget)
        {
         Print("رسیدن به سود کل ", TotalProfitTarget, " دلار. بستن همه.");
         CloseAll();
         tradingDone = true;
         isTradingActive = false;
        }
      else if(totalProfit <= TotalStopLoss)
        {
         Print("رسیدن به ضرر کل ", TotalStopLoss, " دلار. بستن همه.");
         CloseAll();
         tradingDone = true;
         isTradingActive = false;
        }
     }
  }

//+------------------------------------------------------------------+
//| بستن همه پوزیشن‌ها و حذف سفارشات معلق                            |
//+------------------------------------------------------------------+
void CloseAll()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         if(!GridTrade.PositionClose(ticket))
            Print("خطا در بستن پوزیشن ", ticket);
     }

   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(OrderSelect(ticket) && OrderGetInteger(ORDER_MAGIC) == MagicNumber)
         if(!GridTrade.OrderDelete(ticket))
            Print("خطا در حذف سفارش ", ticket);
     }

   Print("تمام پوزیشن‌ها و سفارشات بسته شدند.");
  }
//+------------------------------------------------------------------+
