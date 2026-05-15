//+------------------------------------------------------------------+
//|                                GridHedge_Ultimate_v5.mq5          |
//|               شبکه گرید هوشمند - گسترش با فعال‌شدن سفارش        |
//+------------------------------------------------------------------+
#property copyright "Hamed Movasaqpoor"
#property link      "hamed.movasaqpoor@gmail.com"
#property version   "5.1"

#include <Trade\Trade.mqh>


//------------------------- INPUT PARAMETERS -------------------------
input group "=== تنظیمات کلی ==="
input int    MagicNumber       = 202701;   // شماره جادویی
input int    TesterStartHour      = 1;        // ساعت شروع شبکه در تستر (0-23)


input group "=== تشخیص روند ==="
input bool             UseManualDirection  = false;
input int              DirectionChoice     = 0;
input int              TrendMAPeriod       = 20;
input int              TrendMAShift        = 0;
input ENUM_MA_METHOD   TrendMAMethod       = MODE_EMA;
input int              TrendConfirmCandles = 3;


input group "=== معاملات ==="
input double FixedLot          = 0.01;     // حجم ثابت هر پله لات
input double SL_Points         = 0;        // حد ضرر هر پله (Point)
input double TP_Points         = 100.0;    // حد سود هر پله (Point)
input int    GridLevels        = 4;         // تعداد پله های اولیه
input double GridStep_Points   = 100.0;     // فاصله پله ها (Point)
input double TotalProfitTarget = 40.0;     // هدف سود کل (دلار)
input double TotalStopLoss     = -100.0;    // حد ضرر کل (عدد منفی، دلار)


input group "=== گسترش شبکه ==="
input int    InitialMaxBuyExpansions  = 4;
input int    InitialMaxSellExpansions = 4;
input int    ExpansionMethod       = 1;        //متد گسترش : 0 = فعال‌شدن سفارش | 1 = تغییر قیمت

//------------------------- GLOBAL VARIABLES -------------------------
CTrade GridTrade;
bool   g_WaitingForMarketOpen = false;
string g_GridID            = "";
bool   isTradingActive     = false;
bool   tradingDone         = false;

int    buyExpansionCount      = 0;
int    sellExpansionCount     = 0;
int    g_MaxBuyExpansions;
int    g_MaxSellExpansions;

int    lastBuyPosCount   = 0;   // برای شناسایی فعال‌شدن سفارش خرید
int    lastSellPosCount  = 0;   // برای شناسایی فعال‌شدن سفارش فروش
double lastBuyExpansionPrice  = 0;   // نقطه‌ی مرجع برای گسترش خرید
double lastSellExpansionPrice = 0;   // نقطه‌ی مرجع برای گسترش فروش

double g_ActualGridStep  = 0;

int    g_ActiveMagic = 0;        // MagicNumber پویا برای شبکه‌ی جاری
int    g_GridInstance = 0;       // شمارنده‌ی شبکه (برای تولید Magic یکتا)

//+------------------------------------------------------------------+
//| چاپ اطلاعات نماد                                                |
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
//| محاسبه حجم لات (همیشه ثابت، بدون درصد ریسک)                    |
//+------------------------------------------------------------------+
double CalcLot(double slPoints)
  {
   return FixedLot;
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
   g_GridInstance      = 0;
   g_ActiveMagic       = MagicNumber + g_GridInstance;

   PrintSymbolInfo();

   bool isTester = (bool)MQL5InfoInteger(MQL5_TESTER);

   if(isTester)
    DeleteAllOrdersAndPositions();

   if(!isTester)
     {
      CreateCloseButtons();        // «بستن سودده»، «بستن همه»، «پایان شبکه»
      CreateExpansionButtons();    // دکمه‌های ± خرید و فروش
      CreateStartButton();         // «شروع شبکه»
      isTradingActive = false;
      Print("منتظر کلیک روی دکمه «شروع شبکه» باشید...");
      return INIT_SUCCEEDED;
     }

   // مسیر تستر
   isTradingActive = true;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.hour < TesterStartHour)
     {
      g_WaitingForMarketOpen = true;
      PrintFormat("⏳ تستر: ساعت فعلی %d، منتظر ساعت %d ...", dt.hour, TesterStartHour);
      return INIT_SUCCEEDED;
     }

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
   ObjectDelete(0, "BtnFinishGrid");
   Comment("");
  }

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
  {
   // اگر منتظر باز شدن بازار (واقعی) یا رسیدن به ساعت شروع (تستر) هستیم
   if(g_WaitingForMarketOpen)
     {
      bool shouldStart = false;

      if(MQL5InfoInteger(MQL5_TESTER))
        {
         MqlDateTime dt;
         TimeToStruct(TimeCurrent(), dt);
         if(dt.hour >= TesterStartHour)
            shouldStart = true;
        }
      else if(IsMarketOpen())
        {
         shouldStart = true;
        }

      if(shouldStart)
        {
         Print("✅ شرایط شروع فراهم شد. اجرای استراتژی...");
         g_WaitingForMarketOpen = false;
         ExecuteStrategy();
         return; // در همین تیک باقی عملیات انجام نشود
        }
      else return; // همچنان منتظر
     }

   if(!isTradingActive || tradingDone) return;

   // لاگ تشخیصی – وضعیت گسترش
  //  PrintFormat("🔍 Tick | BuyExp: %d/%d | SellExp: %d/%d | Method: %d",
  //              buyExpansionCount, g_MaxBuyExpansions,
  //              sellExpansionCount, g_MaxSellExpansions,
  //              ExpansionMethod);

      // گسترش شبکه بر اساس روش انتخاب‌شده
   if(ExpansionMethod == 0)
     {
      // روش فعلی: با فعال‌شدن سفارش (تبدیل به پوزیشن)
      int currentBuy  = CountPositionsByType(POSITION_TYPE_BUY);
      int currentSell = CountPositionsByType(POSITION_TYPE_SELL);

      PrintFormat("🔍 Method0 | currentBuy: %d, lastBuyPosCount: %d | currentSell: %d, lastSellPosCount: %d",
                  currentBuy, lastBuyPosCount, currentSell, lastSellPosCount);

      if(currentBuy > lastBuyPosCount)
        {
         TryBuyExpansion("فعال‌شدن سفارش خرید");
         lastBuyPosCount = currentBuy;
        }

      if(currentSell > lastSellPosCount)
        {
         TrySellExpansion("فعال‌شدن سفارش فروش");
         lastSellPosCount = currentSell;
        }

      // اگر قیمت از سقف/کف جدید برگشت کند، سمت مخالف هم نزدیک کندل دوباره ساخته شود.
      ProcessPriceMovementExpansion();
     }
   else // ExpansionMethod == 1 (بر اساس تغییر قیمت)
     {
      ProcessPriceMovementExpansion();
     }

   CheckTotalProfitLoss();
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
   if(sparam == "BtnFinishGrid")        { FinalizeGrid();          return; }

   if(sparam == "BtnBuyExpPlus")
     {
      g_MaxBuyExpansions = MathMin(g_MaxBuyExpansions + 1, 100);
      UpdateExpansionLabels();
      Print("MaxBuyExpansions → ", g_MaxBuyExpansions);
     }
   else if(sparam == "BtnBuyExpMinus")
     {
      g_MaxBuyExpansions = MathMax(g_MaxBuyExpansions - 1, 0);
      UpdateExpansionLabels();
      Print("MaxBuyExpansions → ", g_MaxBuyExpansions);
     }
   else if(sparam == "BtnSellExpPlus")
     {
      g_MaxSellExpansions = MathMin(g_MaxSellExpansions + 1, 100);
      UpdateExpansionLabels();
      Print("MaxSellExpansions → ", g_MaxSellExpansions);
     }
   else if(sparam == "BtnSellExpMinus")
     {
      g_MaxSellExpansions = MathMax(g_MaxSellExpansions - 1, 0);
      UpdateExpansionLabels();
      Print("MaxSellExpansions → ", g_MaxSellExpansions);
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
         PositionGetInteger(POSITION_MAGIC) == g_ActiveMagic &&   // <-- تغییر
         PositionGetString(POSITION_SYMBOL) == _Symbol)
         return true;
     }
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong t = OrderGetTicket(i);
      if(OrderSelect(t) &&
         OrderGetInteger(ORDER_MAGIC) == g_ActiveMagic &&        // <-- تغییر
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
   

   if(direction == ORDER_TYPE_BUY)
     {
      double sl = (SL_Points > 0) ? PointToPrice(ask, SL_Points, true,  true) : 0;
      double tp = (TP_Points > 0) ? PointToPrice(ask, TP_Points, false, true) : 0;
      PlaceInitialLimit(ORDER_TYPE_BUY, FixedLot, sl, tp, "Initial Buy");
     }
   else
     {
      double sl = (SL_Points > 0) ? PointToPrice(bid, SL_Points, true,  false) : 0;
      double tp = (TP_Points > 0) ? PointToPrice(bid, TP_Points, false, false) : 0;
      PlaceInitialLimit(ORDER_TYPE_SELL, FixedLot, sl, tp, "Initial Sell");
     }

   PlaceGrid();

   lastBuyExpansionPrice  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   lastSellExpansionPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // مقداردهی شمارنده‌های موقعیت برای نظارت بر فعال‌شدن
   lastBuyPosCount  = CountPositionsByType(POSITION_TYPE_BUY);
   lastSellPosCount = CountPositionsByType(POSITION_TYPE_SELL);
   buyExpansionCount  = 0;
   sellExpansionCount = 0;
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
   if(CopyBuffer(handle, 0, 0, needed, ema) != needed ||
      CopyClose(_Symbol, 0, 0, needed, cls)  != needed)
     {
      Print("خطا در کپی داده EMA");
      IndicatorRelease(handle);
      return -1;
     }
   IndicatorRelease(handle);

   int confirm  = MathMax(TrendConfirmCandles, 1);
   bool bullish = true, bearish = true;
   for(int i = 0; i < confirm; i++)
     {
      if(cls[i] <= ema[i]) bullish = false;
      if(cls[i] >= ema[i]) bearish = false;
     }
   bool slopeUp   = ema[0] > ema[confirm];
   bool slopeDown = ema[0] < ema[confirm];

   if(bullish && slopeUp)   return ORDER_TYPE_BUY;
   if(bearish && slopeDown) return ORDER_TYPE_SELL;

   // بازار رنج – تصمیم ساده
   if(cls[0] > ema[0]) return ORDER_TYPE_BUY;
   if(cls[0] < ema[0]) return ORDER_TYPE_SELL;
   return ORDER_TYPE_BUY;
  }


//+------------------------------------------------------------------+
//| Limit Order اولیه                                                |
//+------------------------------------------------------------------+
bool PlaceInitialLimit(ENUM_ORDER_TYPE type, double lot, double sl, double tp, string comment)
  {
   Sleep(30);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double halfStep = (GridStep_Points / 2.0) * _Point;
   double price = (type == ORDER_TYPE_BUY)
                  ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) - halfStep
                  : SymbolInfoDouble(_Symbol, SYMBOL_BID) + halfStep;

   long   stopsLvl  = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long   freezeLvl = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double minDist   = (stopsLvl + freezeLvl + 2) * _Point;

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
   req.magic        = g_ActiveMagic;
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
      PlacePendingOrder(ORDER_TYPE_BUY_STOP, lot, entry, sl, tp, "BuyStop_"+IntegerToString(i));
     }

   for(int i = 1; i <= GridLevels; i++)
     {
      double entry = bid - i * step;
      if(bid - entry < minDist) entry = bid - minDist;
      double lot = CalcLot(SL_Points);
      double sl  = (SL_Points > 0) ? PointToPrice(entry, SL_Points, true,  false) : 0;
      double tp  = (TP_Points > 0) ? PointToPrice(entry, TP_Points, false, false) : 0;
      PlacePendingOrder(ORDER_TYPE_SELL_STOP, lot, entry, sl, tp, "SellStop_"+IntegerToString(i));
     }
   Print("✅ شبکه اولیه ثبت شد.");
  }

//+------------------------------------------------------------------+
//| ثبت سفارش معلق                                                  |
//+------------------------------------------------------------------+
bool PlacePendingOrder(ENUM_ORDER_TYPE type, double lot, double entry,
                       double sl, double tp, string comment){
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
   req.magic        = g_ActiveMagic;
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
//| ثبت گسترش خرید و به‌روزرسانی شمارنده فقط در صورت ساخت سفارش    |
//+------------------------------------------------------------------+
bool TryBuyExpansion(string reason)
  {
   if(buyExpansionCount >= g_MaxBuyExpansions)
      return false;

   PrintFormat("%s - گسترش خرید %d/%d", reason, buyExpansionCount+1, g_MaxBuyExpansions);
   if(!BuyAdjustment())
      return false;

   buyExpansionCount++;
   UpdateExpansionLabels();
   return true;
  }

//+------------------------------------------------------------------+
//| ثبت گسترش فروش و به‌روزرسانی شمارنده فقط در صورت ساخت سفارش    |
//+------------------------------------------------------------------+
bool TrySellExpansion(string reason)
  {
   if(sellExpansionCount >= g_MaxSellExpansions)
      return false;

   PrintFormat("%s - گسترش فروش %d/%d", reason, sellExpansionCount+1, g_MaxSellExpansions);
   if(!SellAdjustment())
      return false;

   sellExpansionCount++;
   UpdateExpansionLabels();
   return true;
  }

//+------------------------------------------------------------------+
//| مرجع خرید کف اخیر و مرجع فروش سقف اخیر را دنبال می‌کند          |
//+------------------------------------------------------------------+
void TrailExpansionReferences(double ask, double bid)
  {
   if(lastBuyExpansionPrice <= 0)  lastBuyExpansionPrice  = ask;
   if(lastSellExpansionPrice <= 0) lastSellExpansionPrice = bid;

   if(ask < lastBuyExpansionPrice)
      lastBuyExpansionPrice = ask;

   if(bid > lastSellExpansionPrice)
      lastSellExpansionPrice = bid;
  }

//+------------------------------------------------------------------+
//| گسترش بر اساس حرکت قیمت، با پشتیبانی از برگشت روند              |
//+------------------------------------------------------------------+
void ProcessPriceMovementExpansion()
  {
   double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double step = GridStep_Points * _Point;

   TrailExpansionReferences(ask, bid);

   if(ask >= lastBuyExpansionPrice + step)
     {
      TryBuyExpansion("حرکت قیمت از کف مرجع خرید");
      lastBuyExpansionPrice  = ask;
      lastSellExpansionPrice = bid;
     }

   if(bid <= lastSellExpansionPrice - step)
     {
      TrySellExpansion("حرکت قیمت از سقف مرجع فروش");
      lastBuyExpansionPrice  = ask;
      lastSellExpansionPrice = bid;
     }
  }

//+------------------------------------------------------------------+
//| گسترش خرید: اضافه کردن یک Buy Stop نزدیک Ask                    |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| گسترش خرید: اضافه کردن یک Buy Stop نزدیک Ask                    |
//+------------------------------------------------------------------+
bool BuyAdjustment()
  {
   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double step  = GridStep_Points * _Point;
   long   stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist    = (stopsLevel + 1) * _Point;

   double candidate = ask + step;
   if(candidate - ask < minDist) candidate = ask + minDist;

   bool alreadyExists = false;
   for(int i = OrdersTotal()-1; i >= 0; i--)
     {
      ulong t = OrderGetTicket(i);
      if(OrderSelect(t) &&
         OrderGetInteger(ORDER_MAGIC) == g_ActiveMagic &&
         OrderGetString(ORDER_SYMBOL) == _Symbol &&
         OrderGetInteger(ORDER_TYPE)  == ORDER_TYPE_BUY_STOP)
        {
         if(MathAbs(OrderGetDouble(ORDER_PRICE_OPEN) - candidate) < 0.5 * _Point)
           {
            alreadyExists = true;
            break;
           }
        }
     }

   // لاگ تشخیصی
   PrintFormat("🔧 BuyAdjustment | candidate: %.5f, Ask: %.5f, alreadyExists: %s",
               candidate, ask, alreadyExists ? "true" : "false");

   if(!alreadyExists)
     {
      double lot = CalcLot(SL_Points);
      double sl  = (SL_Points > 0) ? PointToPrice(candidate, SL_Points, true,  true) : 0;
      double tp  = (TP_Points > 0) ? PointToPrice(candidate, TP_Points, false, true) : 0;
      if(PlacePendingOrder(ORDER_TYPE_BUY_STOP, lot, candidate, sl, tp, "Buy_Dyn"))
        {
         Print("🔧 BuyAdjustment | سفارش جدید ثبت شد.");
         return true;
        }
      return false;
     }
   else
     {
      Print("🔧 BuyAdjustment | سفارش تکراری - ایجاد نشد.");
     }
   return false;
  }

//+------------------------------------------------------------------+
//| گسترش فروش: اضافه کردن یک Sell Stop نزدیک Bid                   |
//+------------------------------------------------------------------+
bool SellAdjustment()
  {
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double step  = GridStep_Points * _Point;
   long   stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist    = (stopsLevel + 1) * _Point;

   double candidate = bid - step;
   if(bid - candidate < minDist) candidate = bid - minDist;

   bool alreadyExists = false;
   for(int i = OrdersTotal()-1; i >= 0; i--)
     {
      ulong t = OrderGetTicket(i);
      if(OrderSelect(t) &&
         OrderGetInteger(ORDER_MAGIC) == g_ActiveMagic &&
         OrderGetString(ORDER_SYMBOL) == _Symbol &&
         OrderGetInteger(ORDER_TYPE)  == ORDER_TYPE_SELL_STOP)
        {
         if(MathAbs(OrderGetDouble(ORDER_PRICE_OPEN) - candidate) < 0.5 * _Point)
           {
            alreadyExists = true;
            break;
           }
        }
     }

   // لاگ تشخیصی
   PrintFormat("🔧 SellAdjustment | candidate: %.5f, Bid: %.5f, alreadyExists: %s",
               candidate, bid, alreadyExists ? "true" : "false");

   if(!alreadyExists)
     {
      double lot = CalcLot(SL_Points);
      double sl  = (SL_Points > 0) ? PointToPrice(candidate, SL_Points, true,  false) : 0;
      double tp  = (TP_Points > 0) ? PointToPrice(candidate, TP_Points, false, false) : 0;
      if(PlacePendingOrder(ORDER_TYPE_SELL_STOP, lot, candidate, sl, tp, "Sell_Dyn"))
        {
         Print("🔧 SellAdjustment | سفارش جدید ثبت شد.");
         return true;
        }
      return false;
     }
   else
     {
      Print("🔧 SellAdjustment | سفارش تکراری - ایجاد نشد.");
     }
   return false;
  }


double FindHighestBuyStopPrice()
  {
   double maxP = 0;
   for(int i = OrdersTotal()-1; i >= 0; i--)
     {
      ulong t = OrderGetTicket(i);
      if(OrderSelect(t) &&
         OrderGetInteger(ORDER_MAGIC) == g_ActiveMagic &&
         OrderGetString(ORDER_SYMBOL) == _Symbol &&
         OrderGetInteger(ORDER_TYPE)  == ORDER_TYPE_BUY_STOP)
        {
         double p = OrderGetDouble(ORDER_PRICE_OPEN);
         if(p > maxP) maxP = p;
        }
     }
   return maxP;
  }

double FindLowestSellStopPrice()
  {
   double minP = DBL_MAX;
   for(int i = OrdersTotal()-1; i >= 0; i--)
     {
      ulong t = OrderGetTicket(i);
      if(OrderSelect(t) &&
         OrderGetInteger(ORDER_MAGIC) == g_ActiveMagic &&
         OrderGetString(ORDER_SYMBOL) == _Symbol &&
         OrderGetInteger(ORDER_TYPE)  == ORDER_TYPE_SELL_STOP)
        {
         double p = OrderGetDouble(ORDER_PRICE_OPEN);
         if(p < minP) minP = p;
        }
     }
   return minP;
  }

//+------------------------------------------------------------------+
//| شمارش پوزیشن‌های باز از یک نوع (خرید یا فروش)                  |
//+------------------------------------------------------------------+
int CountPositionsByType(long type)
  {
   int count = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(PositionSelectByTicket(t) &&
         PositionGetInteger(POSITION_MAGIC) == g_ActiveMagic &&
         PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_TYPE)  == type)
         count++;
     }
   return count;
  }

//+------------------------------------------------------------------+
//| بررسی سود/زیان کل                                               |
//+------------------------------------------------------------------+
void CheckTotalProfitLoss()
  {
   double totalProfit = 0; int posCount = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(PositionSelectByTicket(t) &&
         PositionGetInteger(POSITION_MAGIC) == g_ActiveMagic &&
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
         PositionGetInteger(POSITION_MAGIC) == g_ActiveMagic &&
         PositionGetString(POSITION_SYMBOL) == _Symbol)
         GridTrade.PositionClose(t);
     }
   for(int i = OrdersTotal()-1; i >= 0; i--)
     {
      ulong t = OrderGetTicket(i);
      if(OrderSelect(t) &&
         OrderGetInteger(ORDER_MAGIC) == g_ActiveMagic &&
         OrderGetString(ORDER_SYMBOL) == _Symbol)
         GridTrade.OrderDelete(t);
     }
   Print("تمامی پوزیشن‌ها و سفارشات بسته شدند.");
  }

//+------------------------------------------------------------------+
void CloseProfitableGrid()
  {
   int closed = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(PositionSelectByTicket(t) &&
         PositionGetInteger(POSITION_MAGIC) == g_ActiveMagic &&
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

void FinalizeGrid()
  {
   if(!AnyGridExists())
     {
      Print("هیچ شبکه‌ی فعالی برای پایان وجود ندارد.");
      return;
     }

   // افزایش شمارنده شبکه و تعیین Magic جدید
   g_GridInstance++;
   g_ActiveMagic = MagicNumber + g_GridInstance;

   // ریست شمارنده‌های داخلی (برای شبکه‌ی جدید)
   buyExpansionCount  = 0;
   sellExpansionCount = 0;
   lastBuyPosCount    = 0;
   lastSellPosCount   = 0;

   PrintFormat("شبکه با Magic=%d پایان یافت. Magic جدید=%d آماده‌ی شروع.", MagicNumber + g_GridInstance - 1, g_ActiveMagic);
  }

void DeleteAllOrdersAndPositions()
  {
   for(int i = OrdersTotal()-1; i >= 0; i--)
     {
      ulong t = OrderGetTicket(i);
      if(OrderSelect(t) &&
         OrderGetInteger(ORDER_MAGIC) == g_ActiveMagic &&
         OrderGetString(ORDER_SYMBOL) == _Symbol)
         GridTrade.OrderDelete(t);
     }
   for(int i = PositionsTotal()-1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(PositionSelectByTicket(t) &&
         PositionGetInteger(POSITION_MAGIC) == g_ActiveMagic &&
         PositionGetString(POSITION_SYMBOL) == _Symbol)
         GridTrade.PositionClose(t);
     }
  }

//+------------------------------------------------------------------+
//| بررسی باز بودن بازار (با اصلاح برای تستر / نمادهای بدون سشن)     |
//+------------------------------------------------------------------+
bool IsMarketOpen()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   ENUM_DAY_OF_WEEK day = (ENUM_DAY_OF_WEEK)dt.day_of_week;
   datetime from, to;
   int sessionCount = 0;

   for(int i = 0; i < 10; i++)
     {
      if(SymbolInfoSessionTrade(_Symbol, day, i, from, to))
        {
         sessionCount++;
         if(TimeCurrent() >= from && TimeCurrent() < to)
            return true;
        }
     }

   // اگر هیچ سشنی برای امروز پیدا نشد (حالت تستر یا نماد نامتعارف)، بازار را باز در نظر بگیرید
   if(sessionCount == 0)
      return true;

   return false;
  }

  //+------------------------------------------------------------------+
//| به‌روزرسانی برچسب‌های گسترش خرید و فروش                        |
//+------------------------------------------------------------------+
void UpdateExpansionLabels()
  {
   ObjectSetString(0, "ValBuyExp", OBJPROP_TEXT,
                   IntegerToString(buyExpansionCount) + "/" + IntegerToString(g_MaxBuyExpansions));
   ObjectSetString(0, "ValSellExp", OBJPROP_TEXT,
                   IntegerToString(sellExpansionCount) + "/" + IntegerToString(g_MaxSellExpansions));
  }
//+------------------------------------------------------------------+
//| دکمه شروع (فشرده‌تر)                                            |
//+------------------------------------------------------------------+
void CreateStartButton()
  {
   string n = "BtnStartGrid";
   if(ObjectFind(0, n) >= 0) ObjectDelete(0, n);
   ObjectCreate(0, n, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, n, OBJPROP_CORNER,       CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE,    258);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE,    8);
   ObjectSetInteger(0, n, OBJPROP_XSIZE,        74);
   ObjectSetInteger(0, n, OBJPROP_YSIZE,        24);
   ObjectSetString (0, n, OBJPROP_TEXT,         "شروع شبکه");
   ObjectSetInteger(0, n, OBJPROP_COLOR,        clrWhite);
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR,      clrSeaGreen);
   ObjectSetInteger(0, n, OBJPROP_BORDER_COLOR, clrBlack);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE,     8);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE,   false);
  }

//+------------------------------------------------------------------+
//| دکمه‌های بستن (کوچک‌تر)                                        |
//+------------------------------------------------------------------+
void CreateCloseButtons()
  {
   string n1 = "BtnCloseProfitable";
   if(ObjectFind(0, n1) < 0)
     {
      ObjectCreate(0, n1, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, n1, OBJPROP_CORNER,       CORNER_RIGHT_UPPER);
      ObjectSetInteger(0, n1, OBJPROP_XDISTANCE,    176);
      ObjectSetInteger(0, n1, OBJPROP_YDISTANCE,    8);
      ObjectSetInteger(0, n1, OBJPROP_XSIZE,        76);
      ObjectSetInteger(0, n1, OBJPROP_YSIZE,        24);
      ObjectSetString (0, n1, OBJPROP_TEXT,         "بستن سودده");
      ObjectSetInteger(0, n1, OBJPROP_COLOR,        clrWhite);
      ObjectSetInteger(0, n1, OBJPROP_BGCOLOR,      clrOrangeRed);
      ObjectSetInteger(0, n1, OBJPROP_BORDER_COLOR, clrBlack);
      ObjectSetInteger(0, n1, OBJPROP_FONTSIZE,     8);
      ObjectSetInteger(0, n1, OBJPROP_SELECTABLE,   false);
     }

   string n2 = "BtnCloseAllGrid";
   if(ObjectFind(0, n2) < 0)
     {
      ObjectCreate(0, n2, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, n2, OBJPROP_CORNER,       CORNER_RIGHT_UPPER);
      ObjectSetInteger(0, n2, OBJPROP_XDISTANCE,    102);
      ObjectSetInteger(0, n2, OBJPROP_YDISTANCE,    8);
      ObjectSetInteger(0, n2, OBJPROP_XSIZE,        68);
      ObjectSetInteger(0, n2, OBJPROP_YSIZE,        24);
      ObjectSetString (0, n2, OBJPROP_TEXT,         "بستن همه");
      ObjectSetInteger(0, n2, OBJPROP_COLOR,        clrWhite);
      ObjectSetInteger(0, n2, OBJPROP_BGCOLOR,      clrFireBrick);
      ObjectSetInteger(0, n2, OBJPROP_BORDER_COLOR, clrBlack);
      ObjectSetInteger(0, n2, OBJPROP_FONTSIZE,     8);
      ObjectSetInteger(0, n2, OBJPROP_SELECTABLE,   false);
     }

    string n3 = "BtnFinishGrid";
    if(ObjectFind(0, n3) < 0)
     {
      ObjectCreate(0, n3, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, n3, OBJPROP_CORNER,       CORNER_RIGHT_UPPER);
      ObjectSetInteger(0, n3, OBJPROP_XDISTANCE,    24);
      ObjectSetInteger(0, n3, OBJPROP_YDISTANCE,    8);
      ObjectSetInteger(0, n3, OBJPROP_XSIZE,        72);
      ObjectSetInteger(0, n3, OBJPROP_YSIZE,        24);
      ObjectSetString (0, n3, OBJPROP_TEXT,         "پایان شبکه");
      ObjectSetInteger(0, n3, OBJPROP_COLOR,        clrWhite);
      ObjectSetInteger(0, n3, OBJPROP_BGCOLOR,      clrGray);
      ObjectSetInteger(0, n3, OBJPROP_BORDER_COLOR, clrBlack);
      ObjectSetInteger(0, n3, OBJPROP_FONTSIZE,     8);
      ObjectSetInteger(0, n3, OBJPROP_SELECTABLE,   false);
     }
  }

//+------------------------------------------------------------------+
//| دکمه‌های گسترش (کوچک‌تر)                                       |
//+------------------------------------------------------------------+
void CreateExpansionButtons()
  {

    // string ValBuyExpExtended = buyExpansionCount + "/" + ValBuyExp
   ObjectCreate(0, "LblBuyExp", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "LblBuyExp", OBJPROP_CORNER,    CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, "LblBuyExp", OBJPROP_XDISTANCE, 258);
   ObjectSetInteger(0, "LblBuyExp", OBJPROP_YDISTANCE, 40);
   ObjectSetString (0, "LblBuyExp", OBJPROP_TEXT,      "Buy:");
   ObjectSetInteger(0, "LblBuyExp", OBJPROP_COLOR,     clrWhite);
   ObjectSetInteger(0, "LblBuyExp", OBJPROP_FONTSIZE,  8);

   CreateButton("BtnBuyExpMinus", "-", 218, 36, 20, 20, clrWhite, clrRed, 8);
   ObjectCreate(0, "ValBuyExp", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "ValBuyExp", OBJPROP_CORNER,    CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, "ValBuyExp", OBJPROP_XDISTANCE, 168);
   ObjectSetInteger(0, "ValBuyExp", OBJPROP_YDISTANCE, 40);
   ObjectSetString (0, "ValBuyExp", OBJPROP_TEXT,      "0/" + IntegerToString(g_MaxBuyExpansions));
   ObjectSetInteger(0, "ValBuyExp", OBJPROP_COLOR,     clrYellow);
   ObjectSetInteger(0, "ValBuyExp", OBJPROP_FONTSIZE,  8);
   CreateButton("BtnBuyExpPlus",  "+", 126, 36, 20, 20, clrWhite, clrGreen, 8);

   ObjectCreate(0, "LblSellExp", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "LblSellExp", OBJPROP_CORNER,    CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, "LblSellExp", OBJPROP_XDISTANCE, 258);
   ObjectSetInteger(0, "LblSellExp", OBJPROP_YDISTANCE, 64);
   ObjectSetString (0, "LblSellExp", OBJPROP_TEXT,      "Sell:");
   ObjectSetInteger(0, "LblSellExp", OBJPROP_COLOR,     clrWhite);
   ObjectSetInteger(0, "LblSellExp", OBJPROP_FONTSIZE,  8);

   CreateButton("BtnSellExpMinus", "-", 218, 60, 20, 20, clrWhite, clrRed, 8);
   ObjectCreate(0, "ValSellExp", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "ValSellExp", OBJPROP_CORNER,    CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, "ValSellExp", OBJPROP_XDISTANCE, 168);
   ObjectSetInteger(0, "ValSellExp", OBJPROP_YDISTANCE, 64);
   ObjectSetString (0, "ValSellExp", OBJPROP_TEXT,      "0/" + IntegerToString(g_MaxSellExpansions));
   ObjectSetInteger(0, "ValSellExp", OBJPROP_COLOR,     clrYellow);
   ObjectSetInteger(0, "ValSellExp", OBJPROP_FONTSIZE,  8);
   CreateButton("BtnSellExpPlus",  "+", 126, 60, 20, 20, clrWhite, clrGreen, 8);
  }

//+------------------------------------------------------------------+
void CreateButton(string name, string text, int x, int y,
                  int w, int h, color ct, color cb, int fs)
  {
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER,       CORNER_RIGHT_UPPER);
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
