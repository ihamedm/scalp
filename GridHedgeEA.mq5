//+------------------------------------------------------------------+
//|                                GridHedge_Ultimate_v5.mq5          |
//|               شبکه گرید هوشمند - گسترش با فعال‌شدن سفارش        |
//+------------------------------------------------------------------+
#property copyright "Hamed Movasaqpoor"
#property link      "hamed.movasaqpoor@gmail.com"
#property version   "6.6"

#include <Trade\Trade.mqh>

//------------------------- CAMARILLA RANGE MODES -------------------------
enum CamarillaRangeMode {
   MODE_H1_L1 = 0,    // بین H1 و L1 (محدود)
   MODE_H2_L2 = 1,    // بین H2 و L2 (میانه) ← پیشنهادی
   MODE_H3_L3 = 2,    // بین H3 و L3 (باز)
   MODE_CUSTOM = 3    // دلخواه (اعداد 1-5 را در زیر انتخاب کنید)
};

//------------------------- INPUT PARAMETERS -------------------------
input group "=== تنظیمات کلی ==="
input int    MagicNumber       = 202701;   // شماره جادویی
input int    TesterStartHour      = 1;        // ساعت شروع شبکه در تستر (0-23)


input group "=== تنظیمات سرور (API) ==="
input bool   EnableServerSync   = false;     // فعال‌سازی ارسال/بازیابی اطلاعات از سرور
input string ServerURL          = "http://127.0.0.1:8000";  // آدرس سرور (مثال: http://your-server:8000)
input string UserToken          = "";       // توکن JWT (از داشبورد سرور دریافت کنید)
input int    LogSyncInterval    = 60;       // فاصله زمانی برای ارسال لاگ‌ها (ثانیه)


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
input int    GridLevels        = 1;         // تعداد پله های اولیه
input double GridStep_Points   = 100.0;     // فاصله پله ها (Point)
input double TotalProfitTarget = 40.0;     // هدف سود کل (دلار)
input double TotalStopLoss     = -100.0;    // حد ضرر کل (عدد منفی، دلار)


input group "=== گسترش شبکه ==="
input int    InitialMaxBuyExpansions  = 4;
input int    InitialMaxSellExpansions = 4;
input double ExpansionMinDistanceFactor = 0.8;   // حداقل فاصله از سفارشات موجود (نسبت به فاصله پله ها)
input int    ExpansionMethod       = 1;        //متد گسترش : 0 = فعال‌شدن سفارش | 1 = تغییر قیمت


input group "=== تریلینگ سبد ==="
input bool   UseBasketTrailing   = false;      // فعال‌سازی تریلینگ حد ضرر کل شبکه
input double TrailingActivation  = 5.0;       // سود اولیه برای شروع تریلینگ (دلار)
input double TrailingStep        = 3.0;       // فاصله حد ضرر شناور از اوج سود (دلار)


input group "=== سطوح حمایت و مقاومت  ==="
input bool   EnableCamarillaCheck = false;      // فعال‌سازی محدودیت سطوح 
input double CamarillaDistance    = 50.0;      // حداقل فاصله مجاز از سطوح (Point)
input bool   EnableCamarillaRangeCheck = false; // محدود کردن سفارشات درون بازه سطوح
input CamarillaRangeMode CamarillaRange = MODE_H2_L2;  // حالت بازه: H1-L1, H2-L2, H3-L3, یا دلخواه
input int    CamarillaCustomUpper  = 5;        // سطح بالای دلخواه (فقط اگر MODE_CUSTOM) - 1=H5, 2=H4, 3=H3, 4=H2, 5=H1
input int    CamarillaCustomLower  = 1;        // سطح پایین دلخواه (فقط اگر MODE_CUSTOM) - 1=L5, 2=L4, 3=L3, 4=L2, 5=L1

//------------------------- GLOBAL VARIABLES -------------------------
bool   g_EnableCamarillaCheck = true; // وضعیت قابل تغییر در زمان اجرا
bool   g_EnableCamarillaRangeCheck = true; // محدود کردن سفارشات درون بازه
CamarillaRangeMode g_CamarillaRange = MODE_H2_L2; // متغیر قابل تغییر برای حالت بازه
double g_TrailingActivation = 5.0; // مقدار فعال‌سازی تریلینگ قابل تغییر
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
int    g_GridDirection = -1;     // جهت شبکه جاری (ORDER_TYPE_BUY / ORDER_TYPE_SELL)
int    g_LiveTrendDirection = -1; // جهت زنده برای نمایش و تصمیم قبل از شروع شبکه
datetime g_LastTrendRefreshTime = 0;
int    g_OrderCommentSeq = 0;    // شماره سفارش داخل شبکه جاری
int    g_adxHandle = INVALID_HANDLE;
int    g_rsiHandle = INVALID_HANDLE;

int    g_TrendStrength = 0;   // قدرت روند (0-100)
bool   UseADXFilter        = true;      // فعال‌سازی فیلتر ADX
int    ADX_Period          = 14;        // دوره ADX
double ADX_Threshold       = 22.0;      // حداقل ADX برای روند قوی
bool   UseRSIFilter        = true;      // فعال‌سازی فیلتر RSI
int    RSI_Period          = 14;        // دوره RSI
double RSI_BuyMax          = 65.0;      // حداکثر RSI برای خرید (برای جلوگیری از اشباع خرید)
double RSI_SellMin         = 35.0;      // حداقل RSI برای فروش (برای جلوگیری از اشباع فروش)


// حجم لات قابل تعدیل
double g_CurrentLot = 0.01;      // حجم فعلی لات (جایگزین FixedLot)
double g_LotSteps[] = {0.01, 0.02, 0.03, 0.04, 0.05}; // مراحل تغییر حجم
int    g_CurrentLotIndex = 0;    // فهرس مرحله فعلی


double g_PeakProfit        = 0.0;    // اوج سود شناور (برای تریلینگ)
double g_TrailingStopLevel = 0.0;    // سطح حد ضرر شناور (دلار)
bool   g_TrailingActivated = false;  // آیا تریلینگ فعال شده است؟


//------------- API / Server Sync Variables ---------
datetime g_LastLogSyncTime = 0;  // آخرین زمان ارسال لاگ
string   g_LastStatusMessage = ""; // آخرین پیام وضعیت برای جلوگیری از تکرار

struct CamarillaLevels
  {
   double H5, H4, H3, H2, H1;
   double L1, L2, L3, L4, L5;
   bool   valid;
  };
//------------------------- PERSISTENCE HELPERS ---------------------
string GVarName(string key)
  {
   return "GridHedge~" + _Symbol + "~" + IntegerToString(MagicNumber) + "~" + key;
  }

void SaveState()
  {
  // همیشه وضعیت را ذخیره کن (شامل تنظیمات دکمه‌ها/گسترش) تا تغییر تایم‌فریم آن‌ها را پاک نکند
  GlobalVariableSet(GVarName("inited"), 1.0);
   GlobalVariableSet(GVarName("g_GridInstance"), (double)g_GridInstance);
   GlobalVariableSet(GVarName("g_ActiveMagic"), (double)g_ActiveMagic);
   GlobalVariableSet(GVarName("isTradingActive"), isTradingActive ? 1.0 : 0.0);
   GlobalVariableSet(GVarName("tradingDone"), tradingDone ? 1.0 : 0.0);
   GlobalVariableSet(GVarName("buyExpansionCount"), (double)buyExpansionCount);
   GlobalVariableSet(GVarName("sellExpansionCount"), (double)sellExpansionCount);
   GlobalVariableSet(GVarName("lastBuyPosCount"), (double)lastBuyPosCount);
   GlobalVariableSet(GVarName("lastSellPosCount"), (double)lastSellPosCount);
   GlobalVariableSet(GVarName("lastBuyExpansionPrice"), lastBuyExpansionPrice);
   GlobalVariableSet(GVarName("lastSellExpansionPrice"), lastSellExpansionPrice);
   GlobalVariableSet(GVarName("g_MaxBuyExpansions"), (double)g_MaxBuyExpansions);
   GlobalVariableSet(GVarName("g_MaxSellExpansions"), (double)g_MaxSellExpansions);
   GlobalVariableSet(GVarName("g_ActualGridStep"), g_ActualGridStep);
   GlobalVariableSet(GVarName("g_CurrentLot"), g_CurrentLot);
   GlobalVariableSet(GVarName("g_CurrentLotIndex"), (double)g_CurrentLotIndex);
   GlobalVariableSet(GVarName("g_OrderCommentSeq"), (double)g_OrderCommentSeq);
   GlobalVariableSet(GVarName("EnableCamarillaCheck"), g_EnableCamarillaCheck ? 1.0 : 0.0);
   GlobalVariableSet(GVarName("EnableCamarillaRangeCheck"), g_EnableCamarillaRangeCheck ? 1.0 : 0.0);
   GlobalVariableSet(GVarName("g_CamarillaRange"), (double)g_CamarillaRange);
   GlobalVariableSet(GVarName("TrailingActivation"), g_TrailingActivation);
   Print("📌 EA state saved to GlobalVariables.");
  }

bool LoadState()
  {
   string k = GVarName("inited");
   if(!GlobalVariableCheck(k)) return false;
   g_GridInstance       = (int)GlobalVariableGet(GVarName("g_GridInstance"));
   g_ActiveMagic        = (int)GlobalVariableGet(GVarName("g_ActiveMagic"));
   isTradingActive      = (GlobalVariableGet(GVarName("isTradingActive")) >= 0.5);
   tradingDone          = (GlobalVariableGet(GVarName("tradingDone")) >= 0.5);
   buyExpansionCount    = (int)GlobalVariableGet(GVarName("buyExpansionCount"));
   sellExpansionCount   = (int)GlobalVariableGet(GVarName("sellExpansionCount"));
   lastBuyPosCount      = (int)GlobalVariableGet(GVarName("lastBuyPosCount"));
   lastSellPosCount     = (int)GlobalVariableGet(GVarName("lastSellPosCount"));
   lastBuyExpansionPrice  = GlobalVariableGet(GVarName("lastBuyExpansionPrice"));
   lastSellExpansionPrice = GlobalVariableGet(GVarName("lastSellExpansionPrice"));
   g_MaxBuyExpansions   = (int)GlobalVariableGet(GVarName("g_MaxBuyExpansions"));
   g_MaxSellExpansions  = (int)GlobalVariableGet(GVarName("g_MaxSellExpansions"));
   g_ActualGridStep     = GlobalVariableGet(GVarName("g_ActualGridStep"));
   g_CurrentLot         = GlobalVariableGet(GVarName("g_CurrentLot"));
   g_CurrentLotIndex    = (int)GlobalVariableGet(GVarName("g_CurrentLotIndex"));
   g_OrderCommentSeq    = GlobalVariableCheck(GVarName("g_OrderCommentSeq"))
                          ? (int)GlobalVariableGet(GVarName("g_OrderCommentSeq")) : 0;
   g_EnableCamarillaCheck = GlobalVariableCheck(GVarName("EnableCamarillaCheck"))
                          ? (GlobalVariableGet(GVarName("EnableCamarillaCheck")) >= 0.5)
                          : EnableCamarillaCheck;
   g_EnableCamarillaRangeCheck = GlobalVariableCheck(GVarName("EnableCamarillaRangeCheck"))
                          ? (GlobalVariableGet(GVarName("EnableCamarillaRangeCheck")) >= 0.5)
                          : EnableCamarillaRangeCheck;
   g_CamarillaRange = GlobalVariableCheck(GVarName("g_CamarillaRange"))
                          ? (CamarillaRangeMode)(int)GlobalVariableGet(GVarName("g_CamarillaRange"))
                          : CamarillaRange;
   g_TrailingActivation = GlobalVariableCheck(GVarName("TrailingActivation"))
                          ? GlobalVariableGet(GVarName("TrailingActivation"))
                          : TrailingActivation;

  // بازسازی g_CurrentLot بر اساس شاخص ذخیره شده
   if(g_CurrentLotIndex >= 0 && g_CurrentLotIndex < ArraySize(g_LotSteps))
      g_CurrentLot = g_LotSteps[g_CurrentLotIndex];
   else
     {
      g_CurrentLotIndex = 0;
      g_CurrentLot = g_LotSteps[0];
      Print("⚠️ شاخص لات نامعتبر، ریست شد.");
     }

   g_GridID = "شبکه " + IntegerToString(g_GridInstance + 1);

   Print("📌 EA state loaded from GlobalVariables.");
   return true;
  }

void ClearState()
  {
   string prefix = "GridHedge~" + _Symbol + "~" + IntegerToString(MagicNumber) + "~";
   string names[] = {"inited","g_GridInstance","g_ActiveMagic","isTradingActive","tradingDone","buyExpansionCount","sellExpansionCount","lastBuyPosCount","lastSellPosCount","lastBuyExpansionPrice","lastSellExpansionPrice","g_MaxBuyExpansions","g_MaxSellExpansions","g_ActualGridStep","g_CurrentLot","g_CurrentLotIndex","g_OrderCommentSeq","EnableCamarillaCheck","EnableCamarillaRangeCheck","g_CamarillaRange"};
   for(int i=0;i<ArraySize(names);i++) GlobalVariableDel(prefix + names[i]);
   Print("📌 Cleared persisted EA state.");
  }

void PrepareGridCommentContext()
  {
   g_GridID = "شبکه " + IntegerToString(g_GridInstance + 1);
   g_OrderCommentSeq = 0;
  }

string BuildOrderComment(string role, int &nextSeq)
  {
  if(g_GridID == "")
    g_GridID = "شبکه " + IntegerToString(g_GridInstance + 1);

  nextSeq = g_OrderCommentSeq + 1;
  return g_GridID + " " + role + " #" + IntegerToString(nextSeq);
  }


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
   return g_CurrentLot;
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

double NormalizePriceToTick(double price)
  {
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0) tickSize = _Point;
   return NormalizeDouble(MathRound(price / tickSize) * tickSize, digits);
  }

double ProtectionPriceFromEntry(double entry, double points, bool isSL, bool isBuy)
  {
   if(points <= 0) return 0;
   return NormalizePriceToTick(PointToPrice(entry, points, isSL, isBuy));
  }

bool ModifyPositionProtection(ulong ticket, double sl, double tp)
  {
   MqlTradeRequest req = {};
   MqlTradeResult  res = {};
   req.action   = TRADE_ACTION_SLTP;
   req.position = ticket;
   req.symbol   = _Symbol;
   req.sl       = (sl > 0) ? NormalizePriceToTick(sl) : 0;
   req.tp       = (tp > 0) ? NormalizePriceToTick(tp) : 0;
   req.magic    = g_ActiveMagic;

   if(!OrderSend(req, res))
     {
      PrintFormat("❌ اصلاح TP/SL پوزیشن ناموفق: ticket=%I64u err=%d retcode=%d",
                  ticket, GetLastError(), res.retcode);
      return false;
     }
   return true;
  }

bool SelectPositionByTicketOrIdentifier(ulong positionId)
  {
   if(PositionSelectByTicket(positionId))
      return true;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(ticket == positionId || (ulong)PositionGetInteger(POSITION_IDENTIFIER) == positionId)
         return true;
     }

   return false;
  }

void SyncPositionProtectionToOpenPrice(ulong positionTicket)
  {
   if(!SelectPositionByTicketOrIdentifier(positionTicket)) return;
   if(PositionGetInteger(POSITION_MAGIC) != g_ActiveMagic) return;
   if(PositionGetString(POSITION_SYMBOL) != _Symbol) return;

   ulong ticket = (ulong)PositionGetInteger(POSITION_TICKET);
   long posType = PositionGetInteger(POSITION_TYPE);
   bool isBuy = (posType == POSITION_TYPE_BUY);
   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl = (SL_Points > 0) ? ProtectionPriceFromEntry(openPrice, SL_Points, true, isBuy)
                               : PositionGetDouble(POSITION_SL);
   double tp = (TP_Points > 0) ? ProtectionPriceFromEntry(openPrice, TP_Points, false, isBuy)
                               : PositionGetDouble(POSITION_TP);

   double currentSL = PositionGetDouble(POSITION_SL);
   double currentTP = PositionGetDouble(POSITION_TP);
   if(MathAbs(currentSL - sl) < (_Point / 2.0) && MathAbs(currentTP - tp) < (_Point / 2.0))
      return;

   if(ModifyPositionProtection(ticket, sl, tp))
      PrintFormat("✅ TP/SL بر اساس قیمت ورود واقعی اصلاح شد | ticket=%I64u open=%.5f SL=%.5f TP=%.5f",
                  ticket, openPrice, sl, tp);
  }

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
  {
   // تلاش برای بارگذاری وضعیت قبلی (مثلاً پس از تغییر تایم‌فریم)
   bool stateLoaded = LoadState();
   if(stateLoaded)
     {
      // به‌روزرسانی پارامترهایی که به‌صورت پویا باید مطابق ورودی جدید باشند
      g_ActualGridStep = GridStep_Points * _Point;
      PrintSymbolInfo();
      Print("🔁 حالت قبلی بارگذاری شد؛ مقدارها ریست نشدند.");
      // اگر LoadState موفق باشد، اما g_TrailingActivation بارگذاری نشود
      if(g_TrailingActivation <= 0)
        g_TrailingActivation = TrailingActivation;
     }
   else
     {
      tradingDone         = false;
      g_MaxBuyExpansions  = InitialMaxBuyExpansions;
      g_MaxSellExpansions = InitialMaxSellExpansions;
      g_ActualGridStep    = GridStep_Points * _Point;
      g_GridInstance      = 0;
      g_ActiveMagic       = MagicNumber + g_GridInstance;

      // هماهنگ‌سازی حجم اولیه با FixedLot ورودی
      g_CurrentLot = FixedLot;
      g_CurrentLotIndex = 0;
      for(int i = 0; i < ArraySize(g_LotSteps); i++)
        {
         if(MathAbs(g_LotSteps[i] - FixedLot) < 0.0001)
           {
            g_CurrentLotIndex = i;
            break;
           }
        } 
      g_EnableCamarillaCheck = EnableCamarillaCheck;
      g_EnableCamarillaRangeCheck = EnableCamarillaRangeCheck;
      g_CamarillaRange = CamarillaRange;
      g_TrailingActivation = TrailingActivation;
    }

   if(UseADXFilter)
     {
      g_adxHandle = iADX(_Symbol, PERIOD_CURRENT, ADX_Period);
      if(g_adxHandle == INVALID_HANDLE)
         Print("⚠️ خطا در ایجاد هندل ADX");
     }

   if(UseRSIFilter)
     {
      g_rsiHandle = iRSI(_Symbol, PERIOD_CURRENT, RSI_Period, PRICE_CLOSE);
      if(g_rsiHandle == INVALID_HANDLE)
         Print("⚠️ خطا در ایجاد هندل RSI");
     }


    // ShowCamarillaLevelsOnChart();

    bool isTester = (bool)MQLInfoInteger(MQL_TESTER);
   if(isTester)
    DeleteAllOrdersAndPositions();

   if(!isTester)
     {
      CreateCloseButtons();        // «بستن سودده»، «بستن همه»، «پایان شبکه»
      CreateExpansionButtons();    // دکمه‌های ± خرید و فروش
      CreateLotButtons();
      CreateStartButton();         // «شروع شبکه»

      bool gridExists = AnyGridExists();
      if(gridExists && !tradingDone)
        {
         isTradingActive = true;
         Print("🔁 شبکه فعال قبلی پیدا شد؛ موتور گسترش دوباره فعال شد.");
        }
      else if(!gridExists)
        {
         isTradingActive = false;
        }

      UpdateExpansionLabels();
      UpdateLotLabel();
      UpdateChartComment();

      if(!isTradingActive)
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
   // قبل از پاک‌سازی رابط، وضعیت را ذخیره کن تا تغییر تایم‌فریم باعث ریست تنظیمات نشود
   SaveState();

   if(g_adxHandle != INVALID_HANDLE) IndicatorRelease(g_adxHandle);
   if(g_rsiHandle != INVALID_HANDLE) IndicatorRelease(g_rsiHandle);

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
   ObjectDelete(0, "LblLot");
   ObjectDelete(0, "ValLot");
   ObjectDelete(0, "BtnLotMinus");
   ObjectDelete(0, "BtnLotPlus");
   ObjectDelete(0, "BtnToggleCamarilla");
   ObjectDelete(0, "LblCamarilla");
   ObjectDelete(0, "ValCamarilla");
   ObjectDelete(0, "BtnToggleCamarillaRange");
   ObjectDelete(0, "ValCamarillaRange");
   ObjectDelete(0, "BtnEnableCamarillaRange");
   ObjectDelete(0, "ValRangeEnabled");
   ObjectDelete(0, "BtnTrailingActivationPlus");
   ObjectDelete(0, "BtnTrailingActivationMinus");
   ObjectDelete(0, "ValTrailingActivation");
   ObjectDelete(0, "LblTrailingActivation");
   Comment("");

   ObjectsDeleteAll(0, "Camarilla_");
   
  }

//+------------------------------------------------------------------+
//| اصلاح TP/SL بعد از تبدیل سفارش معلق به پوزیشن                  |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || trans.deal == 0)
      return;

   if(!HistoryDealSelect(trans.deal))
      return;

   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != g_ActiveMagic)
      return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol)
      return;
   if(HistoryDealGetInteger(trans.deal, DEAL_ENTRY) != DEAL_ENTRY_IN)
      return;

   long dealType = HistoryDealGetInteger(trans.deal, DEAL_TYPE);
   if(dealType != DEAL_TYPE_BUY && dealType != DEAL_TYPE_SELL)
      return;

   ulong positionTicket = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
   if(positionTicket > 0)
      SyncPositionProtectionToOpenPrice(positionTicket);
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

      if(MQLInfoInteger(MQL_TESTER))
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

   if(!isTradingActive || tradingDone)
     {
      UpdateChartComment();
      return;
     }

   // ارسال لاگ پوریدی وضعیت تریدینگ
   if(TimeCurrent() - g_LastLogSyncTime >= LogSyncInterval)
     {
      int buyCount = CountPositionsByType(POSITION_TYPE_BUY);
      int sellCount = CountPositionsByType(POSITION_TYPE_SELL);
      double profit = CalculateTotalProfit();
      
      string statusMsg = StringFormat("Grid Active: %d Buy, %d Sell | Profit: %.2f USD | Lot: %.2f",
                                      buyCount, sellCount, profit, g_CurrentLot);
      if(statusMsg != g_LastStatusMessage)
        {
         SendLogToServer("INFO", statusMsg);
         g_LastStatusMessage = statusMsg;
        }
      g_LastLogSyncTime = TimeCurrent();
     }

   // گسترش شبکه بر اساس روش انتخاب‌شده
   if(ExpansionMethod == 0)
     {
      int currentBuy  = CountPositionsByType(POSITION_TYPE_BUY);
      int currentSell = CountPositionsByType(POSITION_TYPE_SELL);

      PrintFormat("🔍 Method0 | currentBuy: %d, lastBuyPosCount: %d | currentSell: %d, lastSellPosCount: %d",
                  currentBuy, lastBuyPosCount, currentSell, lastSellPosCount);

      if(currentBuy > lastBuyPosCount)
        {
         string msg = "فعال‌شدن سفارش خرید";
         TryBuyExpansion(msg);
         SendLogToServer("INFO", msg);
         lastBuyPosCount = currentBuy;
        }

      if(currentSell > lastSellPosCount)
        {
         string msg = "فعال‌شدن سفارش فروش";
         TrySellExpansion(msg);
         SendLogToServer("INFO", msg);
         lastSellPosCount = currentSell;
        }

      // اگر قیمت از سقف/کف جدید برگشت کند، سمت مخالف هم نزدیک کندل دوباره ساخته شود.
      ProcessPriceMovementExpansion();
     }
   else // ExpansionMethod == 1 (بر اساس تغییر قیمت)
     {
      ProcessPriceMovementExpansion();
     }
  UpdateChartComment(); 

  if(UseBasketTrailing)
    CheckBasketTrailingStop();
  else
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
      g_MaxBuyExpansions = MathMin(g_MaxBuyExpansions + 1, 1000);
      UpdateExpansionLabels();
      SaveState();
      Print("MaxBuyExpansions → ", g_MaxBuyExpansions);
     }
   else if(sparam == "BtnBuyExpPlus50")
     {
      g_MaxBuyExpansions = MathMin(g_MaxBuyExpansions + 50, 1000);
      UpdateExpansionLabels();
      SaveState();
      Print("MaxBuyExpansions → ", g_MaxBuyExpansions);
     }
   else if(sparam == "BtnBuyExpZero")
     {
      g_MaxBuyExpansions = 0;
      UpdateExpansionLabels();
      SaveState();
      Print("MaxBuyExpansions → ", g_MaxBuyExpansions);
     }
   else if(sparam == "BtnBuyExpMinus")
     {
      g_MaxBuyExpansions = MathMax(g_MaxBuyExpansions - 1, 0);
      UpdateExpansionLabels();
      SaveState();
      Print("MaxBuyExpansions → ", g_MaxBuyExpansions);
     }
   else if(sparam == "BtnSellExpPlus")
     {
      g_MaxSellExpansions = MathMin(g_MaxSellExpansions + 1, 1000);
      UpdateExpansionLabels();
      SaveState();
      Print("MaxSellExpansions → ", g_MaxSellExpansions);
     }
   else if(sparam == "BtnSellExpPlus50")
     {
      g_MaxSellExpansions = MathMin(g_MaxSellExpansions + 50, 1000);
      UpdateExpansionLabels();
      SaveState();
      Print("MaxSellExpansions → ", g_MaxSellExpansions);
     }
   else if(sparam == "BtnSellExpZero")
     {
      g_MaxSellExpansions = 0;
      UpdateExpansionLabels();
      SaveState();
      Print("MaxSellExpansions → ", g_MaxSellExpansions);
     }
   else if(sparam == "BtnSellExpMinus")
     {
      g_MaxSellExpansions = MathMax(g_MaxSellExpansions - 1, 0);
      UpdateExpansionLabels();
      SaveState();
      Print("MaxSellExpansions → ", g_MaxSellExpansions);
     }

  else if(sparam == "BtnLotPlus")
     {
      if(g_CurrentLotIndex + 1 < ArraySize(g_LotSteps))
        {
         g_CurrentLotIndex++;
         g_CurrentLot = g_LotSteps[g_CurrentLotIndex];
         UpdateLotLabel();
         SaveState();
         UpdateParamOnServer("LotSize", g_CurrentLot);
         SendLogToServer("INFO", "Lot Size increased to: " + DoubleToString(g_CurrentLot, 3));
         Print("حجم جدید: ", DoubleToString(g_CurrentLot, 3));
        }
      else Print("حداکثر حجم مجاز رسیده است.");
      return;
     }
   else if(sparam == "BtnToggleCamarilla")
     {
      g_EnableCamarillaCheck = !g_EnableCamarillaCheck;
      UpdateCamarillaLabel();
      PrintFormat("EnableCamarillaCheck → %s", g_EnableCamarillaCheck ? "true" : "false");
      return;
     }
   else if(sparam == "BtnToggleCamarillaRange")
     {
      // Cycle through range modes: H1-L1 → H2-L2 → H3-L3 → CUSTOM
      if(g_CamarillaRange == MODE_H1_L1)
        {
         g_CamarillaRange = MODE_H2_L2;
         Print("🔄 بازه تغییر یافت: H2-L2");
        }
      else if(g_CamarillaRange == MODE_H2_L2)
        {
         g_CamarillaRange = MODE_H3_L3;
         Print("🔄 بازه تغییر یافت: H3-L3");
        }
      else if(g_CamarillaRange == MODE_H3_L3)
        {
         g_CamarillaRange = MODE_CUSTOM;
         PrintFormat("🔄 بازه تغییر یافت: CUSTOM (%d-%d)", CamarillaCustomUpper, CamarillaCustomLower);
        }
      else // MODE_CUSTOM
        {
         g_CamarillaRange = MODE_H1_L1;
         Print("🔄 بازه تغییر یافت: H1-L1");
        }
      UpdateCamarillaLabel();
      return;
     }
   else if(sparam == "BtnEnableCamarillaRange")
     {
      g_EnableCamarillaRangeCheck = !g_EnableCamarillaRangeCheck;
      ObjectSetString(0, "ValRangeEnabled", OBJPROP_TEXT, g_EnableCamarillaRangeCheck ? "ON" : "OFF");
      ObjectSetInteger(0, "ValRangeEnabled", OBJPROP_COLOR, g_EnableCamarillaRangeCheck ? clrLime : clrRed);
      PrintFormat("✓ Range Check → %s", g_EnableCamarillaRangeCheck ? "ON" : "OFF");
      return;
     }
   else if(sparam == "BtnTrailingActivationPlus")
     {
      g_TrailingActivation += 1.0;
      ObjectSetString(0, "ValTrailingActivation", OBJPROP_TEXT, DoubleToString(g_TrailingActivation, 2));
      SaveState();
      PrintFormat("TrailingActivation → %.2f USD", g_TrailingActivation);
      return;
     }
   else if(sparam == "BtnTrailingActivationMinus")
     {
      g_TrailingActivation = MathMax(g_TrailingActivation - 1.0, 0.1);
      ObjectSetString(0, "ValTrailingActivation", OBJPROP_TEXT, DoubleToString(g_TrailingActivation, 2));
      SaveState();
      PrintFormat("TrailingActivation → %.2f USD", g_TrailingActivation);
      return;
     }
   else if(sparam == "BtnLotMinus")
     {
      if(g_CurrentLotIndex - 1 >= 0)
        {
         g_CurrentLotIndex--;
         g_CurrentLot = g_LotSteps[g_CurrentLotIndex];
         UpdateLotLabel();
         SaveState();
         UpdateParamOnServer("LotSize", g_CurrentLot);
         SendLogToServer("INFO", "Lot Size decreased to: " + DoubleToString(g_CurrentLot, 3));
         Print("حجم جدید: ", DoubleToString(g_CurrentLot, 3));
        }
      else Print("حداقل حجم مجاز رسیده است.");
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
      SendLogToServer("WARNING", "Grid start attempted but already active");
      return;
     }
   Print("▶ ایجاد شبکه جدید...");
   
   // ارسال لاگ شروع شبکه و پارامترهای اولیه
   string gridInfo = StringFormat("Grid started | Symbol: %s | LotSize: %.3f | GridStep: %.2f | Levels: %d",
                                  _Symbol, g_CurrentLot, GridStep_Points, GridLevels);
   SendLogToServer("INFO", gridInfo);
   UpdateParamOnServer("GridActive", 1.0);
   UpdateParamOnServer("LotSize", g_CurrentLot);
   
   isTradingActive = true;
   tradingDone     = false;

   ResetTrailingState();
   ExecuteStrategy();
   SaveState();
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
   PrepareGridCommentContext();
   ResetTrailingState();

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
      g_GridDirection = direction;
      double sl = (SL_Points > 0) ? PointToPrice(ask, SL_Points, true,  true) : 0;
      double tp = (TP_Points > 0) ? PointToPrice(ask, TP_Points, false, true) : 0;
      PlaceInitialLimit(ORDER_TYPE_BUY, g_CurrentLot, sl, tp, "اولیه");
     }
   else
     {
      g_GridDirection = direction;
      double sl = (SL_Points > 0) ? PointToPrice(bid, SL_Points, true,  false) : 0;
      double tp = (TP_Points > 0) ? PointToPrice(bid, TP_Points, false, false) : 0;
      PlaceInitialLimit(ORDER_TYPE_SELL, g_CurrentLot, sl, tp, "اولیه");
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


  void ResetTrailingState()
  {
   g_PeakProfit        = 0.0;
   g_TrailingStopLevel = TotalStopLoss;   // سطح اولیه = حد ضرر اصلی (عددی منفی)
   g_TrailingActivated = false;
  }


//+------------------------------------------------------------------+
//| تشخیص روند - چند کندل + شیب EMA                                |
//+------------------------------------------------------------------+
int DetectTrendFromEMA(bool printLog = true)
  {
   g_TrendStrength = 0;
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

   int direction = -1;
   if(bullish && slopeUp)   direction = ORDER_TYPE_BUY;
   else if(bearish && slopeDown) direction = ORDER_TYPE_SELL;
   else
     {
      // بازار رنج – تصمیم ساده
      direction = (cls[0] > ema[0]) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
     }

   // ---- ADX Filter ----
   double adxVal = 0;
   bool adxOk = true;
   if(UseADXFilter && g_adxHandle != INVALID_HANDLE)
     {
      double adx[];
      ArraySetAsSeries(adx, true);
      if(CopyBuffer(g_adxHandle, 0, 0, 1, adx) == 1)
        {
         adxVal = adx[0];
         if(adxVal < ADX_Threshold)
            adxOk = false;
        }
     }

   // ---- RSI Filter ----
   double rsiVal = 50.0;
   bool rsiOk = true;
   if(UseRSIFilter && g_rsiHandle != INVALID_HANDLE)
     {
      double rsi[];
      ArraySetAsSeries(rsi, true);
      if(CopyBuffer(g_rsiHandle, 0, 0, 1, rsi) == 1)
        {
         rsiVal = rsi[0];
         if(direction == ORDER_TYPE_BUY && rsiVal > RSI_BuyMax)
            rsiOk = false;
         else if(direction == ORDER_TYPE_SELL && rsiVal < RSI_SellMin)
            rsiOk = false;
        }
     }

   // محاسبه قدرت کلی (0-100)
   int strength = 50; // پایه
   if(bullish && slopeUp) strength += 20; else if(!bullish || !slopeUp) strength -= 10;
   if(adxOk) strength += 20; else strength -= 20;
   if(rsiOk) strength += 10; else strength -= 10;
   strength = MathMax(0, MathMin(100, strength));
   g_TrendStrength = strength;

   if(printLog)
      PrintFormat("🧭 تشخیص روند: %s (قدرت: %d%%) | ADX=%.2f (آستانه=%.2f) | RSI=%.2f",
                  direction == ORDER_TYPE_BUY ? "خرید" : (direction == ORDER_TYPE_SELL ? "فروش" : "نامشخص"),
                  strength, adxVal, ADX_Threshold, rsiVal);

   return direction;
  }

//+------------------------------------------------------------------+
//| به‌روزرسانی جهت زنده برای نمایش قبل از شروع شبکه                |
//+------------------------------------------------------------------+
int RefreshLiveTrendDirection(bool force = false)
  {
   datetime now = TimeCurrent();
   if(!force && g_LiveTrendDirection != -1 && (now - g_LastTrendRefreshTime) < 10)
      return g_LiveTrendDirection;

   int direction = DetectTrendFromEMA(false);
   if(direction == ORDER_TYPE_BUY || direction == ORDER_TYPE_SELL)
     {
      g_LiveTrendDirection = direction;
      g_LastTrendRefreshTime = now;
     }

   return g_LiveTrendDirection;
  }

//+------------------------------------------------------------------+
//| Limit Order اولیه                                                |
//+------------------------------------------------------------------+
bool PlaceInitialLimit(ENUM_ORDER_TYPE type, double lot, double sl, double tp, string comment)
  {
   Sleep(30);
   double halfStep = (GridStep_Points / 2.0) * _Point;
   double price = (type == ORDER_TYPE_BUY)
                  ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) - halfStep
                  : SymbolInfoDouble(_Symbol, SYMBOL_BID) + halfStep;
   price = NormalizePriceToTick(price);
   bool isBuy = (type == ORDER_TYPE_BUY);
   
   // بررسی بازه سطوح کاماریلا
   if(!IsPriceWithinCamarillaRange(price))
     {
      PrintFormat("⛔ سفارش اولیه ایجاد نشد - قیمت خارج از بازه: %.5f", price);
      return false;
     }
   
   sl = (SL_Points > 0) ? ProtectionPriceFromEntry(price, SL_Points, true, isBuy) : 0;
   tp = (TP_Points > 0) ? ProtectionPriceFromEntry(price, TP_Points, false, isBuy) : 0;

   // proximity check using dynamic factor
   ENUM_ORDER_TYPE checkType = (type == ORDER_TYPE_BUY) ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT;
   if(IsTooCloseToExisting(price, checkType))
     {
      PrintFormat("⛔ جلوگیری از ثبت Limit اولیه - خیلی نزدیک به سفارش/پوزیشن موجود (price=%.5f)", price);
      return false;
     }

   long   stopsLvl  = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long   freezeLvl = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double minDist   = (stopsLvl + freezeLvl + 2) * _Point;

   if(type == ORDER_TYPE_BUY)
     {
      if(sl > 0 && (price - sl) < minDist) sl = NormalizePriceToTick(price - minDist);
      if(tp > 0 && (tp - price) < minDist) tp = NormalizePriceToTick(price + minDist);
     }
   else
     {
      if(sl > 0 && (sl - price) < minDist) sl = NormalizePriceToTick(price + minDist);
      if(tp > 0 && (price - tp) < minDist) tp = NormalizePriceToTick(price - minDist);
     }

   MqlTradeRequest req = {};
   MqlTradeResult  res = {};
   int commentSeq = 0;
   string orderComment = BuildOrderComment(comment, commentSeq);
   req.action       = TRADE_ACTION_PENDING;
   req.symbol       = _Symbol;
   req.volume       = lot;
   req.price        = price;
   req.type         = (type == ORDER_TYPE_BUY) ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT;
   req.sl           = sl;
   req.tp           = tp;
   req.magic        = g_ActiveMagic;
   req.comment      = orderComment;
   req.type_filling = ORDER_FILLING_RETURN;
   req.type_time    = ORDER_TIME_GTC;

   if(!OrderSend(req, res))
     {
      PrintFormat("❌ Limit خطا: err=%d retcode=%d", GetLastError(), res.retcode);
      return false;
     }
   g_OrderCommentSeq = commentSeq;
   PrintFormat("✅ %s | Price=%.5f | SL=%.5f | TP=%.5f | Lot=%.2f",
               orderComment, price, sl, tp, lot);
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

   // ثبت فقط سفارش‌های هم‌جهت با جهت اولیه شبکه
   // لاحظ: سفارش اولیه (Initial Limit) قبلاً برای پله ۱ ثبت شده است
   // بنابراین سفارش‌های گرید اضافی باید از پله ۲ شروع شوند
   if(g_GridDirection == ORDER_TYPE_BUY)
     {
      for(int i = 2; i <= GridLevels; i++)
        {
         double entry = ask + i * step;
         if(entry - ask < minDist) entry = ask + minDist;
         double lot = CalcLot(SL_Points);
         double sl  = (SL_Points > 0) ? PointToPrice(entry, SL_Points, true,  true) : 0;
         double tp  = (TP_Points > 0) ? PointToPrice(entry, TP_Points, false, true) : 0;
         PlacePendingOrder(ORDER_TYPE_BUY_STOP, lot, entry, sl, tp, "خرید");
        }
     }
   else if(g_GridDirection == ORDER_TYPE_SELL)
     {
      for(int i = 2; i <= GridLevels; i++)
        {
         double entry = bid - i * step;
         if(bid - entry < minDist) entry = bid - minDist;
         double lot = CalcLot(SL_Points);
         double sl  = (SL_Points > 0) ? PointToPrice(entry, SL_Points, true,  false) : 0;
         double tp  = (TP_Points > 0) ? PointToPrice(entry, TP_Points, false, false) : 0;
         PlacePendingOrder(ORDER_TYPE_SELL_STOP, lot, entry, sl, tp, "فروش");
        }
     }
   else
     {
      // اگر جهت مشخص نشده بود، رفتار قدیمی: هر دو سمت را ثبت کن (از پله ۲)
      for(int i = 2; i <= GridLevels; i++)
        {
         double entry = ask + i * step;
         if(entry - ask < minDist) entry = ask + minDist;
         double lot = CalcLot(SL_Points);
         double sl  = (SL_Points > 0) ? PointToPrice(entry, SL_Points, true,  true) : 0;
         double tp  = (TP_Points > 0) ? PointToPrice(entry, TP_Points, false, true) : 0;
         PlacePendingOrder(ORDER_TYPE_BUY_STOP, lot, entry, sl, tp, "خرید");
        }
      for(int i = 2; i <= GridLevels; i++)
        {
         double entry = bid - i * step;
         if(bid - entry < minDist) entry = bid - minDist;
         double lot = CalcLot(SL_Points);
         double sl  = (SL_Points > 0) ? PointToPrice(entry, SL_Points, true,  false) : 0;
         double tp  = (TP_Points > 0) ? PointToPrice(entry, TP_Points, false, false) : 0;
         PlacePendingOrder(ORDER_TYPE_SELL_STOP, lot, entry, sl, tp, "فروش");
        }
     }
   Print("✅ شبکه اولیه ثبت شد.");
  }

//+------------------------------------------------------------------+
//| ثبت سفارش معلق                                                  |
//+------------------------------------------------------------------+
bool PlacePendingOrder(ENUM_ORDER_TYPE type, double lot, double entry,
                       double sl, double tp, string comment){
   Sleep(30);
   entry = NormalizePriceToTick(entry);
   bool isBuy = (type == ORDER_TYPE_BUY_STOP || type == ORDER_TYPE_BUY_LIMIT);
   sl = (SL_Points > 0) ? ProtectionPriceFromEntry(entry, SL_Points, true, isBuy) : 0;
   tp = (TP_Points > 0) ? ProtectionPriceFromEntry(entry, TP_Points, false, isBuy) : 0;

   // proximity check before placing pending order
   if(IsTooCloseToExisting(entry, type))
     {
      PrintFormat("⛔ جلوگیری از ثبت سفارش معلق '%s' - خیلی نزدیک به سفارش/پوزیشن موجود (entry=%.5f)", comment, entry);
      return false;
     }
   
   // بررسی بازه سطوح کاماریلا برای سفارش معلق
   if(!IsPriceWithinCamarillaRange(entry))
     {
      PrintFormat("⛔ سفارش معلق '%s' ایجاد نشد - قیمت خارج از بازه: %.5f", comment, entry);
      return false;
     }

   MqlTradeRequest req = {};
   MqlTradeResult  res = {};
   int commentSeq = 0;
   string orderComment = BuildOrderComment(comment, commentSeq);
   req.action       = TRADE_ACTION_PENDING;
   req.symbol       = _Symbol;
   req.volume       = lot;
   req.price        = entry;
   req.type         = type;
   req.sl           = sl;
   req.tp           = tp;
   req.magic        = g_ActiveMagic;
   req.comment      = orderComment;
   req.type_filling = ORDER_FILLING_RETURN;
   req.type_time    = ORDER_TIME_GTC;

   if(!OrderSend(req, res))
     {
      PrintFormat("❌ OrderSend خطا: err=%d retcode=%d comment=%s", GetLastError(), res.retcode, comment);
      return false;
     }
   g_OrderCommentSeq = commentSeq;
   PrintFormat("✅ %s | Entry=%.5f | SL=%.5f | TP=%.5f | Lot=%.2f",
               orderComment, entry, sl, tp, lot);
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
   SaveState();
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
   SaveState();
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
//| بررسی فاصله از نزدیک‌ترین سفارش معلق یا پوزیشن باز (هم‌جهت)       |
//+------------------------------------------------------------------+
bool IsTooCloseToExisting(double price, ENUM_ORDER_TYPE orderType)
  {
   double minDistPoints = GridStep_Points * ExpansionMinDistanceFactor;
   double minDistPrice = minDistPoints * _Point;
   
   // 1. بررسی سفارشات معلق هم‌نوع
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(!OrderSelect(ticket)) continue;
      if(OrderGetInteger(ORDER_MAGIC) != g_ActiveMagic) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if(OrderGetInteger(ORDER_TYPE) != orderType) continue;
      
      double existingPrice = OrderGetDouble(ORDER_PRICE_OPEN);
      if(MathAbs(price - existingPrice) < minDistPrice)
        {
         PrintFormat("❌ سفارش جدید %.5f بیش از حد به سفارش موجود %.5f نزدیک است (فاصله %.1f پیپ، حداقل مجاز %.1f پیپ)",
                     price, existingPrice, MathAbs(price - existingPrice)/_Point, minDistPoints);
         return true;
        }
     }
   
   // 2. بررسی پوزیشن‌های باز هم‌جهت (برای احتیاط بیشتر)
   long posType = (orderType == ORDER_TYPE_BUY_STOP) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != g_ActiveMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_TYPE) != posType) continue;
      
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      if(MathAbs(price - openPrice) < minDistPrice)
        {
         PrintFormat("❌ سفارش جدید %.5f بیش از حد به پوزیشن باز %.5f نزدیک است (فاصله %.1f پیپ، حداقل مجاز %.1f پیپ)",
                     price, openPrice, MathAbs(price - openPrice)/_Point, minDistPoints);
         return true;
        }
     }
   
   return false;
  }

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

  if(IsNearCamarillaLevel(candidate, CamarillaDistance))
  {
   Print("🔧 BuyAdjustment | به دلیل نزدیکی به سطح کاماریلا، سفارش جدید ایجاد نشد.");
   return false;
  }

  if(IsTooCloseToExisting(candidate, ORDER_TYPE_BUY_STOP))
  {
   Print("🔧 BuyAdjustment | به دلیل فاصله کم، سفارش جدید ایجاد نشد.");
   return false;
  }

   // ثبت سفارش
   double lot = CalcLot(SL_Points);
   double sl  = (SL_Points > 0) ? PointToPrice(candidate, SL_Points, true,  true) : 0;
   double tp  = (TP_Points > 0) ? PointToPrice(candidate, TP_Points, false, true) : 0;
   if(PlacePendingOrder(ORDER_TYPE_BUY_STOP, lot, candidate, sl, tp, "خرید"))
     {
      Print("🔧 BuyAdjustment | سفارش جدید ثبت شد.");
      return true;
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

  if(IsNearCamarillaLevel(candidate, CamarillaDistance))
  {
   Print("🔧 SellAdjustment | به دلیل نزدیکی به سطح کاماریلا، سفارش جدید ایجاد نشد.");
   return false;
  }

   if(IsTooCloseToExisting(candidate, ORDER_TYPE_SELL_STOP))
  {
   Print("🔧 SellAdjustment | به دلیل فاصله کم، سفارش جدید ایجاد نشد.");
   return false;
  }
  
  // ثبت سفارش
   double lot = CalcLot(SL_Points);
   double sl  = (SL_Points > 0) ? PointToPrice(candidate, SL_Points, true,  false) : 0;
   double tp  = (TP_Points > 0) ? PointToPrice(candidate, TP_Points, false, false) : 0;
   if(PlacePendingOrder(ORDER_TYPE_SELL_STOP, lot, candidate, sl, tp, "فروش"))
     {
      Print("🔧 SellAdjustment | سفارش جدید ثبت شد.");
      return true;
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
      int oldMagic = g_ActiveMagic;
      PrintFormat("✅ هدف سود کل برآورده شد: %.2f$", totalProfit);
      CloseAll();
      g_GridInstance++;
      g_ActiveMagic = MagicNumber + g_GridInstance;
      buyExpansionCount  = 0;
      sellExpansionCount = 0;
      lastBuyPosCount    = 0;
      lastSellPosCount   = 0;
      g_OrderCommentSeq  = 0;
      g_GridID           = "";
      tradingDone = true;
      isTradingActive = false;
      ClearState();
      SaveState();
      PrintFormat("شبکه با Magic=%d بسته شد. Magic جدید=%d آماده‌ی شروع.", oldMagic, g_ActiveMagic);
     }
   else if(totalProfit <= TotalStopLoss)
     {
      int oldMagic = g_ActiveMagic;
      PrintFormat("🛑 حد ضرر کل فعال شد: %.2f$", totalProfit);
      CloseAll();
      g_GridInstance++;
      g_ActiveMagic = MagicNumber + g_GridInstance;
      buyExpansionCount  = 0;
      sellExpansionCount = 0;
      lastBuyPosCount    = 0;
      lastSellPosCount   = 0;
      g_OrderCommentSeq  = 0;
      g_GridID           = "";
      tradingDone = true;
      isTradingActive = false;
      ClearState();
      SaveState();
      PrintFormat("شبکه با Magic=%d بسته شد. Magic جدید=%d آماده‌ی شروع.", oldMagic, g_ActiveMagic);
     }

     ResetTrailingState();
  }


  void CheckBasketTrailingStop()
  {
   if(!UseBasketTrailing) return;
   if(!isTradingActive || tradingDone) return;

   double profit = CalculateTotalProfit();

   // اگر تریلینگ هنوز فعال نشده و سود به آستانه رسید
   if(!g_TrailingActivated)
     {
      if(profit >= g_TrailingActivation)
        {
         g_TrailingActivated = true;
         g_PeakProfit = profit;
         g_TrailingStopLevel = g_PeakProfit - TrailingStep;
         PrintFormat("🟢 تریلینگ سبد فعال شد | سود فعلی: %.2f | سطح توقف اولیه: %.2f",
                     profit, g_TrailingStopLevel);
        }
      return;
     }

   // به‌روزرسانی اوج سود
   if(profit > g_PeakProfit)
     {
      g_PeakProfit = profit;
      double newStop = g_PeakProfit - TrailingStep;
      if(newStop > g_TrailingStopLevel)
        {
         g_TrailingStopLevel = newStop;
         PrintFormat("📈 تریلینگ به‌روز شد | اوج سود: %.2f | سطح توقف جدید: %.2f",
                     g_PeakProfit, g_TrailingStopLevel);
        }
     }

   // بررسی برخورد سود به سطح توقف
   if(profit <= g_TrailingStopLevel)
     {
      PrintFormat("🛑 تریلینگ فعال شد! سود شناور %.2f به سطح توقف %.2f رسید. بستن همه...",
                  profit, g_TrailingStopLevel);
      CloseAll();
      // ریست شبکه (مانند وقتی TP/SL اصلی زده می‌شود)
      int oldMagic = g_ActiveMagic;
      g_GridInstance++;
      g_ActiveMagic = MagicNumber + g_GridInstance;
      buyExpansionCount  = 0;
      sellExpansionCount = 0;
      lastBuyPosCount    = 0;
      lastSellPosCount   = 0;
      g_OrderCommentSeq  = 0;
      g_GridID           = "";
      tradingDone = true;
      isTradingActive = false;
      ResetTrailingState();
      ClearState();
      SaveState();
      PrintFormat("شبکه با Magic=%d بسته شد (تریلینگ). Magic جدید=%d آماده‌ی شروع.", oldMagic, g_ActiveMagic);
     }
  }
//+------------------------------------------------------------------+
//| بستن همه                                                        |
//+------------------------------------------------------------------+
void CloseAll()
  {
   int maxAttempts = 10;
   int attempt = 0;

   while(attempt < maxAttempts)
     {
      bool anyClosed = false;

      // بستن پوزیشن‌ها
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong t = PositionGetTicket(i);
         if(PositionSelectByTicket(t) &&
            PositionGetInteger(POSITION_MAGIC) == g_ActiveMagic &&
            PositionGetString(POSITION_SYMBOL) == _Symbol)
           {
            if(GridTrade.PositionClose(t))
              {
               PrintFormat("✅ پوزیشن %I64u بسته شد.", t);
               anyClosed = true;
              }
            else
              {
               PrintFormat("❌ بستن پوزیشن %I64u ناموفق. کد خطا: %d", t, GridTrade.ResultRetcode());
              }
           }
        }

      // حذف سفارشات معلق
      for(int i = OrdersTotal() - 1; i >= 0; i--)
        {
         ulong t = OrderGetTicket(i);
         if(OrderSelect(t) &&
            OrderGetInteger(ORDER_MAGIC) == g_ActiveMagic &&
            OrderGetString(ORDER_SYMBOL) == _Symbol)
           {
            if(GridTrade.OrderDelete(t))
              {
               PrintFormat("✅ سفارش %I64u حذف شد.", t);
               anyClosed = true;
              }
            else
              {
               PrintFormat("❌ حذف سفارش %I64u ناموفق. کد خطا: %d", t, GridTrade.ResultRetcode());
              }
           }
        }

      // اگر دیگر هیچ پوزیشن/سفارشی باقی نمانده، کار تمام است
      if(!AnyGridExists())
         break;

      if(!anyClosed)
        {
         Print("⚠️ تلاش مجدد برای بستن...");
         Sleep(100);
        }
      attempt++;
     }

   if(AnyGridExists())
      Print("🚨 بعد از چندین تلاش هنوز پوزیشن/سفارشی با این magic باقی مانده!");
   else
      Print("تمامی پوزیشن‌ها و سفارشات با موفقیت بسته شدند.");
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
   SendLogToServer("INFO", StringFormat("Closed %d profitable positions", closed));
  }

//+------------------------------------------------------------------+
void CloseAllGrid()
  {
   int oldMagic = g_ActiveMagic;
   CloseAll();
   g_GridInstance++;
   g_ActiveMagic = MagicNumber + g_GridInstance;
   buyExpansionCount  = 0;
   sellExpansionCount = 0;
   lastBuyPosCount    = 0;
   lastSellPosCount   = 0;
   g_OrderCommentSeq  = 0;
   g_GridID           = "";
   isTradingActive = false;
   tradingDone     = true;
   ClearState();
   SaveState();
   ResetTrailingState();
   SendLogToServer("INFO", "Closed all grid positions");
   UpdateParamOnServer("GridActive", 0.0);
   PrintFormat("شبکه با Magic=%d بسته شد. Magic جدید=%d آماده‌ی شروع.", oldMagic, g_ActiveMagic);
  }

//+------------------------------------------------------------------+
void FinalizeGrid()
  {
   if(!AnyGridExists())
     {
      Print("هیچ شبکه‌ی فعالی برای پایان وجود ندارد.");
      SendLogToServer("WARNING", "Finalize attempted but no active grid exists");
      return;
     }

   int oldMagic = g_ActiveMagic;
   g_GridInstance++;
   g_ActiveMagic = MagicNumber + g_GridInstance;

   buyExpansionCount  = 0;
   sellExpansionCount = 0;
   lastBuyPosCount    = 0;
   lastSellPosCount   = 0;
   g_OrderCommentSeq  = 0;
   g_GridID           = "";
   isTradingActive    = false;
   tradingDone        = true;
   ClearState();
   SaveState();
   ResetTrailingState();

   Comment("");
   SendLogToServer("INFO", StringFormat("Grid finalized manually | oldMagic=%d newMagic=%d", oldMagic, g_ActiveMagic));
   UpdateParamOnServer("GridActive", 0.0);
   PrintFormat("شبکه با Magic=%d پایان یافت. Magic جدید=%d آماده‌ی شروع.", oldMagic, g_ActiveMagic);
  }

//+------------------------------------------------------------------+
double CalculateTotalProfit()
  {
   double totalProfit = 0.0;
   for(int i = PositionsTotal()-1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(PositionSelectByTicket(t) &&
         PositionGetInteger(POSITION_MAGIC) == g_ActiveMagic &&
         PositionGetString(POSITION_SYMBOL) == _Symbol)
         totalProfit += PositionGetDouble(POSITION_PROFIT);
     }
   return totalProfit;
  }

//+------------------------------------------------------------------+
double CalculateClosedGridProfit()
  {
   double closedProfit = 0.0;
   if(!HistorySelect(0, TimeCurrent()))
      return 0.0;

   int totalDeals = HistoryDealsTotal();
   for(int i = 0; i < totalDeals; i++)
     {
      ulong dealTicket = HistoryDealGetTicket(i);
      if(dealTicket == 0) continue;
      if(HistoryDealGetInteger(dealTicket, DEAL_MAGIC) != g_ActiveMagic) continue;
      if(HistoryDealGetString(dealTicket, DEAL_SYMBOL) != _Symbol) continue;

      long dealType = HistoryDealGetInteger(dealTicket, DEAL_TYPE);
      if(dealType != DEAL_TYPE_BUY && dealType != DEAL_TYPE_SELL) continue;

      long entryType = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
      if(entryType != DEAL_ENTRY_OUT &&
         entryType != DEAL_ENTRY_INOUT &&
         entryType != DEAL_ENTRY_OUT_BY)
         continue;

      closedProfit += HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
      closedProfit += HistoryDealGetDouble(dealTicket, DEAL_SWAP);
      closedProfit += HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
      closedProfit += HistoryDealGetDouble(dealTicket, DEAL_FEE);
     }

   return closedProfit;
  }

//+------------------------------------------------------------------+
void DeleteAllOrdersAndPositions()
  {
   CloseAll();
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
//| به‌روزرسانی کامنت روی چارت با اطلاعات وضعیت شبکه                |
//+------------------------------------------------------------------+
void UpdateChartComment()
  {
   string commentText = "";
   int liveDirection = RefreshLiveTrendDirection(false);
   int displayDirection = (isTradingActive && !tradingDone && g_GridDirection != -1)
                          ? g_GridDirection
                          : liveDirection;

   string strengthStr = (g_TrendStrength >= 70) ? "💪 قوی" :
                        (g_TrendStrength >= 40) ? "⚖️ متوسط" : "🪫 ضعیف";
   string directionStr = (displayDirection == ORDER_TYPE_BUY)  ? "▲ خرید" :
                         (displayDirection == ORDER_TYPE_SELL) ? "▼ فروش" : "～ نامشخص";
   directionStr += " | " + strengthStr + " (" + IntegerToString(g_TrendStrength) + "%)";


   if(!isTradingActive)
     {
      commentText = "═════ GridHedge Ultimate ═════\n"
              "🔴 شبکه غیرفعال است.\n"
              "برای شروع، دکمه «شروع شبکه» را بزنید.\n\n";
      commentText += "🧭 جهت     : " + directionStr + "\n";
      Comment(commentText);
      return;
     }
   if(tradingDone)
     {
      commentText = "═════ GridHedge Ultimate ═════\n"
              "✅ شبکه پایان یافته (هدف سود یا حد ضرر رسیده).\n"
              "برای شروع مجدد، دکمه «شروع شبکه» را بزنید.\n\n";
      commentText += "🧭 جهت     : " + directionStr + "\n";
      Comment(commentText);
      return;
     }

   // محاسبه آمار
   double totalProfit = 0;
   double closedProfit = CalculateClosedGridProfit();
   int totalPos = 0, buyPos = 0, sellPos = 0;
   int buyOrders = 0, sellOrders = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(PositionSelectByTicket(t) &&
         PositionGetInteger(POSITION_MAGIC) == g_ActiveMagic &&
         PositionGetString(POSITION_SYMBOL) == _Symbol)
        {
         totalProfit += PositionGetDouble(POSITION_PROFIT);
         totalPos++;
         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
            buyPos++;
         else
            sellPos++;
        }
     }

   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong t = OrderGetTicket(i);
      if(OrderSelect(t) &&
         OrderGetInteger(ORDER_MAGIC) == g_ActiveMagic &&
         OrderGetString(ORDER_SYMBOL) == _Symbol)
        {
         ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
         if(type == ORDER_TYPE_BUY_STOP || type == ORDER_TYPE_BUY_LIMIT)
            buyOrders++;
         else if(type == ORDER_TYPE_SELL_STOP || type == ORDER_TYPE_SELL_LIMIT)
            sellOrders++;
        }
     }

   commentText += "═══════ GridHedge Ultimate ═══════\n";
   commentText += "🔢 Magic   : " + IntegerToString(g_ActiveMagic) + "\n";
   commentText += "🏷️ شناسه   : " + g_GridID + "\n";
   commentText += "🧭 جهت     : " + directionStr + "\n";
   commentText += "📦 حجم لات : " + DoubleToString(g_CurrentLot, 3) + "\n";
   commentText += "📊 پوزیشن‌ها: " + IntegerToString(totalPos) + "  ( خرید:" + IntegerToString(buyPos) + " | فروش:" + IntegerToString(sellPos) + " )\n";
   commentText += "⏳ سفارشات : Buy Stop:" + IntegerToString(buyOrders) + " | Sell Stop:" + IntegerToString(sellOrders) + "\n";
   commentText += "💰 سود/زیان باز: " + DoubleToString(totalProfit, 2) + " $\n";
   commentText += "✅ سود/زیان بسته‌شده: " + DoubleToString(closedProfit, 2) + " $\n";
   commentText += "🔄 گسترش   : Buy " + IntegerToString(buyExpansionCount) + "/" + IntegerToString(g_MaxBuyExpansions) +
                  " | Sell " + IntegerToString(sellExpansionCount) + "/" + IntegerToString(g_MaxSellExpansions) + "\n";
   commentText += "📏 گام شبکه: " + DoubleToString(GridStep_Points, 0) + " point\n";
   commentText += "🎯 هدف سود : " + DoubleToString(TotalProfitTarget, 2) + " $   |   حد ضرر: " + DoubleToString(TotalStopLoss, 2) + " $\n";
   commentText += "⚙️ وضعیت   : " + (isTradingActive ? "فعال" : "غیرفعال") + " | " + (tradingDone ? "پایان یافته" : "در حال اجرا");

   Comment(commentText);
  }

  //+------------------------------------------------------------------+
//| به‌روزرسانی برچسب‌های تغییرات حجم                        |
//+------------------------------------------------------------------+
  void UpdateLotLabel()
  {
   ObjectSetString(0, "ValLot", OBJPROP_TEXT, DoubleToString(g_CurrentLot, 3));
   UpdateCamarillaLabel();
  }

  //+------------------------------------------------------------------+
void UpdateCamarillaLabel()
  {
   ObjectSetString(0, "ValCamarilla", OBJPROP_TEXT,
                   g_EnableCamarillaCheck ? "true" : "false");
   
   string rangeText = "";
   if(g_CamarillaRange == MODE_H1_L1)
      rangeText = "H1-L1";
   else if(g_CamarillaRange == MODE_H2_L2)
      rangeText = "H2-L2";
   else if(g_CamarillaRange == MODE_H3_L3)
      rangeText = "H3-L3";
   else if(g_CamarillaRange == MODE_CUSTOM)
      rangeText = StringFormat("C(%d-%d)", CamarillaCustomUpper, CamarillaCustomLower);
   
   ObjectSetString(0, "ValCamarillaRange", OBJPROP_TEXT, rangeText);
   ObjectSetString(0, "ValRangeEnabled", OBJPROP_TEXT, g_EnableCamarillaRangeCheck ? "ON" : "OFF");
   ObjectSetInteger(0, "ValRangeEnabled", OBJPROP_COLOR, g_EnableCamarillaRangeCheck ? clrLime : clrRed);
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
  ObjectSetInteger(0, n, OBJPROP_XDISTANCE,    358);
  ObjectSetInteger(0, n, OBJPROP_YDISTANCE,    33);
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
      ObjectSetInteger(0, n1, OBJPROP_XDISTANCE,    276);
      ObjectSetInteger(0, n1, OBJPROP_YDISTANCE,    33);
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
      ObjectSetInteger(0, n2, OBJPROP_XDISTANCE,    202);
      ObjectSetInteger(0, n2, OBJPROP_YDISTANCE,    33);
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
      ObjectSetInteger(0, n3, OBJPROP_XDISTANCE,    124);
      ObjectSetInteger(0, n3, OBJPROP_YDISTANCE,    33);
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
  ObjectSetInteger(0, "LblBuyExp", OBJPROP_XDISTANCE, 273);
  ObjectSetInteger(0, "LblBuyExp", OBJPROP_YDISTANCE, 65);
   ObjectSetString (0, "LblBuyExp", OBJPROP_TEXT,      "Buy:");
   ObjectSetInteger(0, "LblBuyExp", OBJPROP_COLOR,     clrWhite);
   ObjectSetInteger(0, "LblBuyExp", OBJPROP_FONTSIZE,  8);

  CreateButton("BtnBuyExpMinus", "-", 225, 70, 20, 20, clrWhite, clrRed, 8);
   ObjectCreate(0, "ValBuyExp", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "ValBuyExp", OBJPROP_CORNER,    CORNER_RIGHT_UPPER);
  ObjectSetInteger(0, "ValBuyExp", OBJPROP_XDISTANCE, 183);
  ObjectSetInteger(0, "ValBuyExp", OBJPROP_YDISTANCE, 65);
   ObjectSetString (0, "ValBuyExp", OBJPROP_TEXT,      "0/" + IntegerToString(g_MaxBuyExpansions));
  ObjectSetInteger(0, "ValBuyExp", OBJPROP_COLOR,     clrYellow);
  ObjectSetInteger(0, "ValBuyExp", OBJPROP_FONTSIZE,  8);
  CreateButton("BtnBuyExpPlus",  "+", 126, 70, 20, 20, clrWhite, clrGreen, 8);
  CreateButton("BtnBuyExpPlus50", "+50", 72, 70, 44, 20, clrWhite, clrGreen, 8);
  CreateButton("BtnBuyExpZero",   "0",   42, 70, 20, 20, clrBlack, clrWhite, 8);

   ObjectCreate(0, "LblSellExp", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "LblSellExp", OBJPROP_CORNER,    CORNER_RIGHT_UPPER);
  ObjectSetInteger(0, "LblSellExp", OBJPROP_XDISTANCE, 273);
  ObjectSetInteger(0, "LblSellExp", OBJPROP_YDISTANCE, 89);
   ObjectSetString (0, "LblSellExp", OBJPROP_TEXT,      "Sell:");
   ObjectSetInteger(0, "LblSellExp", OBJPROP_COLOR,     clrWhite);
   ObjectSetInteger(0, "LblSellExp", OBJPROP_FONTSIZE,  8);

  CreateButton("BtnSellExpMinus", "-", 225, 94, 20, 20, clrWhite, clrRed, 8);
   ObjectCreate(0, "ValSellExp", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "ValSellExp", OBJPROP_CORNER,    CORNER_RIGHT_UPPER);
  ObjectSetInteger(0, "ValSellExp", OBJPROP_XDISTANCE, 183);
  ObjectSetInteger(0, "ValSellExp", OBJPROP_YDISTANCE, 89);
   ObjectSetString (0, "ValSellExp", OBJPROP_TEXT,      "0/" + IntegerToString(g_MaxSellExpansions));
  ObjectSetInteger(0, "ValSellExp", OBJPROP_COLOR,     clrYellow);
  ObjectSetInteger(0, "ValSellExp", OBJPROP_FONTSIZE,  8);
  CreateButton("BtnSellExpPlus",  "+", 126, 94, 20, 20, clrWhite, clrGreen, 8);
  CreateButton("BtnSellExpPlus50", "+50", 72, 94, 44, 20, clrWhite, clrGreen, 8);
  CreateButton("BtnSellExpZero",   "0",   42, 94, 20, 20, clrBlack, clrWhite, 8);
  }

//+------------------------------------------------------------------+
//| دکمه‌های تغییر حجم (Lot)                                         |
//+------------------------------------------------------------------+
void CreateLotButtons()
  {
   // برچسب "Lot:"
   ObjectCreate(0, "LblLot", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "LblLot", OBJPROP_CORNER,    CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, "LblLot", OBJPROP_XDISTANCE, 258);
   ObjectSetInteger(0, "LblLot", OBJPROP_YDISTANCE, 127);
   ObjectSetString (0, "LblLot", OBJPROP_TEXT,      "Lot:");
   ObjectSetInteger(0, "LblLot", OBJPROP_COLOR,     clrGreenYellow);
   ObjectSetInteger(0, "LblLot", OBJPROP_FONTSIZE,  8);

   // دکمه کاهش
   CreateButton("BtnLotMinus", "-", 218, 127, 20, 20, clrBlack, clrGreenYellow, 8);

   // مقدار فعلی
   ObjectCreate(0, "ValLot", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "ValLot", OBJPROP_CORNER,    CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, "ValLot", OBJPROP_XDISTANCE, 190);
   ObjectSetInteger(0, "ValLot", OBJPROP_YDISTANCE, 127);
   ObjectSetString (0, "ValLot", OBJPROP_TEXT,      DoubleToString(g_CurrentLot, 3));
   ObjectSetInteger(0, "ValLot", OBJPROP_COLOR,     clrGreenYellow);
   ObjectSetInteger(0, "ValLot", OBJPROP_FONTSIZE,  8);

   // دکمه افزایش
   CreateButton("BtnLotPlus",  "+", 126, 127, 20, 20, clrBlueViolet, clrGreenYellow, 8);

   // دکمه تغییر وضعیت Camarilla
   CreateButton("BtnToggleCamarilla", "حمایت/مقاومت", 126, 151, 120, 20, clrWhite, clrDodgerBlue, 8);

   ObjectCreate(0, "ValCamarilla", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "ValCamarilla", OBJPROP_CORNER,    CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, "ValCamarilla", OBJPROP_XDISTANCE, 178);
   ObjectSetInteger(0, "ValCamarilla", OBJPROP_YDISTANCE, 151);
   ObjectSetString (0, "ValCamarilla", OBJPROP_TEXT,      g_EnableCamarillaCheck ? "true" : "false");
   ObjectSetInteger(0, "ValCamarilla", OBJPROP_COLOR,     clrYellow);
   ObjectSetInteger(0, "ValCamarilla", OBJPROP_FONTSIZE,  8);

   // دکمه‌های محدودیت بازه - فقط اگر EnableCamarillaCheck == false
   if(!EnableCamarillaCheck)
     {
      // دکمه تغییر وضعیت محدودیت بازه کاماریلا
      CreateButton("BtnToggleCamarillaRange", "حالت بازه", 126, 175, 120, 20, clrWhite, clrMediumPurple, 8);

      ObjectCreate(0, "ValCamarillaRange", OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, "ValCamarillaRange", OBJPROP_CORNER,    CORNER_RIGHT_UPPER);
      ObjectSetInteger(0, "ValCamarillaRange", OBJPROP_XDISTANCE, 178);
      ObjectSetInteger(0, "ValCamarillaRange", OBJPROP_YDISTANCE, 175);
      ObjectSetString (0, "ValCamarillaRange", OBJPROP_TEXT,      "H2-L2");
      ObjectSetInteger(0, "ValCamarillaRange", OBJPROP_COLOR,     clrYellow);
      ObjectSetInteger(0, "ValCamarillaRange", OBJPROP_FONTSIZE,  8);
      
      // دکمه فعال/غیرفعال کردن ویژگی Range Check
      CreateButton("BtnEnableCamarillaRange", "✓ Range", 126, 199, 120, 20, clrWhite, clrDarkGreen, 8);
      
      ObjectCreate(0, "ValRangeEnabled", OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, "ValRangeEnabled", OBJPROP_CORNER,    CORNER_RIGHT_UPPER);
      ObjectSetInteger(0, "ValRangeEnabled", OBJPROP_XDISTANCE, 178);
      ObjectSetInteger(0, "ValRangeEnabled", OBJPROP_YDISTANCE, 199);
      ObjectSetString (0, "ValRangeEnabled", OBJPROP_TEXT,      g_EnableCamarillaRangeCheck ? "ON" : "OFF");
      ObjectSetInteger(0, "ValRangeEnabled", OBJPROP_COLOR,     g_EnableCamarillaRangeCheck ? clrLime : clrRed);
      ObjectSetInteger(0, "ValRangeEnabled", OBJPROP_FONTSIZE,  8);
     }

   // دکمه‌های TrailingActivation - فقط اگر UseBasketTrailing == true
   if(UseBasketTrailing)
     {
      // دکمه کاهش TrailingActivation
      CreateButton("BtnTrailingActivationMinus", "-", 218, 223, 20, 20, clrBlack, clrDarkOrange, 8);

      // مقدار فعلی TrailingActivation
      ObjectCreate(0, "ValTrailingActivation", OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, "ValTrailingActivation", OBJPROP_CORNER,    CORNER_RIGHT_UPPER);
      ObjectSetInteger(0, "ValTrailingActivation", OBJPROP_XDISTANCE, 190);
      ObjectSetInteger(0, "ValTrailingActivation", OBJPROP_YDISTANCE, 223);
      ObjectSetString (0, "ValTrailingActivation", OBJPROP_TEXT,      DoubleToString(g_TrailingActivation, 2));
      ObjectSetInteger(0, "ValTrailingActivation", OBJPROP_COLOR,     clrDarkOrange);
      ObjectSetInteger(0, "ValTrailingActivation", OBJPROP_FONTSIZE,  8);

      // دکمه افزایش TrailingActivation
      CreateButton("BtnTrailingActivationPlus",  "+", 126, 223, 20, 20, clrBlueViolet, clrDarkOrange, 8);
      
      // برچسب TrailingActivation
      ObjectCreate(0, "LblTrailingActivation", OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, "LblTrailingActivation", OBJPROP_CORNER,    CORNER_RIGHT_UPPER);
      ObjectSetInteger(0, "LblTrailingActivation", OBJPROP_XDISTANCE, 300);
      ObjectSetInteger(0, "LblTrailingActivation", OBJPROP_YDISTANCE, 223);
      ObjectSetString (0, "LblTrailingActivation", OBJPROP_TEXT,      "Trailing:");
      ObjectSetInteger(0, "LblTrailingActivation", OBJPROP_COLOR,     clrDarkOrange);
      ObjectSetInteger(0, "LblTrailingActivation", OBJPROP_FONTSIZE,  8);
     }
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





//+------------------------------------------------------------------+
//| محاسبه سطوح کاماریلا بر اساس کندل روز قبل                         |
//+------------------------------------------------------------------+
CamarillaLevels CalculateCamarilla(const MqlRates &prevDay)
  {
   CamarillaLevels levels;
   levels.valid = false;
   ZeroMemory(levels);

   double high = prevDay.high;
   double low  = prevDay.low;
   double close = prevDay.close;

   if(high <= 0 || low <= 0 || close <= 0 || (high - low) <= 0)
      return levels;

   double range = high - low;
   double factor = 1.1;  // همان فاکتور استاندارد کاماریلا

   levels.H5 = (high / low) * close;
   levels.H4 = close + range * factor / 2.0;
   levels.H3 = close + range * factor / 4.0;
   levels.H2 = close + range * factor / 6.0;
   levels.H1 = close + range * factor / 12.0;
   levels.L1 = close - range * factor / 12.0;
   levels.L2 = close - range * factor / 6.0;
   levels.L3 = close - range * factor / 4.0;
   levels.L4 = close - range * factor / 2.0;
   levels.L5 = close - (levels.H5 - close);

   levels.valid = true;
   return levels;
  }

//+------------------------------------------------------------------+
//| دریافت سطوح کاماریلا برای امروز (بر اساس آخرین روز کامل)         |
//+------------------------------------------------------------------+
CamarillaLevels GetTodayCamarilla()
  {
   MqlRates prevDay[1];
   // گرفتن کندل روز قبل (شاخص 1 یعنی دیروز نسبت به امروز)
   if(CopyRates(_Symbol, PERIOD_D1, 1, 1, prevDay) != 1)
     {
      Print("⚠️ خطا در دریافت داده روز قبل برای محاسبه Camarilla. Error: ", GetLastError());
      CamarillaLevels empty;
      empty.valid = false;
      return empty;
     }
   return CalculateCamarilla(prevDay[0]);
  }

//+------------------------------------------------------------------+
//| گرفتن مقدار سطح کاماریلا بر اساس شماره                           |
//+------------------------------------------------------------------+
double GetCamarillaLevelByNumber(const CamarillaLevels& levels, int levelNumber, bool isUpper)
  {
   // levelNumber: 1=H5/L5, 2=H4/L4, 3=H3/L3, 4=H2/L2, 5=H1/L1
   if(isUpper)
     {
      if(levelNumber == 1) return levels.H5;
      if(levelNumber == 2) return levels.H4;
      if(levelNumber == 3) return levels.H3;
      if(levelNumber == 4) return levels.H2;
      if(levelNumber == 5) return levels.H1;
     }
   else
     {
      if(levelNumber == 1) return levels.L5;
      if(levelNumber == 2) return levels.L4;
      if(levelNumber == 3) return levels.L3;
      if(levelNumber == 4) return levels.L2;
      if(levelNumber == 5) return levels.L1;
     }
   return 0;
  }

//+------------------------------------------------------------------+
//| دریافت سطوح بازه براساس حالت انتخاب‌شده                         |
//+------------------------------------------------------------------+
bool GetCamarillaRangeLevels(double& upperLevel, double& lowerLevel)
  {
   CamarillaLevels levels = GetTodayCamarilla();
   if(!levels.valid) return false;
   
   if(g_CamarillaRange == MODE_H1_L1)
     {
      upperLevel = levels.H1;
      lowerLevel = levels.L1;
     }
   else if(g_CamarillaRange == MODE_H2_L2)
     {
      upperLevel = levels.H2;
      lowerLevel = levels.L2;
     }
   else if(g_CamarillaRange == MODE_H3_L3)
     {
      upperLevel = levels.H3;
      lowerLevel = levels.L3;
     }
   else if(g_CamarillaRange == MODE_CUSTOM)
     {
      upperLevel = GetCamarillaLevelByNumber(levels, CamarillaCustomUpper, true);
      lowerLevel = GetCamarillaLevelByNumber(levels, CamarillaCustomLower, false);
     }
   
   return (upperLevel > 0 && lowerLevel > 0);
  }

//+------------------------------------------------------------------+
//| بررسی اینکه قیمت درون بازه سطوح کاماریلا است یا نه                 |
//+------------------------------------------------------------------+
bool IsPriceWithinCamarillaRange(double price)
  {
   if(!g_EnableCamarillaRangeCheck) return true;

   static datetime lastDay = 0;
   static double cachedUpper = 0, cachedLower = 0;
   datetime todayStart = iTime(_Symbol, PERIOD_D1, 0);
   
   // بازخوانی سطوح هر روز
   if(todayStart != lastDay)
     {
      if(!GetCamarillaRangeLevels(cachedUpper, cachedLower))
         return true; // اگر نتوانستیم سطوح را بگیریم، سفارش را بپذیر
      lastDay = todayStart;
     }
   
   // بررسی اینکه قیمت بین دو سطح است
   if(price >= cachedLower && price <= cachedUpper)
     {
      PrintFormat("✅ قیمت %.5f درون بازه [%.5f - %.5f]", price, cachedLower, cachedUpper);
      return true;
     }
   
   PrintFormat("⛔ قیمت %.5f خارج از بازه [%.5f - %.5f]. سفارش ایجاد نشود.",
               price, cachedLower, cachedUpper);
   return false;
  }


//+------------------------------------------------------------------+
//| بررسی نزدیکی قیمت به سطوح اصلی کاماریلا                          |
//+------------------------------------------------------------------+
bool IsNearCamarillaLevel(double price, double minDistancePoints)
  {
   if(!g_EnableCamarillaCheck) return false;

   static CamarillaLevels lastLevels;
   static datetime lastDay = 0;
   datetime todayStart = iTime(_Symbol, PERIOD_D1, 0);
   
   if(todayStart != lastDay || !lastLevels.valid)
     {
      lastLevels = GetTodayCamarilla();  // این تابع باید مطابق قبل باشد (CopyRates)
      lastDay = todayStart;
      if(!lastLevels.valid) return false;
     }
   
   double minDist = minDistancePoints * _Point;
   
   // آرایه شامل هر 10 سطح
   double levels[] = {lastLevels.H5, lastLevels.H4, lastLevels.H3, lastLevels.H2, lastLevels.H1,
                      lastLevels.L1, lastLevels.L2, lastLevels.L3, lastLevels.L4, lastLevels.L5};
   string names[] = {"H5","H4","H3","H2","H1","L1","L2","L3","L4","L5"};
   
   for(int i = 0; i < 10; i++)
     {
      if(levels[i] <= 0) continue;
      double diff = MathAbs(price - levels[i]);
      if(diff < minDist)
        {
         PrintFormat("⚠️ گسترش متوقف شد: قیمت %.5f به سطح %s (%.5f) نزدیک است (فاصله: %.1f پیپ)",
                     price, names[i], levels[i], diff / _Point);
         return true;
        }
     }
   return false;
  }

  
  //+------------------------------------------------------------------+
//| نمایش عمودی سطوح کاماریلا در سمت راست، زیر دکمه‌ها (چند لیبل)     |
//+------------------------------------------------------------------+
void ShowCamarillaLevelsOnChart()
  {
   if(!g_EnableCamarillaCheck) return;

   static datetime lastDisplayDay = 0;
   datetime todayStart = iTime(_Symbol, PERIOD_D1, 0);
   if(todayStart == lastDisplayDay) return;
   lastDisplayDay = todayStart;

   CamarillaLevels levels = GetTodayCamarilla();
   if(!levels.valid) return;

   string prefix = "Camarilla_";
   // حذف تمام لیبل‌های قدیمی با این پیشوند
   ObjectsDeleteAll(0, prefix);

   // مختصات شروع (گوشه بالا-راست، زیر دکمه‌ها)
   int startX = 150;      // فاصله از لبه راست
   int startY = 150;     // فاصله از لبه بالا (زیر دکمه‌های لات که در Y=117 بودند)
   int stepY = 16;       // فاصله عمودی بین هر خط

   startY += stepY;

   // سطوح مقاومت (H5 تا H1)
   string hLabels[5] = {"H5", "H4", "H3", "H2", "H1"};
   double hValues[5] = {levels.H5, levels.H4, levels.H3, levels.H2, levels.H1};
   for(int i = 0; i < 5; i++)
     {
      string text = hLabels[i] + ": " + DoubleToString(hValues[i], _Digits);
      CreateLabel(prefix + hLabels[i], text, startX, startY + i * stepY, clrRed, 8);
     }
   startY += 5 * stepY;

   // خط جداکننده
   startY += stepY;

   // سطوح حمایت (L1 تا L5)
   string lLabels[5] = {"L1", "L2", "L3", "L4", "L5"};
   double lValues[5] = {levels.L1, levels.L2, levels.L3, levels.L4, levels.L5};
   for(int i = 0; i < 5; i++)
     {
      string text = lLabels[i] + ": " + DoubleToString(lValues[i], _Digits);
      CreateLabel(prefix + lLabels[i], text, startX, startY + i * stepY, clrGreen, 8);
     }

   Print("📊 سطوح کاماریلا (عمودی، چندلیبل) در سمت راست چارت به‌روز شد.");
  }

//+------------------------------------------------------------------+
//| SERVER API FUNCTIONS - ارسال/بازیابی اطلاعات از سرور             |
//+------------------------------------------------------------------+

string TrimString(string value)
  {
   StringTrimLeft(value);
   StringTrimRight(value);
   return value;
  }

string JsonEscape(string value)
  {
   StringReplace(value, "\\", "\\\\");
   StringReplace(value, "\"", "\\\"");
   StringReplace(value, "\r", "\\r");
   StringReplace(value, "\n", "\\n");
   return value;
  }

void StringToUtf8Body(string text, char &body[])
  {
   int len = StringToCharArray(text, body, 0, WHOLE_ARRAY, CP_UTF8);
   if(len > 0)
      ArrayResize(body, len - 1);
  }

string ResponseToString(const char &result[])
  {
   if(ArraySize(result) <= 0)
      return "";
   return CharArrayToString(result, 0, ArraySize(result), CP_UTF8);
  }

void PrintWebRequestError(string action, int status, int err, string url, string response, string headers)
  {
   PrintFormat("❌ %s: status=%d err=%d url=%s response=%s headers=%s",
               action, status, err, url, response, headers);
  }

//+------------------------------------------------------------------+
//| ارسال لاگ به سرور                                                |
//+------------------------------------------------------------------+
void SendLogToServer(string level, string message)
  {
   if(!EnableServerSync || UserToken == "") return;

   string url = ServerURL + "/logs";
   string headers = "Authorization: Bearer " + UserToken + "\r\nContent-Type: application/json\r\n";
   
   // ساخت JSON payload
   string json = "{\"level\":\"" + JsonEscape(level) + "\",\"message\":\"" + JsonEscape(message) + "\"}";
   
   char post_data[];
   StringToUtf8Body(json, post_data);
   
   char result[];
   string result_headers;
   
   ResetLastError();
   int res = WebRequest("POST", url, headers, 5000, post_data, result, result_headers);
   int err = GetLastError();
   string response = ResponseToString(result);
   if(res >= 200 && res < 300)
     {
      PrintFormat("✅ لاگ ارسال شد: %s", message);
     }
   else
     {
      PrintWebRequestError("خطا در ارسال لاگ", res, err, url, response, result_headers);
     }
  }

//+------------------------------------------------------------------+
//| بازیابی پارامتر از سرور                                           |
//+------------------------------------------------------------------+
double FetchParamFromServer(string paramName, double defaultValue)
  {
   if(!EnableServerSync || UserToken == "") return defaultValue;
   
   string url = ServerURL + "/params";
   string headers = "Authorization: Bearer " + UserToken + "\r\n";
   
   char empty_data[];
   char result[];
   string result_headers;
   
   ResetLastError();
   int res = WebRequest("GET", url, headers, 5000, empty_data, result, result_headers);
   int err = GetLastError();
   string response = ResponseToString(result);
   if(res < 200 || res >= 300)
     {
      PrintWebRequestError("خطا در دریافت پارامترها", res, err, url, response, result_headers);
      return defaultValue;
     }
   
   // جستجوی ساده برای parameter (می‌تواند بهتر شود با JSON parser)
   int pos = StringFind(response, "\"" + paramName + "\"");
   if(pos == -1) return defaultValue;
   
   pos = StringFind(response, "\"value\"", pos);
   if(pos == -1) return defaultValue;
   
   pos = StringFind(response, ":", pos);
   if(pos == -1) return defaultValue;
   
   string value_str = StringSubstr(response, pos + 1, 30);
   value_str = TrimString(value_str);
   if(StringLen(value_str) > 0 && StringGetCharacter(value_str, 0) == '"')
      value_str = StringSubstr(value_str, 1);
   int endQuote = StringFind(value_str, "\"");
   if(endQuote >= 0)
      value_str = StringSubstr(value_str, 0, endQuote);
   value_str = TrimString(value_str);
   
   return StringToDouble(value_str);
  }

//+------------------------------------------------------------------+
//| تغییر پارامتر روی سرور                                            |
//+------------------------------------------------------------------+
void UpdateParamOnServer(string paramName, double value)
  {
   if(!EnableServerSync || UserToken == "") return;
   
   string url = ServerURL + "/params/" + paramName;
   string headers = "Authorization: Bearer " + UserToken + "\r\nContent-Type: application/json\r\n";
   
   // ساخت JSON payload
   string json = "{\"name\":\"" + JsonEscape(paramName) + "\",\"value\":\"" + DoubleToString(value, 3) + "\"}";
   
   char put_data[];
   StringToUtf8Body(json, put_data);
   
   char result[];
   string result_headers;
   
   ResetLastError();
   int res = WebRequest("PUT", url, headers, 5000, put_data, result, result_headers);
   int err = GetLastError();
   string response = ResponseToString(result);
   if(res >= 200 && res < 300)
     {
      PrintFormat("✅ پارامتر %s به‌روز شد: %.3f", paramName, value);
     }
   else
     {
      PrintWebRequestError("خطا در بروزرسانی پارامتر", res, err, url, response, result_headers);
     }
  }

//+------------------------------------------------------------------+
//| تابع کمکی برای ساخت لیبل با مختصات مشخص (قبلاً داشتیم)           |
//+------------------------------------------------------------------+
void CreateLabel(string name, string text, int x, int y, color clr, int fontSize)
  {
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
  }
