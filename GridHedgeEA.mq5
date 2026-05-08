//+------------------------------------------------------------------+
//|                                GridHedge_Ultimate.mq5             |
//|   سفارش اولیه بر اساس روند + شبکه پیپ + مدیریت پویا + دکمه دستی   |
//+------------------------------------------------------------------+
#property copyright "Hamed Movasaqpoor"
#property link      "hamed.movasaqpoor@gmail.com"
#property version   "2.50"

#include <Trade\Trade.mqh>

//------------------------- INPUT PARAMETERS -------------------------
input group "=== تنظیمات کلی ==="
input bool     UseManualStart        = false;     // فعال کردن دکمه دستی (در غیر این صورت خودکار)
input bool     EnableTrading         = true;      // فعال‌سازی اولیه (در حالت خودکار)
input bool     ResetGridOnStart      = true;      // حذف سفارشات قبلی و شروع دوباره
input int      MagicNumber           = 202701;    // شماره جادویی
input double   TotalProfitTarget     = 10.0;      // سود کل (دلار) - بستن همه
input double   TotalStopLoss         = -50.0;     // ضرر کل (عدد منفی)

input group "=== تشخیص روند (پوزیشن اول) ==="
input bool     UseManualDirection   = false;      // انتخاب دستی جهت؟
input int      DirectionChoice      = 0;          // 0 = خرید, 1 = فروش (در صورت دستی)
input int      TrendMAPeriod        = 20;         // دوره EMA
input int      TrendMAShift         = 0;
input ENUM_MA_METHOD TrendMAMethod  = MODE_EMA;

input group "=== شبکه سفارشات معلق ==="
input int      GridLevels           = 5;          // تعداد اولیه Buy/Sell Stop
input double   GridPipStep          = 5.0;        // فاصله پله‌ها (پیپ)

input group "=== مدیریت سرمایه و ریسک ==="
input double   DefaultLot           = 0.01;       // حجم ثابت
input double   SL_Pips              = 20.0;       // حد ضرر (پیپ)
input double   TP_Pips              = 10.0;       // حد سود (پیپ)

//------------------------- GLOBAL VARIABLES -------------------------
CTrade GridTrade;
int    g_PipSize;
bool   isTradingActive = false;
bool   tradingDone     = false;

// متغیرهای تعدیل پویا
datetime lastCheckTime        = 0;
int      closedBuyProfitCount  = 0;
int      closedSellProfitCount = 0;

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_PipSize = Getg_PipSize();

   tradingDone = false;

   if(UseManualStart)
     {
      isTradingActive = false;                // دکمه فعال می‌کند
      CreateStartButton();
      Print("منتظر کلیک روی دکمه «شروع شبکه» باشید...");
      return(INIT_SUCCEEDED);
     }

   // حالت خودکار
   isTradingActive = EnableTrading;
   if(!isTradingActive)
     {
      Print("EnableTrading = false؛ اجرا نمی‌شود.");
      return(INIT_SUCCEEDED);
     }

   if(ResetGridOnStart)
      DeleteAllOrdersAndPositions();

   lastCheckTime = TimeCurrent();
   ExecuteStrategy();
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Deinitialization (پاک‌کردن دکمه)                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(UseManualStart)
      ObjectDelete(0, "BtnStartGrid");
  }

//+------------------------------------------------------------------+
//| Tick function                                                    |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(!isTradingActive || tradingDone)
      return;

   CheckClosedProfits();          // تعدیل پویا
   CheckTotalProfitLoss();        // بستن کامل
  }

//+------------------------------------------------------------------+
//| رویدادهای نمودار (کلیک روی دکمه)                                 |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id == CHARTEVENT_OBJECT_CLICK && sparam == "BtnStartGrid")
     {
      StartGridByButton();
     }
  }

//+------------------------------------------------------------------+
//| ایجاد دکمه گرافیکی روی نمودار                                    |
//+------------------------------------------------------------------+
void CreateStartButton()
  {
   string name = "BtnStartGrid";
   if(ObjectFind(0, name) >= 0)
      ObjectDelete(0, name);

   ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, 30);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, 120);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, 30);
   ObjectSetString(0, name, OBJPROP_TEXT, "شروع شبکه");
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clrSeaGreen);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, clrBlack);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 10);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 0);
  }

//+------------------------------------------------------------------+
//| واکنش به کلیک دکمه: اگر شبکه‌ای نبود، اجرا کند                    |
//+------------------------------------------------------------------+
void StartGridByButton()
  {
   // بررسی وجود هرگونه پوزیشن یا سفارش معلق با MagicNumber
   if(AnyGridExists())
     {
      Print("شبکه در حال حاضر فعال است. ابتدا آن را ببندید.");
      return;
     }

   Print("ایجاد شبکه جدید با دکمه...");
   isTradingActive = true;
   tradingDone     = false;
   lastCheckTime   = TimeCurrent();
   ExecuteStrategy();
  }

//+------------------------------------------------------------------+
//| بررسی وجود پوزیشن یا سفارش معلق                                  |
//+------------------------------------------------------------------+
bool AnyGridExists()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber)
            return true;
     }
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(OrderSelect(ticket))
         if(OrderGetInteger(ORDER_MAGIC) == MagicNumber)
            return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| تشخیص خودکار PipSize                                             |
//+------------------------------------------------------------------+
int Getg_PipSize()
  {
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   switch(digits)
     {
      case 2: case 3: return 10;  // طلا و نمادهای ۲/۳ رقمی
      case 4:         return 1;
      case 5: default: return 10;
     }
  }

//+------------------------------------------------------------------+
//| اجرای استراتژی: Limit اولیه + شبکه معلق                         |
//+------------------------------------------------------------------+
void ExecuteStrategy()
  {
   int direction = -1;
   if(UseManualDirection)
     {
      direction = (DirectionChoice == 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      Print("جهت دستی: ", direction == ORDER_TYPE_BUY ? "خرید" : "فروش");
     }
   else
     {
      direction = DetectTrendFromEMA();
      if(direction == -1) return;
      Print("جهت EMA(", TrendMAPeriod, "): ", direction == ORDER_TYPE_BUY ? "خرید" : "فروش");
     }

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double slPrice = 0, tpPrice = 0;

   if(direction == ORDER_TYPE_BUY)
     {
      slPrice = (SL_Pips > 0) ? PipToPrice(ask, SL_Pips, true, true) : 0;
      tpPrice = (TP_Pips > 0) ? PipToPrice(ask, TP_Pips, false, true) : 0;
      if(!PlaceInitialLimit(ORDER_TYPE_BUY, DefaultLot, slPrice, tpPrice, "Initial Buy"))
         Print("خطا در Limit خرید");
     }
   else
     {
      slPrice = (SL_Pips > 0) ? PipToPrice(bid, SL_Pips, true, false) : 0;
      tpPrice = (TP_Pips > 0) ? PipToPrice(bid, TP_Pips, false, false) : 0;
      if(!PlaceInitialLimit(ORDER_TYPE_SELL, DefaultLot, slPrice, tpPrice, "Initial Sell"))
         Print("خطا در Limit فروش");
     }

   PlaceGrid();
  }

//+------------------------------------------------------------------+
//| تشخیص روند با EMA                                                |
//+------------------------------------------------------------------+
int DetectTrendFromEMA()
  {
   int emaHandle = iMA(_Symbol, 0, TrendMAPeriod, TrendMAShift, TrendMAMethod, PRICE_CLOSE);
   if(emaHandle == INVALID_HANDLE) { Print("خطا در EMA"); return -1; }

   double ema[1], close[1];
   if(CopyBuffer(emaHandle, 0, 0, 1, ema) != 1 || CopyClose(_Symbol, 0, 0, 1, close) != 1)
     {
      Print("خطا در کپی داده");
      IndicatorRelease(emaHandle);
      return -1;
     }
   IndicatorRelease(emaHandle);
   return (close[0] > ema[0]) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
  }

//+------------------------------------------------------------------+
//| Limit Order اولیه با فاصله‌ی ۰.۵ پیپ                              |
//+------------------------------------------------------------------+
bool PlaceInitialLimit(ENUM_ORDER_TYPE type, double lot, double sl, double tp, string comment)
  {
   Sleep(30);
   MqlTradeRequest request = {};
   MqlTradeResult  result  = {};
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   double price;
   if(type == ORDER_TYPE_BUY)
      price = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - 0.5 * g_PipSize * _Point;
   else
      price = SymbolInfoDouble(_Symbol, SYMBOL_BID) + 0.5 * g_PipSize * _Point;

   long stopsLevel  = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freezeLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double minStopDist = (stopsLevel + freezeLevel + 10 * g_PipSize) * _Point;

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

   request.action    = TRADE_ACTION_PENDING;
   request.symbol    = _Symbol;
   request.volume    = lot;
   request.price     = NormalizeDouble(price, digits);
   request.type      = (type == ORDER_TYPE_BUY) ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT;
   request.sl        = (sl > 0) ? NormalizeDouble(sl, digits) : 0;
   request.tp        = (tp > 0) ? NormalizeDouble(tp, digits) : 0;
   request.magic     = MagicNumber;
   request.comment   = comment;
   request.type_filling = ORDER_FILLING_RETURN;
   request.type_time    = ORDER_TIME_GTC;
   request.deviation    = 0;

   if(!OrderSend(request, result))
     {
      Print("Limit Order error: ", GetLastError(), " retcode=", result.retcode);
      return false;
     }
   Print("Limit ", comment, " (Ticket ", result.order, ") ثبت شد. Price=", price);
   return true;
  }

//+------------------------------------------------------------------+
//| شبکه اولیه Buy/Sell Stop                                        |
//+------------------------------------------------------------------+
void PlaceGrid()
  {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   long stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist = (stopsLevel + 2) * _Point;

   double baseBuy = ask;
   for(int i = 1; i <= GridLevels; i++)
     {
      double entry = baseBuy + i * GridPipStep * g_PipSize * _Point;
      if(entry - ask < minDist) entry = ask + minDist;
      double sl = (SL_Pips > 0) ? PipToPrice(entry, SL_Pips, true, true) : 0;
      double tp = (TP_Pips > 0) ? PipToPrice(entry, TP_Pips, false, true) : 0;
      PlacePendingOrder(ORDER_TYPE_BUY_STOP, DefaultLot, entry, sl, tp, "BuyStop_"+IntegerToString(i));
     }

   double baseSell = bid;
   for(int i = 1; i <= GridLevels; i++)
     {
      double entry = baseSell - i * GridPipStep * g_PipSize * _Point;
      if(bid - entry < minDist) entry = bid - minDist;
      double sl = (SL_Pips > 0) ? PipToPrice(entry, SL_Pips, true, false) : 0;
      double tp = (TP_Pips > 0) ? PipToPrice(entry, TP_Pips, false, false) : 0;
      PlacePendingOrder(ORDER_TYPE_SELL_STOP, DefaultLot, entry, sl, tp, "SellStop_"+IntegerToString(i));
     }
   Print("شبکه اولیه قرار داده شد.");
  }

//+------------------------------------------------------------------+
//| ثبت سفارش معلق                                                   |
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
   request.type_filling = ORDER_FILLING_RETURN;
   request.type_time    = ORDER_TIME_GTC;
   request.deviation    = 0;

   if(!OrderSend(request, result))
     {
      Print("OrderSend error: ", GetLastError(), " retcode=", result.retcode);
      return false;
     }
   Print("سفارش ", comment, " (Ticket ", result.order, ") ثبت شد. Entry=", entry);
   return true;
  }

//+------------------------------------------------------------------+
//| تبدیل فاصله پیپ به قیمت (SL/TP)                                  |
//+------------------------------------------------------------------+
double PipToPrice(double entryPrice, double pips, bool isSL, bool isBuy)
  {
   if(pips <= 0) return 0;
   double offset = pips * g_PipSize * _Point;
   if(isBuy)
      return isSL ? entryPrice - offset : entryPrice + offset;  // Buy: SL پایین, TP بالا
   else
      return isSL ? entryPrice + offset : entryPrice - offset;  // Sell: SL بالا, TP پایین
  }

//+------------------------------------------------------------------+
//| حذف سفارشات و بستن پوزیشن‌ها                                     |
//+------------------------------------------------------------------+
void DeleteAllOrdersAndPositions()
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(OrderSelect(ticket) && OrderGetInteger(ORDER_MAGIC) == MagicNumber)
         if(!GridTrade.OrderDelete(ticket))
            Print("خطا در حذف سفارش ", ticket);
     }
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         if(!GridTrade.PositionClose(ticket))
            Print("خطا در بستن پوزیشن ", ticket);
     }
  }

//+------------------------------------------------------------------+
//| بررسی بسته‌شدن پوزیشن‌های سودده و تعدیل پویا                     |
//+------------------------------------------------------------------+
void CheckClosedProfits()
  {
   if(!HistorySelect(lastCheckTime, TimeCurrent())) return;

   int totalDeals = HistoryDealsTotal();
   for(int i = 0; i < totalDeals; i++)
     {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != MagicNumber) continue;
      if(HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
      if(HistoryDealGetDouble(ticket, DEAL_PROFIT) <= 0) continue;

      long dealType = HistoryDealGetInteger(ticket, DEAL_TYPE);
      if(dealType == DEAL_TYPE_BUY)
         closedBuyProfitCount++;
      else if(dealType == DEAL_TYPE_SELL)
         closedSellProfitCount++;
     }

   lastCheckTime = TimeCurrent() + 1;

   while(closedBuyProfitCount >= 2) { Print("تعدیل خرید"); BuyAdjustment(); closedBuyProfitCount -= 2; }
   while(closedSellProfitCount >= 2) { Print("تعدیل فروش"); SellAdjustment(); closedSellProfitCount -= 2; }
  }

void BuyAdjustment()
  {
   double maxBuyPrice = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(OrderSelect(ticket) && OrderGetInteger(ORDER_MAGIC)==MagicNumber && OrderGetInteger(ORDER_TYPE)==ORDER_TYPE_BUY_STOP)
        {
         double price = OrderGetDouble(ORDER_PRICE_OPEN);
         if(price > maxBuyPrice) maxBuyPrice = price;
        }
     }
   if(maxBuyPrice == 0) maxBuyPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   double newPrice = maxBuyPrice + GridPipStep * g_PipSize * _Point;
   for(int i = 0; i < 2; i++)
     {
      double sl = (SL_Pips > 0) ? PipToPrice(newPrice, SL_Pips, true, true) : 0;
      double tp = (TP_Pips > 0) ? PipToPrice(newPrice, TP_Pips, false, true) : 0;
      if(PlacePendingOrder(ORDER_TYPE_BUY_STOP, DefaultLot, newPrice, sl, tp, "Buy_Dyn"))
         newPrice += GridPipStep * g_PipSize * _Point;
      else break;
     }
   DeleteClosestSellStops(2);
  }

void SellAdjustment()
  {
   double minSellPrice = DBL_MAX;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(OrderSelect(ticket) && OrderGetInteger(ORDER_MAGIC)==MagicNumber && OrderGetInteger(ORDER_TYPE)==ORDER_TYPE_SELL_STOP)
        {
         double price = OrderGetDouble(ORDER_PRICE_OPEN);
         if(price < minSellPrice) minSellPrice = price;
        }
     }
   if(minSellPrice == DBL_MAX) minSellPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double newPrice = minSellPrice - GridPipStep * g_PipSize * _Point;
   for(int i = 0; i < 2; i++)
     {
      double sl = (SL_Pips > 0) ? PipToPrice(newPrice, SL_Pips, true, false) : 0;
      double tp = (TP_Pips > 0) ? PipToPrice(newPrice, TP_Pips, false, false) : 0;
      if(PlacePendingOrder(ORDER_TYPE_SELL_STOP, DefaultLot, newPrice, sl, tp, "Sell_Dyn"))
         newPrice -= GridPipStep * g_PipSize * _Point;
      else break;
     }
   DeleteClosestBuyStops(2);
  }

void DeleteClosestSellStops(int count)
  {
   ulong tickets[]; double prices[];
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(OrderSelect(ticket) && OrderGetInteger(ORDER_MAGIC)==MagicNumber && OrderGetInteger(ORDER_TYPE)==ORDER_TYPE_SELL_STOP)
        {
         int s = ArraySize(tickets); ArrayResize(tickets, s+1); ArrayResize(prices, s+1);
         tickets[s] = ticket; prices[s] = OrderGetDouble(ORDER_PRICE_OPEN);
        }
     }
   // مرتب‌سازی نزولی (بزرگترین نزدیک‌ترین)
   for(int i = ArraySize(prices)-1; i>0; i--) for(int j=0; j<i; j++)
        if(prices[j] < prices[j+1]) { double t=prices[j]; prices[j]=prices[j+1]; prices[j+1]=t; ulong u=tickets[j]; tickets[j]=tickets[j+1]; tickets[j+1]=u; }
   for(int i = 0; i < count && i < ArraySize(tickets); i++) GridTrade.OrderDelete(tickets[i]);
  }

void DeleteClosestBuyStops(int count)
  {
   ulong tickets[]; double prices[];
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(OrderSelect(ticket) && OrderGetInteger(ORDER_MAGIC)==MagicNumber && OrderGetInteger(ORDER_TYPE)==ORDER_TYPE_BUY_STOP)
        {
         int s = ArraySize(tickets); ArrayResize(tickets, s+1); ArrayResize(prices, s+1);
         tickets[s] = ticket; prices[s] = OrderGetDouble(ORDER_PRICE_OPEN);
        }
     }
   // مرتب‌سازی صعودی (کوچکترین نزدیک‌ترین)
   for(int i = ArraySize(prices)-1; i>0; i--) for(int j=0; j<i; j++)
        if(prices[j] > prices[j+1]) { double t=prices[j]; prices[j]=prices[j+1]; prices[j+1]=t; ulong u=tickets[j]; tickets[j]=tickets[j+1]; tickets[j+1]=u; }
   for(int i = 0; i < count && i < ArraySize(tickets); i++) GridTrade.OrderDelete(tickets[i]);
  }

//+------------------------------------------------------------------+
//| بررسی سود/زیان کل و بستن همه                                    |
//+------------------------------------------------------------------+
void CheckTotalProfitLoss()
  {
   double totalProfit = 0.0; int posCount = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
        { totalProfit += PositionGetDouble(POSITION_PROFIT); posCount++; }
     }
   if(posCount > 0)
     {
      if(totalProfit >= TotalProfitTarget) { Print("StopTarget reached"); CloseAll(); tradingDone = true; isTradingActive = false; }
      else if(totalProfit <= TotalStopLoss) { Print("StopLoss reached"); CloseAll(); tradingDone = true; isTradingActive = false; }
     }
  }

//+------------------------------------------------------------------+
//| بستن همه پوزیشن‌ها و سفارشات                                    |
//+------------------------------------------------------------------+
void CloseAll()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         GridTrade.PositionClose(ticket);
     }
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(OrderSelect(ticket) && OrderGetInteger(ORDER_MAGIC) == MagicNumber)
         GridTrade.OrderDelete(ticket);
     }
   Print("تمام پوزیشن‌ها و سفارشات بسته شدند.");
  }
//+------------------------------------------------------------------+