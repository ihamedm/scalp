//+------------------------------------------------------------------+
//|                                GridHedge_Ultimate_v4.mq5         |
//|   شبکه گرید با محاسبات بر اساس Point (سازگار با همه نمادها)     |
//|   نسخه ۴.۰ - جایگزینی پیپ با Point + مدیریت ریسک درصدی         |
//+------------------------------------------------------------------+
#property copyright "Hamed Movasaqpoor"
#property link      "hamed.movasaqpoor@gmail.com"
#property version   "4.00"

#include <Trade\Trade.mqh>

#define DASHBOARD_LABEL "DashboardLabel"

//===================================================================
//  راهنمای تنظیم اعداد بر حسب نماد
//
//  _Point برای هر نماد:
//    EURUSD / GBPUSD  → _Point = 0.00001  → 1 پیپ = 10 Point
//    USDJPY / EURJPY  → _Point = 0.001    → 1 پیپ = 10 Point
//    XAUUSD (طلا)     → _Point = 0.01     → 1 پیپ = 10 Point
//    BTCUSD (بیتکوین) → _Point = 0.01     → 1 پیپ = 10 Point
//
//  مثال طلا (_Point=0.01):
//    GridStep_Points = 500   → فاصله پله‌ها = 500 × 0.01 = 5.00 دلار
//    SL_Points       = 2000  → حد ضرر       = 2000 × 0.01 = 20.00 دلار
//    TP_Points       = 1000  → حد سود        = 1000 × 0.01 = 10.00 دلار
//
//  مثال بیتکوین (_Point=0.01):
//    GridStep_Points = 50000 → فاصله پله‌ها = 50000 × 0.01 = 500 دلار
//    SL_Points       = 100000→ حد ضرر       = 100000 × 0.01 = 1000 دلار
//    TP_Points       = 50000 → حد سود        = 50000 × 0.01 = 500 دلار
//
//  مثال EURUSD (_Point=0.00001):
//    GridStep_Points = 500   → فاصله پله‌ها = 500 × 0.00001 = 0.00500 = 50 پیپ
//    SL_Points       = 200   → حد ضرر       = 200 × 0.00001 = 20 پیپ
//    TP_Points       = 100   → حد سود        = 100 × 0.00001 = 10 پیپ
//===================================================================

//------------------------- INPUT PARAMETERS -------------------------
input group "=== تنظیمات کلی ==="
input bool   UseManualStart    = true;     // نمایش دکمه شروع دستی
input bool   ShowCloseButtons  = true;     // نمایش دکمه‌های بستن سریع
input bool   EnableTrading     = false;    // فعال‌سازی اولیه (حالت خودکار)
input bool   ResetGridOnStart  = false;    // حذف سفارشات قبلی و شروع دوباره
input int    MagicNumber       = 202701;   // شماره جادویی
input double TotalProfitTarget = 10.0;    // هدف سود کل (دلار)
input double TotalStopLoss     = -50.0;   // حد ضرر کل (عدد منفی، دلار)

input group "=== تشخیص روند ==="
input bool             UseManualDirection  = false;   // انتخاب دستی جهت؟
input int              DirectionChoice     = 0;       // 0=خرید  1=فروش
input int              TrendMAPeriod       = 20;      // دوره EMA
input int              TrendMAShift        = 0;
input ENUM_MA_METHOD   TrendMAMethod       = MODE_EMA;
input int              TrendConfirmCandles = 3;       // تعداد کندل‌های تأیید روند

input group "=== شبکه سفارشات (بر حسب Point) ==="
input int    GridLevels        = 5;        // تعداد پله‌های اولیه Buy/Sell Stop
input double GridStep_Points   = 500.0;   // فاصله بین پله‌ها (Point)
//  طلا:    500  → 5.00$  |  BTC: 50000 → 500$  |  EUR: 500 → 50 pip

input group "=== مدیریت ریسک ==="
input bool   UseRiskPercent    = true;     // مدیریت ریسک درصدی؟ (پیشنهادی)
input double RiskPercent       = 1.0;     // درصد ریسک از موجودی برای هر پوزیشن
input double FixedLot          = 0.01;    // حجم ثابت (فقط وقتی UseRiskPercent=false)
input double SL_Points         = 0;  // حد ضرر (Point)
input double TP_Points         = 200.0;  // حد سود (Point)
//  طلا:  SL=2000 → 20$  TP=1000 → 10$
//  BTC:  SL=100000 → 1000$  TP=50000 → 500$
//  EUR:  SL=200 → 20pip  TP=100 → 10pip

input group "=== Trailing Stop (بر حسب Point) ==="
input bool   UseTrailingStop        = true;    // فعال‌سازی Trailing Stop
input double TrailingStop_Points    = 800.0;   // فاصله Trailing از قیمت (Point)
input double TrailingStep_Points    = 100.0;   // حداقل گام جابجایی SL (Point)
input double TrailingActivate_Points= 500.0;   // سود لازم برای فعال‌شدن (Point)
//  طلا:  Trailing=800 → 8$  Step=100 → 1$  Activate=500 → 5$

input group "=== گسترش شبکه ==="
input int    InitialMaxBuyExpansions  = 4;     // حداکثر گسترش خرید
input int    InitialMaxSellExpansions = 4;     // حداکثر گسترش فروش

//------------------------- GLOBAL VARIABLES -------------------------
CTrade GridTrade;

string g_GridID            = "";
bool   isTradingActive     = false;
bool   tradingDone         = false;

double lastBuyExpansionPrice  = 0;
double lastSellExpansionPrice = 0;
int    buyExpansionCount      = 0;
int    sellExpansionCount     = 0;
int    g_MaxBuyExpansions;
int    g_MaxSellExpansions;

// مقادیر محاسبه‌شده در زمان اجرا (برای نمایش در داشبورد)
double g_ActualGridStep  = 0;
double g_ActualSL        = 0;
double g_ActualTP        = 0;
double g_CurrentLot      = 0;

//+------------------------------------------------------------------+
//| چاپ اطلاعات تشخیصی نماد                                        |
//+------------------------------------------------------------------+
void PrintSymbolInfo()
  {
   double pointVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE) /
                     SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE) * _Point;

   PrintFormat("══ اطلاعات نماد: %s ══", _Symbol);
   PrintFormat("  _Point       = %.8f", _Point);
   PrintFormat("  Digits       = %d",   (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
   PrintFormat("  TickSize     = %.8f", SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE));
   PrintFormat("  TickValue    = %.5f", SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE));
   PrintFormat("  ارزش هر Point برای ۱ لات = %.5f $", pointVal);
   PrintFormat("  GridStep     = %.5f $ (%.0f Point)", GridStep_Points * _Point, GridStep_Points);
   PrintFormat("  SL فاصله    = %.5f $ (%.0f Point)", SL_Points * _Point, SL_Points);
   PrintFormat("  TP فاصله    = %.5f $ (%.0f Point)", TP_Points * _Point, TP_Points);
  }

//+------------------------------------------------------------------+
//| محاسبه حجم لات بر اساس درصد ریسک                               |
//+------------------------------------------------------------------+
double CalcLot(double slPoints)
  {
   if(!UseRiskPercent || slPoints <= 0)
      return FixedLot;

   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * RiskPercent / 100.0;

   double tickValue  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   // ارزش دلاری هر Point برای ۱ لات استاندارد
   double pointValue = (tickSize > 0) ? (tickValue / tickSize * _Point) : 0;
   if(pointValue <= 0)
     {
      Print("⚠️ خطا در محاسبه PointValue. از حجم ثابت استفاده می‌شود.");
      return FixedLot;
     }

   double lot = riskAmount / (slPoints * pointValue);

   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   lot = MathFloor(lot / lotStep) * lotStep;
   lot = MathMax(lot, minLot);
   lot = MathMin(lot, maxLot);

   PrintFormat("  CalcLot: Balance=%.2f | Risk=%.2f$ | SL=%.0fpt | PointVal=%.6f | Lot=%.2f",
               balance, riskAmount, slPoints, pointValue, lot);
   return lot;
  }

//+------------------------------------------------------------------+
//| تبدیل Point به قیمت SL/TP                                       |
//+------------------------------------------------------------------+
double PointToPrice(double basePrice, double points, bool isSL, bool isBuy)
  {
   if(points <= 0) return 0;
   double offset = points * _Point;
   if(isBuy)
      return isSL ? basePrice - offset : basePrice + offset;
   else
      return isSL ? basePrice + offset : basePrice - offset;
  }

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
  {
   tradingDone         = false;
   g_MaxBuyExpansions  = InitialMaxBuyExpansions;
   g_MaxSellExpansions = InitialMaxSellExpansions;
   g_ActualGridStep    = GridStep_Points * _Point;
   g_ActualSL          = SL_Points * _Point;
   g_ActualTP          = TP_Points * _Point;

   PrintSymbolInfo();

   if(ShowCloseButtons) CreateCloseButtons();
   CreateExpansionButtons();

   if(UseManualStart)
     {
      isTradingActive = false;
      CreateStartButton();
      Print("منتظر کلیک روی دکمه «شروع شبکه» باشید...");
      return INIT_SUCCEEDED;
     }

   isTradingActive = EnableTrading;
   if(!isTradingActive)
     {
      Print("EnableTrading = false؛ اجرا نمی‌شود.");
      return INIT_SUCCEEDED;
     }

   if(ResetGridOnStart) DeleteAllOrdersAndPositions();
   ExecuteStrategy();
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectDelete(0, "BtnStartGrid");
   ObjectDelete(0, "BtnCloseProfitable");
   ObjectDelete(0, "BtnCloseAllGrid");
   ObjectsDeleteAll(0, "BtnBuyExp");
   ObjectsDeleteAll(0, "BtnSellExp");
   ObjectDelete(0, "LblBuyExp");
   ObjectDelete(0, "ValBuyExp");
   ObjectDelete(0, "LblSellExp");
   ObjectDelete(0, "ValSellExp");
   ObjectDelete(0, DASHBOARD_LABEL);
   Comment("");
  }

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(!isTradingActive || tradingDone) return;

   if(UseTrailingStop) ManageTrailing();
   CheckGridExpansion();
   CheckTotalProfitLoss();
   ShowDashboard();
  }

//+------------------------------------------------------------------+
//| OnChartEvent                                                     |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id != CHARTEVENT_OBJECT_CLICK) return;

   if(sparam == "BtnStartGrid")        { StartGridByButton();   return; }
   if(sparam == "BtnCloseProfitable")  { CloseProfitableGrid(); return; }
   if(sparam == "BtnCloseAllGrid")     { CloseAllGrid();        return; }

   if(sparam == "BtnBuyExpPlus")
     {
      g_MaxBuyExpansions = MathMin(g_MaxBuyExpansions + 1, 10);
      ObjectSetString(0, "ValBuyExp", OBJPROP_TEXT, IntegerToString(g_MaxBuyExpansions));
      Print("MaxBuyExpansions → ", g_MaxBuyExpansions);
      return;
     }
   if(sparam == "BtnBuyExpMinus")
     {
      g_MaxBuyExpansions = MathMax(g_MaxBuyExpansions - 1, 0);
      ObjectSetString(0, "ValBuyExp", OBJPROP_TEXT, IntegerToString(g_MaxBuyExpansions));
      Print("MaxBuyExpansions → ", g_MaxBuyExpansions);
      return;
     }
   if(sparam == "BtnSellExpPlus")
     {
      g_MaxSellExpansions = MathMin(g_MaxSellExpansions + 1, 10);
      ObjectSetString(0, "ValSellExp", OBJPROP_TEXT, IntegerToString(g_MaxSellExpansions));
      Print("MaxSellExpansions → ", g_MaxSellExpansions);
      return;
     }
   if(sparam == "BtnSellExpMinus")
     {
      g_MaxSellExpansions = MathMax(g_MaxSellExpansions - 1, 0);
      ObjectSetString(0, "ValSellExp", OBJPROP_TEXT, IntegerToString(g_MaxSellExpansions));
      Print("MaxSellExpansions → ", g_MaxSellExpansions);
      return;
     }
  }

//+------------------------------------------------------------------+
//| شروع شبکه با دکمه                                               |
//+------------------------------------------------------------------+
void StartGridByButton()
  {
   if(AnyGridExists())
     {
      Print("⚠️ شبکه در حال حاضر فعال است. ابتدا آن را ببندید.");
      return;
     }
   Print("▶ ایجاد شبکه جدید...");
   isTradingActive = true;
   tradingDone     = false;
   ExecuteStrategy();
  }

//+------------------------------------------------------------------+
//| بررسی وجود پوزیشن یا سفارش                                     |
//+------------------------------------------------------------------+
bool AnyGridExists()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(PositionSelectByTicket(t) &&
         PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
         PositionGetString(POSITION_SYMBOL) == _Symbol)
         return true;
     }
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong t = OrderGetTicket(i);
      if(OrderSelect(t) &&
         OrderGetInteger(ORDER_MAGIC) == MagicNumber &&
         OrderGetString(ORDER_SYMBOL) == _Symbol)
         return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| اجرای استراتژی اصلی                                             |
//+------------------------------------------------------------------+
void ExecuteStrategy()
  {
   g_GridID = TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES|TIME_SECONDS);

   int direction = -1;
   if(UseManualDirection)
     {
      direction = (DirectionChoice == 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      Print("جهت دستی: ", direction == ORDER_TYPE_BUY ? "خرید ▲" : "فروش ▼");
     }
   else
     {
      direction = DetectTrendFromEMA();
    
      Print("جهت EMA(", TrendMAPeriod, "): ", direction == ORDER_TYPE_BUY ? "خرید ▲" : "فروش ▼");
     }

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // محاسبه حجم بر اساس SL
   g_CurrentLot = CalcLot(SL_Points);

   if(direction == ORDER_TYPE_BUY)
     {
      double sl = (SL_Points > 0) ? PointToPrice(ask, SL_Points, true,  true) : 0;
      double tp = (TP_Points > 0) ? PointToPrice(ask, TP_Points, false, true) : 0;
      PlaceInitialLimit(ORDER_TYPE_BUY, g_CurrentLot, sl, tp, "Initial Buy");
     }
   else
     {
      double sl = (SL_Points > 0) ? PointToPrice(bid, SL_Points, true,  false) : 0;
      double tp = (TP_Points > 0) ? PointToPrice(bid, TP_Points, false, false) : 0;
      PlaceInitialLimit(ORDER_TYPE_SELL, g_CurrentLot, sl, tp, "Initial Sell");
     }

   PlaceGrid();

   lastBuyExpansionPrice  = ask;
   lastSellExpansionPrice = bid;
   buyExpansionCount      = 0;
   sellExpansionCount     = 0;
  }

//+------------------------------------------------------------------+
//| تشخیص روند - چند کندل + شیب EMA                                |
//+------------------------------------------------------------------+
int DetectTrendFromEMA()
  {
   int needed = MathMax(TrendConfirmCandles, 1) + 1;

   int handle = iMA(_Symbol, 0, TrendMAPeriod, TrendMAShift, TrendMAMethod, PRICE_CLOSE);
   if(handle == INVALID_HANDLE) { Print("خطا در EMA handle"); return -1; }

   double ema[], cls[];
   ArraySetAsSeries(ema, true);
   ArraySetAsSeries(cls, true);

   bool ok = (CopyBuffer(handle, 0, 0, needed, ema) == needed) &&
             (CopyClose(_Symbol, 0, 0, needed, cls)  == needed);
   IndicatorRelease(handle);
   if(!ok) { Print("خطا در کپی داده EMA"); return -1; }

   int confirm   = MathMax(TrendConfirmCandles, 1);
   bool bullish  = true, bearish = true;
   for(int i = 0; i < confirm; i++)
     {
      if(cls[i] <= ema[i]) bullish = false;
      if(cls[i] >= ema[i]) bearish = false;
     }

   bool slopeUp   = ema[0] > ema[confirm];
   bool slopeDown = ema[0] < ema[confirm];

   // اگر شرایط قوی برقرار بود، همان جهت را برگردان
   if(bullish && slopeUp)   return ORDER_TYPE_BUY;
   if(bearish && slopeDown) return ORDER_TYPE_SELL;

   // در غیر این‌صورت (رنج)، با یک قانون ساده تصمیم بگیر:
   if(cls[0] > ema[0])      return ORDER_TYPE_BUY;
   if(cls[0] < ema[0])      return ORDER_TYPE_SELL;

   // اگر برابر بود، جهت پیش‌فرض خرید (می‌توانید تغییر دهید)
   return ORDER_TYPE_BUY;
  }
//+------------------------------------------------------------------+
//| Trailing Stop - بر حسب Point                                    |
//+------------------------------------------------------------------+
void ManageTrailing()
  {
   double trail    = TrailingStop_Points    * _Point;
   double step     = TrailingStep_Points    * _Point;
   double activate = TrailingActivate_Points * _Point;
   int    digits   = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      double sl   = PositionGetDouble(POSITION_SL);
      double tp   = PositionGetDouble(POSITION_TP);
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      long   type = PositionGetInteger(POSITION_TYPE);

      if(type == POSITION_TYPE_BUY)
        {
         double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double profit = bid - open;
         if(profit < activate) continue;

         double newSL = NormalizeDouble(bid - trail, digits);
         if(newSL > sl + step && newSL > open)
            GridTrade.PositionModify(ticket, newSL, tp);
        }
      else if(type == POSITION_TYPE_SELL)
        {
         double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double profit = open - ask;
         if(profit < activate) continue;

         double newSL = NormalizeDouble(ask + trail, digits);
         if((sl == 0 || newSL < sl - step) && newSL < open)
            GridTrade.PositionModify(ticket, newSL, tp);
        }
     }
  }

//+------------------------------------------------------------------+
//| Limit Order اولیه                                                |
//+------------------------------------------------------------------+
bool PlaceInitialLimit(ENUM_ORDER_TYPE type, double lot, double sl, double tp, string comment)
  {
   Sleep(30);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   // ورود کمی داخل‌تر از قیمت بازار (نصف GridStep)
   double halfStep = (GridStep_Points / 2.0) * _Point;
   double price = (type == ORDER_TYPE_BUY)
                  ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) - halfStep
                  : SymbolInfoDouble(_Symbol, SYMBOL_BID) + halfStep;

   // بررسی حداقل فاصله بروکر
   long   stopsLvl   = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long   freezeLvl  = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double minDist    = (stopsLvl + freezeLvl + 2) * _Point;

   if(type == ORDER_TYPE_BUY)
     {
      if(sl > 0 && (price - sl) < minDist) sl = price - minDist;
      if(tp > 0 && (tp - price) < minDist) tp = price + minDist;
     }
   else
     {
      if(sl > 0 && (sl - price) < minDist) sl = price + minDist;
      if(tp > 0 && (price - tp) < minDist) tp = price - minDist;
     }

   MqlTradeRequest req = {};
   MqlTradeResult  res = {};
   req.action       = TRADE_ACTION_PENDING;
   req.symbol       = _Symbol;
   req.volume       = lot;
   req.price        = NormalizeDouble(price, digits);
   req.type         = (type == ORDER_TYPE_BUY) ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT;
   req.sl           = (sl > 0) ? NormalizeDouble(sl, digits) : 0;
   req.tp           = (tp > 0) ? NormalizeDouble(tp, digits) : 0;
   req.magic        = MagicNumber;
   req.comment      = "[" + g_GridID + "] " + comment;
   req.type_filling = ORDER_FILLING_RETURN;
   req.type_time    = ORDER_TIME_GTC;

   if(!OrderSend(req, res))
     {
      PrintFormat("❌ Limit خطا: err=%d retcode=%d", GetLastError(), res.retcode);
      return false;
     }
   PrintFormat("✅ %s | Price=%.5f | SL=%.5f | TP=%.5f | Lot=%.2f",
               comment, price, sl, tp, lot);
   return true;
  }

//+------------------------------------------------------------------+
//| شبکه اولیه Buy/Sell Stop                                        |
//+------------------------------------------------------------------+
void PlaceGrid()
  {
   double ask      = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid      = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   long   stopsLvl = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist  = (stopsLvl + 2) * _Point;
   double step     = GridStep_Points * _Point;

   for(int i = 1; i <= GridLevels; i++)
     {
      double entry = ask + i * step;
      if(entry - ask < minDist) entry = ask + minDist;
      double lot = CalcLot(SL_Points);
      double sl  = (SL_Points > 0) ? PointToPrice(entry, SL_Points, true,  true) : 0;
      double tp  = (TP_Points > 0) ? PointToPrice(entry, TP_Points, false, true) : 0;
      PlacePendingOrder(ORDER_TYPE_BUY_STOP, lot, entry, sl, tp,
                        "BuyStop_" + IntegerToString(i));
     }

   for(int i = 1; i <= GridLevels; i++)
     {
      double entry = bid - i * step;
      if(bid - entry < minDist) entry = bid - minDist;
      double lot = CalcLot(SL_Points);
      double sl  = (SL_Points > 0) ? PointToPrice(entry, SL_Points, true,  false) : 0;
      double tp  = (TP_Points > 0) ? PointToPrice(entry, TP_Points, false, false) : 0;
      PlacePendingOrder(ORDER_TYPE_SELL_STOP, lot, entry, sl, tp,
                        "SellStop_" + IntegerToString(i));
     }
   Print("✅ شبکه اولیه ثبت شد.");
  }

//+------------------------------------------------------------------+
//| ثبت سفارش معلق                                                  |
//+------------------------------------------------------------------+
bool PlacePendingOrder(ENUM_ORDER_TYPE type, double lot, double entry,
                       double sl, double tp, string comment)
  {
   Sleep(30);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   MqlTradeRequest req = {};
   MqlTradeResult  res = {};
   req.action       = TRADE_ACTION_PENDING;
   req.symbol       = _Symbol;
   req.volume       = lot;
   req.price        = NormalizeDouble(entry, digits);
   req.type         = type;
   req.sl           = (sl > 0) ? NormalizeDouble(sl, digits) : 0;
   req.tp           = (tp > 0) ? NormalizeDouble(tp, digits) : 0;
   req.magic        = MagicNumber;
   req.comment      = "[" + g_GridID + "] " + comment;
   req.type_filling = ORDER_FILLING_RETURN;
   req.type_time    = ORDER_TIME_GTC;

   if(!OrderSend(req, res))
     {
      PrintFormat("❌ OrderSend خطا: err=%d retcode=%d comment=%s", GetLastError(), res.retcode, comment);
      return false;
     }
   PrintFormat("✅ %s | Entry=%.5f | SL=%.5f | TP=%.5f | Lot=%.2f",
               comment, entry, sl, tp, lot);
   return true;
  }

//+------------------------------------------------------------------+
//| گسترش شبکه                                                      |
//+------------------------------------------------------------------+
void CheckGridExpansion()
  {
   double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double step = GridStep_Points * _Point;

   if(ask >= lastBuyExpansionPrice + step)
     {
      if(buyExpansionCount < g_MaxBuyExpansions)
        {
         PrintFormat("█ گسترش خرید %d/%d | Ask=%.5f", buyExpansionCount+1, g_MaxBuyExpansions, ask);
         BuyAdjustment();
         buyExpansionCount++;
        }
      lastBuyExpansionPrice += step;
     }

   if(bid <= lastSellExpansionPrice - step)
     {
      if(sellExpansionCount < g_MaxSellExpansions)
        {
         PrintFormat("█ گسترش فروش %d/%d | Bid=%.5f", sellExpansionCount+1, g_MaxSellExpansions, bid);
         SellAdjustment();
         sellExpansionCount++;
        }
      lastSellExpansionPrice -= step;
     }
  }

//+------------------------------------------------------------------+
//| گسترش خرید: پر کردن نزدیک‌ترین شکاف بالای Ask                   |
//+------------------------------------------------------------------+
void BuyAdjustment()
  {
   double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double step = GridStep_Points * _Point;

   // پیدا کردن نزدیک‌ترین Buy Stop موجود بالای Ask
   double nearestBuy = DBL_MAX;
   for(int i = OrdersTotal()-1; i >= 0; i--)
     {
      ulong t = OrderGetTicket(i);
      if(OrderSelect(t) &&
         OrderGetInteger(ORDER_MAGIC) == MagicNumber &&
         OrderGetString(ORDER_SYMBOL) == _Symbol &&
         OrderGetInteger(ORDER_TYPE)  == ORDER_TYPE_BUY_STOP)
        {
         double p = OrderGetDouble(ORDER_PRICE_OPEN);
         if(p > ask && p < nearestBuy) nearestBuy = p;
        }
     }

   // تعیین قیمت ورود سفارش جدید
   double entry = (nearestBuy < DBL_MAX) ? nearestBuy + step : ask + step;

   // رعایت حداقل فاصله بروکر
   long stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist = (stopsLevel + 1) * _Point;
   if(entry - ask < minDist) entry = ask + minDist;

   double lot = CalcLot(SL_Points);
   double sl  = (SL_Points > 0) ? PointToPrice(entry, SL_Points, true,  true) : 0;
   double tp  = (TP_Points > 0) ? PointToPrice(entry, TP_Points, false, true) : 0;
   PlacePendingOrder(ORDER_TYPE_BUY_STOP, lot, entry, sl, tp, "Buy_Dyn");

   // حذف دورترین سفارش فروش (پایین‌ترین قیمت)
   DeleteFarthestSellStop();
  }

//+------------------------------------------------------------------+
//| گسترش فروش: پر کردن نزدیک‌ترین شکاف پایین Bid                  |
//+------------------------------------------------------------------+
void SellAdjustment()
  {
   double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double step = GridStep_Points * _Point;

   // پیدا کردن نزدیک‌ترین Sell Stop موجود پایین Bid
   double nearestSell = -1;
   for(int i = OrdersTotal()-1; i >= 0; i--)
     {
      ulong t = OrderGetTicket(i);
      if(OrderSelect(t) &&
         OrderGetInteger(ORDER_MAGIC) == MagicNumber &&
         OrderGetString(ORDER_SYMBOL) == _Symbol &&
         OrderGetInteger(ORDER_TYPE)  == ORDER_TYPE_SELL_STOP)
        {
         double p = OrderGetDouble(ORDER_PRICE_OPEN);
         if(p < bid && p > nearestSell) nearestSell = p;
        }
     }

   // تعیین قیمت ورود سفارش جدید
   double entry = (nearestSell > 0) ? nearestSell - step : bid - step;

   long stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist = (stopsLevel + 1) * _Point;
   if(bid - entry < minDist) entry = bid - minDist;

   double lot = CalcLot(SL_Points);
   double sl  = (SL_Points > 0) ? PointToPrice(entry, SL_Points, true,  false) : 0;
   double tp  = (TP_Points > 0) ? PointToPrice(entry, TP_Points, false, false) : 0;
   PlacePendingOrder(ORDER_TYPE_SELL_STOP, lot, entry, sl, tp, "Sell_Dyn");

   // حذف دورترین سفارش خرید (بالاترین قیمت)
   DeleteFarthestBuyStop();
  }

//+------------------------------------------------------------------+
//| حذف دورترین سفارش فروش (پایین‌ترین قیمت)                        |
//+------------------------------------------------------------------+
void DeleteFarthestSellStop()
  {
   ulong  farthestTicket = 0;
   double farthestPrice  = DBL_MAX;

   for(int i = OrdersTotal()-1; i >= 0; i--)
     {
      ulong t = OrderGetTicket(i);
      if(OrderSelect(t) &&
         OrderGetInteger(ORDER_MAGIC) == MagicNumber &&
         OrderGetString(ORDER_SYMBOL) == _Symbol &&
         OrderGetInteger(ORDER_TYPE)  == ORDER_TYPE_SELL_STOP)
        {
         double p = OrderGetDouble(ORDER_PRICE_OPEN);
         if(p < farthestPrice)
           {
            farthestPrice  = p;
            farthestTicket = t;
           }
        }
     }

   if(farthestTicket != 0)
      GridTrade.OrderDelete(farthestTicket);
  }

//+------------------------------------------------------------------+
//| حذف دورترین سفارش خرید (بالاترین قیمت)                          |
//+------------------------------------------------------------------+
void DeleteFarthestBuyStop()
  {
   ulong  farthestTicket = 0;
   double farthestPrice  = 0;

   for(int i = OrdersTotal()-1; i >= 0; i--)
     {
      ulong t = OrderGetTicket(i);
      if(OrderSelect(t) &&
         OrderGetInteger(ORDER_MAGIC) == MagicNumber &&
         OrderGetString(ORDER_SYMBOL) == _Symbol &&
         OrderGetInteger(ORDER_TYPE)  == ORDER_TYPE_BUY_STOP)
        {
         double p = OrderGetDouble(ORDER_PRICE_OPEN);
         if(p > farthestPrice)
           {
            farthestPrice  = p;
            farthestTicket = t;
           }
        }
     }

   if(farthestTicket != 0)
      GridTrade.OrderDelete(farthestTicket);
  }
//+------------------------------------------------------------------+
//| بررسی سود/زیان کل                                               |
//+------------------------------------------------------------------+
void CheckTotalProfitLoss()
  {
   double totalProfit = 0;
   int    posCount    = 0;

   for(int i = PositionsTotal()-1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(PositionSelectByTicket(t) &&
         PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
         PositionGetString(POSITION_SYMBOL) == _Symbol)
        { totalProfit += PositionGetDouble(POSITION_PROFIT); posCount++; }
     }
   if(posCount == 0) return;

   if(totalProfit >= TotalProfitTarget)
     {
      PrintFormat("✅ هدف سود کل برآورده شد: %.2f$", totalProfit);
      CloseAll(); tradingDone = true; isTradingActive = false;
     }
   else if(totalProfit <= TotalStopLoss)
     {
      PrintFormat("🛑 حد ضرر کل فعال شد: %.2f$", totalProfit);
      CloseAll(); tradingDone = true; isTradingActive = false;
     }
  }

//+------------------------------------------------------------------+
//| بستن همه                                                        |
//+------------------------------------------------------------------+
void CloseAll()
  {
   for(int i = PositionsTotal()-1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(PositionSelectByTicket(t) &&
         PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
         PositionGetString(POSITION_SYMBOL) == _Symbol)
         GridTrade.PositionClose(t);
     }
   for(int i = OrdersTotal()-1; i >= 0; i--)
     {
      ulong t = OrderGetTicket(i);
      if(OrderSelect(t) &&
         OrderGetInteger(ORDER_MAGIC) == MagicNumber &&
         OrderGetString(ORDER_SYMBOL) == _Symbol)
         GridTrade.OrderDelete(t);
     }
   Print("تمام پوزیشن‌ها و سفارشات بسته شدند.");
  }

//+------------------------------------------------------------------+
//| بستن فقط سودده‌ها                                               |
//+------------------------------------------------------------------+
void CloseProfitableGrid()
  {
   int closed = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(PositionSelectByTicket(t) &&
         PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
         PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetDouble(POSITION_PROFIT) > 0)
         if(GridTrade.PositionClose(t)) closed++;
     }
   PrintFormat("%d پوزیشن سودده بسته شد.", closed);
  }

//+------------------------------------------------------------------+
void CloseAllGrid()
  {
   CloseAll();
   isTradingActive = false;
   tradingDone     = true;
   Print("شبکه متوقف شد. برای شروع مجدد دکمه «شروع شبکه» را بزنید.");
  }

void DeleteAllOrdersAndPositions()
  {
   for(int i = OrdersTotal()-1; i >= 0; i--)
     {
      ulong t = OrderGetTicket(i);
      if(OrderSelect(t) &&
         OrderGetInteger(ORDER_MAGIC) == MagicNumber &&
         OrderGetString(ORDER_SYMBOL) == _Symbol)
         GridTrade.OrderDelete(t);
     }
   for(int i = PositionsTotal()-1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(PositionSelectByTicket(t) &&
         PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
         PositionGetString(POSITION_SYMBOL) == _Symbol)
         GridTrade.PositionClose(t);
     }
  }

//+------------------------------------------------------------------+
//| یافتن بالاترین Buy Stop                                         |
//+------------------------------------------------------------------+
double FindHighestBuyStopPrice()
  {
   double maxP = 0;
   for(int i = OrdersTotal()-1; i >= 0; i--)
     {
      ulong t = OrderGetTicket(i);
      if(OrderSelect(t) &&
         OrderGetInteger(ORDER_MAGIC) == MagicNumber &&
         OrderGetString(ORDER_SYMBOL) == _Symbol &&
         OrderGetInteger(ORDER_TYPE)  == ORDER_TYPE_BUY_STOP)
        {
         double p = OrderGetDouble(ORDER_PRICE_OPEN);
         if(p > maxP) maxP = p;
        }
     }
   if(maxP == 0)
      maxP = SymbolInfoDouble(_Symbol, SYMBOL_ASK) + GridStep_Points * _Point;
   return maxP;
  }

//+------------------------------------------------------------------+
//| یافتن پایین‌ترین Sell Stop                                      |
//+------------------------------------------------------------------+
double FindLowestSellStopPrice()
  {
   double minP = DBL_MAX;
   for(int i = OrdersTotal()-1; i >= 0; i--)
     {
      ulong t = OrderGetTicket(i);
      if(OrderSelect(t) &&
         OrderGetInteger(ORDER_MAGIC) == MagicNumber &&
         OrderGetString(ORDER_SYMBOL) == _Symbol &&
         OrderGetInteger(ORDER_TYPE)  == ORDER_TYPE_SELL_STOP)
        {
         double p = OrderGetDouble(ORDER_PRICE_OPEN);
         if(p < minP) minP = p;
        }
     }
   if(minP == DBL_MAX)
      minP = SymbolInfoDouble(_Symbol, SYMBOL_BID) - GridStep_Points * _Point;
   return minP;
  }

//+------------------------------------------------------------------+
//| داشبورد اطلاعات                                                  |
//+------------------------------------------------------------------+
void ShowDashboard()
  {
   double totalProfit = 0;
   int    posCount = 0, ordCount = 0, buyPos = 0, sellPos = 0;

   for(int i = PositionsTotal()-1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(PositionSelectByTicket(t) &&
         PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
         PositionGetString(POSITION_SYMBOL) == _Symbol)
        {
         totalProfit += PositionGetDouble(POSITION_PROFIT);
         posCount++;
         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) buyPos++;
         else sellPos++;
        }
     }
   for(int i = OrdersTotal()-1; i >= 0; i--)
     {
      ulong t = OrderGetTicket(i);
      if(OrderSelect(t) &&
         OrderGetInteger(ORDER_MAGIC) == MagicNumber &&
         OrderGetString(ORDER_SYMBOL) == _Symbol)
         ordCount++;
     }

   // محاسبه فاصله‌های واقعی بر حسب قیمت
   double stepPrice = GridStep_Points * _Point;
   double slPrice   = SL_Points * _Point;
   double tpPrice   = TP_Points * _Point;

   string status = isTradingActive ? "فعال ✅" : "متوقف ⛔";
   string info   = StringFormat(
      "══ GridHedge v4.00 | %s ══\n"
      "_Point      : %.8f\n"
      "GridStep    : %.5f  (%.0f pt)\n"
      "SL فاصله   : %.5f  (%.0f pt)\n"
      "TP فاصله   : %.5f  (%.0f pt)\n"
      "Lot فعلی   : %.2f\n"
      "─────────────────────────\n"
      "سود/زیان   : %.2f $\n"
      "پوزیشن‌ها  : %d  (B:%d | S:%d)\n"
      "سفارشات    : %d\n"
      "گسترش Buy  : %d / %d\n"
      "گسترش Sell : %d / %d\n"
      "هدف سود    : %.2f$ | ضرر: %.2f$",
      status,
      _Point,
      stepPrice, GridStep_Points,
      slPrice,   SL_Points,
      tpPrice,   TP_Points,
      g_CurrentLot,
      totalProfit,
      posCount, buyPos, sellPos,
      ordCount,
      buyExpansionCount,  g_MaxBuyExpansions,
      sellExpansionCount, g_MaxSellExpansions,
      TotalProfitTarget, TotalStopLoss
   );
  
   
   if(ObjectFind(0, DASHBOARD_LABEL) < 0)
     {
      ObjectCreate(0, DASHBOARD_LABEL, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, DASHBOARD_LABEL, OBJPROP_CORNER, CORNER_LEFT_LOWER);
      ObjectSetInteger(0, DASHBOARD_LABEL, OBJPROP_XDISTANCE, 10);   // فاصله از لبه چپ
      ObjectSetInteger(0, DASHBOARD_LABEL, OBJPROP_YDISTANCE, 10);   // فاصله از لبه پایین
      ObjectSetInteger(0, DASHBOARD_LABEL, OBJPROP_COLOR, clrYellow);
      ObjectSetInteger(0, DASHBOARD_LABEL, OBJPROP_FONTSIZE, 10);
      ObjectSetInteger(0, DASHBOARD_LABEL, OBJPROP_SELECTABLE, false);
     }

   ObjectSetString(0, DASHBOARD_LABEL, OBJPROP_TEXT, info);

  }

//+------------------------------------------------------------------+
//| دکمه شروع                                                        |
//+------------------------------------------------------------------+
void CreateStartButton()
  {
   string n = "BtnStartGrid";
   if(ObjectFind(0, n) >= 0) ObjectDelete(0, n);
   ObjectCreate(0, n, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, n, OBJPROP_CORNER,       CORNER_LEFT_UPPER);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE,    10);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE,    100);
   ObjectSetInteger(0, n, OBJPROP_XSIZE,        220);
   ObjectSetInteger(0, n, OBJPROP_YSIZE,        60);
   ObjectSetString (0, n, OBJPROP_TEXT,         "شروع شبکه");
   ObjectSetInteger(0, n, OBJPROP_COLOR,        clrWhite);
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR,      clrSeaGreen);
   ObjectSetInteger(0, n, OBJPROP_BORDER_COLOR, clrBlack);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE,     13);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE,   false);
  }

//+------------------------------------------------------------------+
//| دکمه‌های بستن                                                   |
//+------------------------------------------------------------------+
void CreateCloseButtons()
  {
   string n1 = "BtnCloseProfitable";
   if(ObjectFind(0, n1) < 0)
     {
      ObjectCreate(0, n1, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, n1, OBJPROP_CORNER,       CORNER_LEFT_UPPER);
      ObjectSetInteger(0, n1, OBJPROP_XDISTANCE,    240);
      ObjectSetInteger(0, n1, OBJPROP_YDISTANCE,    100);
      ObjectSetInteger(0, n1, OBJPROP_XSIZE,        220);
      ObjectSetInteger(0, n1, OBJPROP_YSIZE,        60);
      ObjectSetString (0, n1, OBJPROP_TEXT,         "بستن سودده");
      ObjectSetInteger(0, n1, OBJPROP_COLOR,        clrWhite);
      ObjectSetInteger(0, n1, OBJPROP_BGCOLOR,      clrOrangeRed);
      ObjectSetInteger(0, n1, OBJPROP_BORDER_COLOR, clrBlack);
      ObjectSetInteger(0, n1, OBJPROP_FONTSIZE,     13);
      ObjectSetInteger(0, n1, OBJPROP_SELECTABLE,   false);
     }

   string n2 = "BtnCloseAllGrid";
   if(ObjectFind(0, n2) < 0)
     {
      ObjectCreate(0, n2, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, n2, OBJPROP_CORNER,       CORNER_LEFT_UPPER);
      ObjectSetInteger(0, n2, OBJPROP_XDISTANCE,    470);
      ObjectSetInteger(0, n2, OBJPROP_YDISTANCE,    100);
      ObjectSetInteger(0, n2, OBJPROP_XSIZE,        220);
      ObjectSetInteger(0, n2, OBJPROP_YSIZE,        60);
      ObjectSetString (0, n2, OBJPROP_TEXT,         "بستن همه");
      ObjectSetInteger(0, n2, OBJPROP_COLOR,        clrWhite);
      ObjectSetInteger(0, n2, OBJPROP_BGCOLOR,      clrFireBrick);
      ObjectSetInteger(0, n2, OBJPROP_BORDER_COLOR, clrBlack);
      ObjectSetInteger(0, n2, OBJPROP_FONTSIZE,     13);
      ObjectSetInteger(0, n2, OBJPROP_SELECTABLE,   false);
     }
  }

//+------------------------------------------------------------------+
//| دکمه‌های گسترش                                                  |
//+------------------------------------------------------------------+
void CreateExpansionButtons()
  {
   ObjectCreate(0, "LblBuyExp", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "LblBuyExp", OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0, "LblBuyExp", OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, "LblBuyExp", OBJPROP_YDISTANCE, 180);
   ObjectSetString (0, "LblBuyExp", OBJPROP_TEXT,      "توسعه خرید:");
   ObjectSetInteger(0, "LblBuyExp", OBJPROP_COLOR,     clrWhite);
   ObjectSetInteger(0, "LblBuyExp", OBJPROP_FONTSIZE,  10);

   CreateButton("BtnBuyExpMinus", "-", 190, 180, 50, 50, clrWhite, clrRed,   14);

   ObjectCreate(0, "ValBuyExp", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "ValBuyExp", OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0, "ValBuyExp", OBJPROP_XDISTANCE, 250);
   ObjectSetInteger(0, "ValBuyExp", OBJPROP_YDISTANCE, 180);
   ObjectSetString (0, "ValBuyExp", OBJPROP_TEXT,      IntegerToString(g_MaxBuyExpansions));
   ObjectSetInteger(0, "ValBuyExp", OBJPROP_COLOR,     clrYellow);
   ObjectSetInteger(0, "ValBuyExp", OBJPROP_FONTSIZE,  14);

   CreateButton("BtnBuyExpPlus",  "+", 285, 180, 50, 50, clrWhite, clrGreen, 14);

   ObjectCreate(0, "LblSellExp", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "LblSellExp", OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0, "LblSellExp", OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, "LblSellExp", OBJPROP_YDISTANCE, 250);
   ObjectSetString (0, "LblSellExp", OBJPROP_TEXT,      "توسعه فروش:");
   ObjectSetInteger(0, "LblSellExp", OBJPROP_COLOR,     clrWhite);
   ObjectSetInteger(0, "LblSellExp", OBJPROP_FONTSIZE,  10);

   CreateButton("BtnSellExpMinus", "-", 190, 240, 50, 50, clrWhite, clrRed,   14);

   ObjectCreate(0, "ValSellExp", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "ValSellExp", OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0, "ValSellExp", OBJPROP_XDISTANCE, 250);
   ObjectSetInteger(0, "ValSellExp", OBJPROP_YDISTANCE, 240);
   ObjectSetString (0, "ValSellExp", OBJPROP_TEXT,      IntegerToString(g_MaxSellExpansions));
   ObjectSetInteger(0, "ValSellExp", OBJPROP_COLOR,     clrYellow);
   ObjectSetInteger(0, "ValSellExp", OBJPROP_FONTSIZE,  14);

   CreateButton("BtnSellExpPlus",  "+", 285, 240, 50, 50, clrWhite, clrGreen, 14);
  }

//+------------------------------------------------------------------+
void CreateButton(string name, string text, int x, int y,
                  int w, int h, color ct, color cb, int fs)
  {
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER,       CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,    x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,    y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,        w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,        h);
   ObjectSetString (0, name, OBJPROP_TEXT,         text);
   ObjectSetInteger(0, name, OBJPROP_COLOR,        ct);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,      cb);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, clrBlack);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,     fs);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE,   false);
  }
//+------------------------------------------------------------------+
