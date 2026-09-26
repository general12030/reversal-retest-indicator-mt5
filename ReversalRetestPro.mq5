#property copyright "Professional Trading Tools"
#property version   "2.0"
#property strict
#property indicator_chart_window

input int HistoricalBars = 500;       // عدد الشموع التاريخية المراد فحصها
input int LookbackTrend = 20;         // عدد الشموع للتحقق من الاتجاه الهابط
input int WeakMomentumBars = 8;       // عدد الشموع لقياس ضعف الزخم
input double MinEngulfRatio = 1.15;   // نسبة ابتلاع الشمعة الصفراوية/الحمراء
input int RetestBars = 4;             // عدد الشموع لإعادة الاختبار
input double MinBodySize = 50.0;      // الحد الأدنى لطول جسم الشمعة
input int MaxSignalDistance = 100;    // أقصى مسافة بين ابتلاع الشمعة وإعادة الاختبار
input bool ShowHistoricalSignals = true;
input bool ShowPanel = true;
input int PanelWidth = 350;
input int PanelHeight = 500;
input color PanelBackgroundColor = clrBlack;
input color PanelBorderColor = clrDodgerBlue;

struct Signal
{
   datetime time;
   double entryPrice;
   double stopLoss;
   double target1;
   double target2;
   double target3;
   double maxGain;
   double maxLoss;
   bool isWinning;
   int bars;
};

Signal signals[];
int signalCount = 0;

//===== Global stats =====
int totalSignals = 0;
int winningSignals = 0;
int losingSignals = 0;
double totalPipsGained = 0;
double maxDrawdown = 0;

//===== Initialization =====
int OnInit()
{
   ArrayResize(signals, 1000);
   if(ShowHistoricalSignals) ScanHistoricalBars();
   CalculateStatistics();
   if(ShowPanel) CreatePanel();
   UpdatePanel();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, OBJ_HLINE, 0, -1, -1);
   ObjectsDeleteAll(0, OBJ_ARROW_UP, 0, -1, -1);
   ObjectsDeleteAll(0, OBJ_LABEL, 0, -1, -1);
   ObjectsDeleteAll(0, OBJ_RECTANGLE, 0, -1, -1);
}

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const int begin,
                const double &price[])
{
   if(prev_calculated == 0)
   {
      if(ShowHistoricalSignals) ScanHistoricalBars();
      CalculateStatistics();
      UpdatePanel();
   }
   return rates_total;
}

void ScanHistoricalBars()
{
   int bars = Bars(Symbol(), Period());
   int start = MathMin(HistoricalBars, bars - 10);
   signalCount = 0;

   for(int i = start; i > 0; i--)
   {
      if(!IsBearishTrend(i)) continue;
      if(!IsWeakMomentum(i)) continue;
      if(!IsLowerWickSignal(i)) continue;
      if(!IsBullishEngulfing(i)) continue;

      int retestBar = FindRetestBar(i);
      if(retestBar == -1) continue;

      int breakoutBar = FindBreakoutBar(i, retestBar);
      if(breakoutBar == -1) continue;

      Signal sig;
      sig.time = iTime(Symbol(), Period(), breakoutBar);
      sig.entryPrice = iHigh(Symbol(), Period(), i);
      sig.stopLoss = iLow(Symbol(), Period(), retestBar);

      double risk = sig.entryPrice - sig.stopLoss;
      sig.target1 = sig.entryPrice + risk;
      sig.target2 = sig.entryPrice + risk * 1.5;
      sig.target3 = sig.entryPrice + risk * 2.0;

      sig.isWinning = false;
      sig.maxGain = 0;
      sig.maxLoss = 0;
      sig.bars = 0;
      EstimatePerformance(sig, breakoutBar);

      if(signalCount < ArraySize(signals))
      {
         signals[signalCount] = sig;
         signalCount++;
      }
   }

   if(ShowHistoricalSignals)
      DrawSignals();
}

bool IsBearishTrend(int bar)
{
   int red = 0;
   for(int i = bar; i < bar + LookbackTrend; i++)
   {
      double o = iOpen(Symbol(), Period(), i);
      double c = iClose(Symbol(), Period(), i);
      if(c < o) red++;
   }
   return red >= (int)(LookbackTrend * 0.65);
}

bool IsWeakMomentum(int bar)
{
   for(int i = bar; i < bar + WeakMomentumBars; i++)
   {
      double o = iOpen(Symbol(), Period(), i);
      double c = iClose(Symbol(), Period(), i);
      double h = iHigh(Symbol(), Period(), i);
      double l = iLow(Symbol(), Period(), i);
      double body = MathAbs(c - o);
      double range = h - l;
      if(range > 0 && body < range * 0.35) return true;
   }
   return false;
}

bool IsLowerWickSignal(int bar)
{
   for(int i = bar; i < bar + 5; i++)
   {
      double o = iOpen(Symbol(), Period(), i);
      double c = iClose(Symbol(), Period(), i);
      double h = iHigh(Symbol(), Period(), i);
      double l = iLow(Symbol(), Period(), i);
      if(c < o)
      {
         double downWick = o - l;
         double range = h - l;
         if(range > 0 && downWick > range * 0.55) return true;
      }
   }
   return false;
}

bool IsBullishEngulfing(int bar)
{
   if(bar + 1 >= Bars(Symbol(), Period())) return false;
   double prevClose = iClose(Symbol(), Period(), bar + 1);
   double prevOpen  = iOpen(Symbol(), Period(), bar + 1);
   double currClose = iClose(Symbol(), Period(), bar);
   double currOpen  = iOpen(Symbol(), Period(), bar);

   if(prevClose >= prevOpen) return false;
   if(currClose <= currOpen) return false;

   double prevBody = MathAbs(prevClose - prevOpen);
   double currBody = MathAbs(currClose - currOpen);
   if(currBody < MinBodySize) return false;
   if(currBody < prevBody * MinEngulfRatio) return false;

   return true;
}

int FindRetestBar(int engulfBar)
{
   double engulfHigh = iHigh(Symbol(), Period(), engulfBar);
   int start = MathMax(0, engulfBar - 1);
   int end = MathMax(0, engulfBar - MaxSignalDistance);
   for(int i = start; i > end; i--)
   {
      double low = iLow(Symbol(), Period(), i);
      double close = iClose(Symbol(), Period(), i);
      if(low < engulfHigh && close < engulfHigh)
      {
         if(close > iOpen(Symbol(), Period(), i)) return i;
      }
   }
   return -1;
}

int FindBreakoutBar(int engulfBar, int retestBar)
{
   double engulfHigh = iHigh(Symbol(), Period(), engulfBar);
   int start = MathMax(0, retestBar - 1);
   int finish = MathMax(0, start - 10);
   for(int i = start; i >= finish; i--)
   {
      double close = iClose(Symbol(), Period(), i);
      if(close > engulfHigh) return i;
   }
   return -1;
}

void EstimatePerformance(Signal &sig, int startBar)
{
   sig.bars = 0;
   sig.maxGain = 0;
   sig.maxLoss = 0;
   sig.isWinning = false;

   for(int i = startBar; i >= 0 && sig.bars < 200; i--)
   {
      double high = iHigh(Symbol(), Period(), i);
      double low = iLow(Symbol(), Period(), i);

      sig.bars++;
      sig.maxGain = MathMax(sig.maxGain, high - sig.entryPrice);
      sig.maxLoss = MathMin(sig.maxLoss, low - sig.entryPrice);

      if(low < sig.stopLoss)
      {
         sig.isWinning = false;
         break;
      }

      if(high >= sig.target1 || high >= sig.target2 || high >= sig.target3)
      {
         sig.isWinning = true;
         break;
      }
   }
}

void CalculateStatistics()
{
   totalSignals = signalCount;
   winningSignals = 0;
   losingSignals = 0;
   totalPipsGained = 0;
   maxDrawdown = 0;

   for(int i = 0; i < signalCount; i++)
   {
      if(signals[i].isWinning)
      {
         winningSignals++;
         totalPipsGained += signals[i].maxGain;
      }
      else
      {
         losingSignals++;
         totalPipsGained += signals[i].maxLoss;
      }
   }
}

void DrawSignals()
{
   for(int i = 0; i < signalCount; i++)
   {
      Signal s = signals[i];
      string name = "RR_SIG_" + IntegerToString(i);
      ObjectCreate(0, name, OBJ_ARROW_UP, 0, s.time, s.entryPrice);
      ObjectSetInteger(0, name, OBJPROP_COLOR, s.isWinning ? clrLimeGreen : clrRed);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
      ObjectSetString(0, name, OBJPROP_TEXT, "BUY");

      // SL line
      string sl = "RR_SL_" + IntegerToString(i);
      ObjectCreate(0, sl, OBJ_HLINE, 0, s.time, s.stopLoss);
      ObjectSetInteger(0, sl, OBJPROP_COLOR, clrRed);
      ObjectSetInteger(0, sl, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, sl, OBJPROP_WIDTH, 1);

      // T1/T2/T3
      string t1 = "RR_T1_" + IntegerToString(i);
      ObjectCreate(0, t1, OBJ_HLINE, 0, s.time, s.target1);
      ObjectSetInteger(0, t1, OBJPROP_COLOR, clrDodgerBlue);
      ObjectSetInteger(0, t1, OBJPROP_STYLE, STYLE_DOT);

      string t2 = "RR_T2_" + IntegerToString(i);
      ObjectCreate(0, t2, OBJ_HLINE, 0, s.time, s.target2);
      ObjectSetInteger(0, t2, OBJPROP_COLOR, clrDodgerBlue);
      ObjectSetInteger(0, t2, OBJPROP_STYLE, STYLE_DOT);

      string t3 = "RR_T3_" + IntegerToString(i);
      ObjectCreate(0, t3, OBJ_HLINE, 0, s.time, s.target3);
      ObjectSetInteger(0, t3, OBJPROP_COLOR, clrGold);
      ObjectSetInteger(0, t3, OBJPROP_STYLE, STYLE_DOT);
   }
}

void CreatePanel()
{
   ObjectCreate(0, "RR_PANEL_BG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, "RR_PANEL_BG", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, "RR_PANEL_BG", OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, "RR_PANEL_BG", OBJPROP_YDISTANCE, 30);
   ObjectSetInteger(0, "RR_PANEL_BG", OBJPROP_XSIZE, PanelWidth);
   ObjectSetInteger(0, "RR_PANEL_BG", OBJPROP_YSIZE, PanelHeight);
   ObjectSetInteger(0, "RR_PANEL_BG", OBJPROP_COLOR, PanelBackgroundColor);
   ObjectSetInteger(0, "RR_PANEL_BG", OBJPROP_BORDER_COLOR, PanelBorderColor);
   ObjectSetInteger(0, "RR_PANEL_BG", OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, "RR_PANEL_BG", OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, "RR_PANEL_BG", OBJPROP_BACK, false);
   ObjectSetInteger(0, "RR_PANEL_BG", OBJPROP_FILL, true);

   CreateLabel("RR_TITLE", "REVERSAL RETEST PRO", 20, 40, 14, clrDodgerBlue);
   CreateLabel("RR_TOTAL", "إجمالي الإشارات: 0", 20, 70, 11, clrWhite);
   CreateLabel("RR_WIN", "إشارات رابحة: 0", 20, 90, 11, clrLimeGreen);
   CreateLabel("RR_LOSS", "إشارات خاسرة: 0", 20, 110, 11, clrRed);
   CreateLabel("RR_PIPS", "إجمالي النقاط: 0", 20, 130, 11, clrDodgerBlue);
   CreateLabel("RR_DD", "أقصى تراجع: 0", 20, 150, 11, clrOrange);
   CreateLabel("RR_RATE", "نسبة النجاح: 0%", 20, 170, 11, clrYellow);

   for(int i = 0; i < 10; i++)
      CreateLabel("RR_REC_" + IntegerToString(i), "", 20, 200 + (i * 18), 9, clrWhite);
}

void CreateLabel(string name, string text, int x, int y, int fontSize, color clr)
{
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
}

void UpdatePanel()
{
   string totalText = "إجمالي الإشارات: " + IntegerToString(totalSignals);
   ObjectSetString(0, "RR_TOTAL", OBJPROP_TEXT, totalText);

   string winText = "إشارات رابحة: " + IntegerToString(winningSignals);
   ObjectSetString(0, "RR_WIN", OBJPROP_TEXT, winText);

   string lossText = "إشارات خاسرة: " + IntegerToString(losingSignals);
   ObjectSetString(0, "RR_LOSS", OBJPROP_TEXT, lossText);

   string pipsText = "إجمالي النقاط: " + DoubleToString(totalPipsGained / _Point, 2);
   ObjectSetString(0, "RR_PIPS", OBJPROP_TEXT, pipsText);

   string ddText = "أقصى تراجع: " + DoubleToString(maxDrawdown / _Point, 2);
   ObjectSetString(0, "RR_DD", OBJPROP_TEXT, ddText);

   double winRate = totalSignals > 0 ? (double)winningSignals / totalSignals * 100 : 0;
   string rateText = "نسبة النجاح: " + DoubleToString(winRate, 1) + "%";
   ObjectSetString(0, "RR_RATE", OBJPROP_TEXT, rateText);

   int recCount = MathMin(10, signalCount);
   for(int i = 0; i < recCount; i++)
   {
      int idx = signalCount - 1 - i;
      Signal s = signals[idx];
      string text = (s.isWinning ? "✓" : "✗") + " " + TimeToString(s.time, TIME_DATE | TIME_MINUTES);
      ObjectSetString(0, "RR_REC_" + IntegerToString(i), OBJPROP_TEXT, text);
      ObjectSetInteger(0, "RR_REC_" + IntegerToString(i), OBJPROP_COLOR, s.isWinning ? clrLimeGreen : clrRed);
   }
}
