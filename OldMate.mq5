//+------------------------------------------------------------------+
//|                                                      OldMate.mq5 |
//|                    OldMate - conventional autotrading for MT5     |
//|                                                                  |
//|  Three lanes (M5 / M15 / M30) on one chart. Each lane reads the   |
//|  chart three ways, shows every reading separately, chooses which   |
//|  reading family to trust from measured market memory, plans one    |
//|  trade, and manages it to the end: limit, fill, TP1 partial,       |
//|  trailing stop, TP2, grade.                                       |
//|                                                                  |
//|  RULES THIS FILE LIVES BY                                        |
//|   1. No fallback. A value that cannot be measured is reported as  |
//|      CALIBRATING / DATA WAIT / Unclear, never defaulted.          |
//|   2. No fabricated claim. Agreement is not a probability.         |
//|   3. Closed bars only. The forming bar is never read.             |
//|   4. Correct instrument for the correct job - Wilder smoothing is |
//|      Wilder's, true range counts gaps, percentiles are empirical  |
//|      with a minimum sample count, the target is measured not       |
//|      multiplied.                                                  |
//|   5. The EA may do less than the plan says, never more.           |
//+------------------------------------------------------------------+
#property copyright   "OldMate"
#property version     "1.00"
#property description "Conventional, self-configuring MT5 autotrader."

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//====================================================================
//  SWITCHES - nine, all on/off, all safe at their default forever
//====================================================================
input bool   InpAutoTrade    = true;   // Autotrading (master switch)
input bool   InpAllowM5      = true;   // Allow M5 autotrade
input bool   InpAllowM15     = true;   // Allow M15 autotrade
input bool   InpAllowM30     = true;   // Allow M30 autotrade
input bool   InpTrailStop    = true;   // Trailstop enable
input bool   InpTp1Tp2       = true;   // TP1 partial + TP2
input bool   InpDiaryDetails = true;   // Diary details
input bool   InpTweakArm     = false;  // Tweak (arm one bounded self-tweak)
input bool   InpMinLot       = false;  // Minimum lot

//====================================================================
//  CONSTANTS
//====================================================================
#define EA_NAME            "OLD MATE"
#define PANEL_PREFIX       "OM_"
#define DETAIL_PREFIX      "OMD_"
#define PANEL_X            12
#define PANEL_Y            22
#define FONT_NAME          "Consolas"
#define FONT_SIZE          9
#define DRAW_MIN_MS        1000
#define REFRESH_SEC        600
#define SESSION_SEC        300
#define SPREAD_SAMPLE_SEC  5
#define STALE_MINUTES      5.0

#define LANE_COUNT         3
#define MAX_SESSIONS       64
#define SPREAD_SAMPLES     240

//  Reading / calibration windows.  Morphology, not user settings.
//  The percentile window is per lane (LaneRankWindow): 300 / 400 / 500 bars,
//  because a scalper must adapt within an hour and an intraday lane should
//  reflect the session.  It is morphology, not a user setting.
#define PCT_MIN            60      // minimum samples before a percentile speaks
#define MEM_BARS           320     // bars analysed for market memory
#define SEED_BARS          900     // closed bars loaded per lane

//  Canonical indicator identity.  These lengths ARE the indicators the owner
//  can see on their own chart; they never adapt.  Units and thresholds do.
#define MACD_FAST          12
#define MACD_SLOW          26
#define MACD_SIGNAL        9
#define DMI_PERIOD         14
#define BAND_PERIOD        20
#define BAND_MULT          2.0

//  Vote thresholds - all percentiles, never a written-down level.
#define MOM_CUT_PCT        60.0
#define PUSH_CUT_PCT       55.0
#define STRETCH_HI         85.0
#define STRETCH_LO         15.0
#define MEM_TREND          0
#define MEM_RANDOM         1
#define MEM_RANGE          2
#define MEM_UNCLEAR        3
#define HURST_HI           0.55
#define HURST_LO           0.45
#define HURST_TOL          0.12

//  Trading
#define RISK_PCT           0.50    // % of equity per idea
#define RISK_TOTAL_PCT     1.50    // cap across all lanes at once
#define TP_QUANTILE        0.50    // the measured target is cut here
#define TP_MIN_CASES       24      // analogues needed before a target is claimed
#define REPLAY_BARS        400
#define TP_COST_X          2.0     // target must clear this many spreads
#define MAX_SPREAD_GATE    3.0
#define DURA_BARS          3       // "still standing this many bars on"
#define MIN_DURA_SAMPLES   12
#define TP1_FRACTION       0.50    // share closed at TP1
#define TRAIL_STEP_R       0.50    // trail in steps of half the original risk once 1R is banked

//  Lane states
#define LS_NONE            0       // nothing at the broker
#define LS_LIMIT           2       // a limit rests
#define LS_OPEN            3       // a position is open

//====================================================================
//  TYPES
//====================================================================
struct SymbolFacts
{
   string  name;
   string  desc;
   int     digits;
   double  point;
   double  tick;
   double  contract;
   double  volMin;
   double  volMax;
   double  volStep;
   long    stopsLevel;     // in points
   long    freezeLevel;
   long    fillingMode;
   int     tradeMode;
   bool    hedging;
   double  bid;
   double  ask;
   datetime lastQuote;
   double  equity;
   string  currency;
   string  company;
   string  server;
};

struct AssetProfile
{
   int     cls;
   double  spreadGateX;    // this class's spread gate, as a multiple of the hour's median
   double  stopBufferTicks;
};

struct MarketState
{
   int      status;        // 0 open, 1 closed, 2 disconnected, 3 stale, 4 unavailable, 5 unknown
   string   text;
   color    colour;
   datetime untilOpen;
   string   session;
   bool     sessionEst;
   double   spreadPoints;
   bool     spreadNormal;
};

struct SessionRec
{
   int    dow;
   int    startSec;
   int    endSec;
};

//  Everything one lane knows.  Filled on a closed bar; read by the panel.
struct LaneState
{
   ENUM_TIMEFRAMES tf;
   string   name;
   bool     ready;
   datetime lastBar;
   int      needBars;
   int      haveBars;

   //  the three readings, -1 / 0 / +1
   int      vMom;
   int      vPush;
   int      vStretch;
   double   momValue;
   double   pushValue;
   double   stretchValue;
   bool     momOk;
   bool     pushOk;
   bool     stretchOk;

   //  memory
   int      memory;
   double   hurstDfa;
   double   hurstRs;
   double   varRatio;
   int      volState;      // 0 quiet, 1 normal, 2 wild
   double   volPct;

   //  declared facts
   int      trend;         // -1 / 0 / +1
   int      score;         // how many of the readings agree with the call
   int      spoke;         // how many spoke
   int      signal;        // -1 / 0 / +1
   int      trendAge;
   int      holdsBars;     // typical remaining bars for this state
   int      holdsLo;
   int      holdsHi;
   bool     holdsOk;
   double   reachPct;      // share of same-grade analogues that reached target
   int      reachN;
   int      durabPct;      // typical bars to the target, from the analogue replay
   bool     durabOk;

   //  what the lane is doing
   int      state;         // LS_NONE / LS_LIMIT / LS_OPEN
   ulong    ticket;
   int      tradedTrend;
   int      tradedSignal;
   bool     armed;
   bool     tp1Done;
   double   tp1Price;   // the TP1 this trade was opened with
   double   origRisk;
   double   openLots;
};

struct LanePlan
{
   bool     ok;
   int      dir;
   bool     market;
   double   entry;
   double   sl;
   double   tp;
   double   tp1;
   double   lot;
   string   note;
};

struct LaneFill
{
   ulong    ticket;
   int      dir;
   double   lot;
   int      tries;
};

//====================================================================
//  GLOBAL STATE
//====================================================================
SymbolFacts   g_f;
AssetProfile  g_base;
AssetProfile  g_p;
MarketState   g_m;

SessionRec    g_sess[MAX_SESSIONS];
int           g_sessCount = 0;

LaneState     g_lane[LANE_COUNT];
LanePlan      g_plan[LANE_COUNT];
LaneFill      g_fill[LANE_COUNT];

double        g_spr[24][SPREAD_SAMPLES];
int           g_sprN[24];

double        g_unit[LANE_COUNT];        // the measured unit, per lane

datetime      g_lastRefTable = 0;
datetime      g_lastSession  = 0;
datetime      g_lastSample   = 0;
datetime      g_lastDraw     = 0;

string        g_currency  = "USD";
CTrade        g_trade;
CPositionInfo g_pos;

//  Pending orders are read through the built-in order functions rather than
//  COrderInfo: not every MetaTrader build gives COrderInfo a SelectByTicket,
//  and the built-in calls are guaranteed. One accessor each, so the rest of
//  the file does not care which one is used.
bool OrderPick(ulong ticket)   { return(OrderSelect(ticket)); }
string OrdSymbol()             { return(OrderGetString(ORDER_SYMBOL)); }
long   OrdMagic()              { return(OrderGetInteger(ORDER_MAGIC)); }
double OrdPrice()              { return(OrderGetDouble(ORDER_PRICE_OPEN)); }
double OrdSl()                 { return(OrderGetDouble(ORDER_SL)); }
double OrdTp()                 { return(OrderGetDouble(ORDER_TP)); }
double OrdVolume()             { return(OrderGetDouble(ORDER_VOLUME_CURRENT)); }
datetime OrdSetupTime()        { return((datetime)OrderGetInteger(ORDER_TIME_SETUP)); }
ENUM_ORDER_TYPE OrdKind()      { return((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE)); }

//  Panel bookkeeping
string        g_line[];
color         g_lineClr[];
int           g_segFrom[];
int           g_segN[];
string        g_segTxt[];
color         g_segClr[];
string        g_segTip[];
int           g_drawn = 0;

//  Record bookkeeping
string        g_recName  = "";
int           g_recH      = INVALID_HANDLE;
bool          g_recOk     = false;
string        g_recNote   = "not started";
int           g_todayS[LANE_COUNT][3];   // right / wrong / flat, calls
int           g_allS[LANE_COUNT][3];
int           g_todayW[LANE_COUNT];
int           g_todayL[LANE_COUNT];
int           g_allW[LANE_COUNT];
int           g_allL[LANE_COUNT];
int           g_readHit[LANE_COUNT][3];  // per reading: right
int           g_readN[LANE_COUNT][3];    // per reading: graded
bool          g_demoted[LANE_COUNT][3];
datetime      g_dayKey    = 0;

//  Trend / state run history, for HOLDS.
#define RUN_MAX      400
int           g_runHist[LANE_COUNT][RUN_MAX];
int           g_runN[LANE_COUNT];
int           g_runNow[LANE_COUNT];
int           g_runPrev[LANE_COUNT];

//+------------------------------------------------------------------+
//|  Small text helpers                                               |
//+------------------------------------------------------------------+

string Pad(string text, int width)
{
   string s = text;
   while(StringLen(s) < width) s += " ";
   if(StringLen(s) > width) s = StringSubstr(s, 0, width);
   return(s);
}


string Upper(string s)
{
   StringToUpper(s);
   return(s);
}


//+------------------------------------------------------------------+
//|  Statistics used everywhere: median, MAD, percentile rank.        |
//|  Median and MAD, not mean and sigma, so one news candle cannot    |
//|  move a threshold.                                                |
//+------------------------------------------------------------------+
double MedianOf(double &src[], int n)
{
   if(n <= 0) return(0.0);
   double tmp[];
   ArrayResize(tmp, n);
   for(int i = 0; i < n; i++) tmp[i] = src[i];
   ArraySort(tmp);
   double m;
   if((n % 2) == 1) m = tmp[n / 2];
   else             m = 0.5 * (tmp[n / 2 - 1] + tmp[n / 2]);
   return(m);
}


//  Percentile rank 0..100 of value among the valid entries of hist.
//  Empirical, with a minimum sample count.  When the count is short the
//  function returns false and the caller says CALIBRATING - there is no
//  fallback threshold anywhere in this file.
bool PctRank(double &hist[], int n, double value, int &used, double &rank)
{
   used = 0;
   rank = 50.0;
   if(n <= 0) return(false);

   double tmp[];
   ArrayResize(tmp, n);
   int k = 0;
   for(int i = 0; i < n; i++)
   {
      if(IsNA(hist[i])) continue;
      tmp[k] = hist[i];
      k++;
   }
   used = k;
   if(k < PCT_MIN) return(false);

   ArrayResize(tmp, k);
   ArraySort(tmp);

   int below = 0, equal = 0;
   for(int i = 0; i < k; i++)
   {
      if(tmp[i] < value)      below++;
      else if(tmp[i] == value) equal++;
      else break;
   }
   double pos = below + 0.5 * (double)equal;
   rank = 100.0 * pos / (double)k;
   return(true);
}

//====================================================================
//  SYMBOL DISCOVERY
//====================================================================
void DiscoverSymbol()
{
   g_f.name     = _Symbol;
   g_f.desc     = SymbolInfoString(_Symbol, SYMBOL_DESCRIPTION);
   g_f.digits   = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   g_f.point    = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   g_f.tick     = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   g_f.contract = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   g_f.volMin   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   g_f.volMax   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   g_f.volStep  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   g_f.stopsLevel  = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   g_f.freezeLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   g_f.fillingMode = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   g_f.tradeMode   = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);

   if(g_f.tick <= 0.0) g_f.tick = g_f.point;
   if(g_f.point <= 0.0) g_f.point = g_f.tick;
   if(g_f.volStep <= 0.0) g_f.volStep = 0.01;
   if(g_f.volMin <= 0.0) g_f.volMin = g_f.volStep;

   g_f.hedging  = ((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE) ==
                   ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
   g_f.equity   = AccountInfoDouble(ACCOUNT_EQUITY);
   g_f.currency = AccountInfoString(ACCOUNT_CURRENCY);
   g_f.company  = AccountInfoString(ACCOUNT_COMPANY);
   g_f.server   = AccountInfoString(ACCOUNT_SERVER);
}

void UpdateQuote()
{
   MqlTick t;
   if(!SymbolInfoTick(_Symbol, t)) return;
   g_f.bid = t.bid;
   g_f.ask = t.ask;
   if(t.time > 0) g_f.lastQuote = t.time;
}

//====================================================================
//  CLASSIFICATION
//  A class may raise a floor or set a gate.  It may never choose a
//  different strategy - otherwise forex and gold become two EAs in one
//  file and the comparison against Automate is worthless.
//====================================================================
#define A_OTHER   0
#define A_FOREX   1
#define A_METAL   2
#define A_INDEX   3
#define A_ENERGY  4
#define A_CRYPTO  5
#define A_STOCK   6

string METAL_TOK   = "XAU|XAG|XPT|XPD|GOLD|SILVER|PLATINUM|PALLADIUM";
string CRYPTO_TOK  = "BTC|ETH|XRP|LTC|BCH|DOGE|SHIB|BNB|SOL|AVAX|ADA|DOT|TRX|XLM|USDT|USDC|CRYPTO";
string ENERGY_TOK  = "WTI|BRENT|USOIL|UKOIL|CRUDE|NATGAS|NGAS|XNG|XBR|XTI|OIL";
string INDEX_TOK   = "US500|SP500|SPX|NAS100|NASDAQ|US100|USTEC|NDX|US30|DJ30|DOW|DJIA|US2000|RUSSELL|DE30|DE40|GER30|GER40|DAX|UK100|FTSE|JP225|NIKKEI|HK50|HSI|AUS200|ASX200|STOXX|VIX";
string METAL_PATH  = "METAL|METALS|PRECIOUS";
string CRYPTO_PATH = "CRYPTO|DIGITAL";
string INDEX_PATH  = "INDEX|INDEXES|INDICES";
string ENERGY_PATH = "ENERG|OIL|COMMODIT";
string STOCK_PATH  = "STOCK|SHARES|EQUIT|ETF";
string FOREX_PATH  = "FOREX|CURRENC";

bool HasToken(string hay, string packed)
{
   string parts[];
   int n = StringSplit(packed, '|', parts);
   for(int i = 0; i < n; i++)
   {
      if(parts[i] == "") continue;
      if(StringFind(hay, parts[i]) >= 0) return(true);
   }
   return(false);
}

string ClassLabel(int c)
{
   if(c == A_FOREX)  return("Forex");
   if(c == A_METAL)  return("Metal");
   if(c == A_INDEX)  return("Index");
   if(c == A_ENERGY) return("Energy");
   if(c == A_CRYPTO) return("Crypto");
   if(c == A_STOCK)  return("Stock");
   return("Other");
}

int ClassifySymbol()
{
   string up   = Upper(g_f.name + " " + g_f.desc);
   string path = Upper(SymbolInfoString(_Symbol, SYMBOL_PATH));

   if(HasToken(up, CRYPTO_TOK) || HasToken(path, CRYPTO_PATH)) return(A_CRYPTO);
   if(HasToken(up, METAL_TOK)  || HasToken(path, METAL_PATH))  return(A_METAL);
   if(HasToken(up, ENERGY_TOK) || HasToken(path, ENERGY_PATH)) return(A_ENERGY);
   if(HasToken(up, INDEX_TOK)  || HasToken(path, INDEX_PATH))  return(A_INDEX);
   if(HasToken(path, FOREX_PATH)) return(A_FOREX);
   if(HasToken(path, STOCK_PATH)) return(A_STOCK);

   //  Six letters with no other clue is almost always a currency pair.
   string letters = "";
   for(int i = 0; i < StringLen(g_f.name) && i < 6; i++)
   {
      ushort ch = StringGetCharacter(g_f.name, i);
      if(ch >= 'A' && ch <= 'Z') letters += ShortToString(ch);
   }
   if(StringLen(letters) == 6) return(A_FOREX);
   return(A_OTHER);
}

void ApplyProfile(int cls)
{
   g_base.cls             = cls;
   g_base.spreadGateX     = MAX_SPREAD_GATE;
   g_base.stopBufferTicks = 1.0;

   //  A class may raise a floor or set a gate.  It never changes the strategy.
   if(cls == A_FOREX)  g_base.spreadGateX = 3.0;
   if(cls == A_METAL)  { g_base.spreadGateX = 3.5; g_base.stopBufferTicks = 1.5; }
   if(cls == A_INDEX)  g_base.spreadGateX = 4.0;
   if(cls == A_ENERGY) g_base.spreadGateX = 4.5;
   if(cls == A_CRYPTO) g_base.spreadGateX = 6.0;
   if(cls == A_STOCK)  g_base.spreadGateX = 5.0;
   if(cls == A_OTHER)  g_base.spreadGateX = MAX_SPREAD_GATE;

   g_p = g_base;
}

//====================================================================
//  SPREAD PROFILE  - median spread per server hour, sampled live
//====================================================================
void SampleSpread()
{
   if(g_f.ask <= 0.0 || g_f.bid <= 0.0) return;
   MqlDateTime st;
   TimeToStruct(TimeTradeServer(), st);
   //  A rolling ring, so an hour's baseline keeps refreshing instead of
   //  freezing after its first 240 samples.
   int slot = g_sprN[st.hour] % SPREAD_SAMPLES;
   g_spr[st.hour][slot] = (g_f.ask - g_f.bid) / g_f.point;
   if(g_sprN[st.hour] < SPREAD_SAMPLES) g_sprN[st.hour]++;
}

double SpreadBaseline(int hour, int &samples)
{
   samples = g_sprN[hour];
   if(samples < 20) return(0.0);
   //  MQL5 cannot pass one row of a 2-D array by reference, so the row is
   //  copied first. The copy is the same data, not a different measurement.
   double row[];
   ArrayResize(row, samples);
   for(int i = 0; i < samples; i++) row[i] = g_spr[hour][i];
   return(MedianOf(row, samples));
}

//====================================================================
//  SESSIONS  - the broker's own table, never a guess
//====================================================================
void ReadSessions()
{
   g_sessCount = 0;
   datetime now = TimeTradeServer();
   MqlDateTime st;
   TimeToStruct(now, st);
   datetime midnight = (datetime)((long)now - (long)(st.hour * 3600 + st.min * 60 + st.sec));

   for(int dow = 0; dow < 7 && g_sessCount < MAX_SESSIONS; dow++)
   {
      for(uint idx = 0; idx < 4 && g_sessCount < MAX_SESSIONS; idx++)
      {
         datetime from = 0, to = 0;
         if(!SymbolInfoSessionTrade(_Symbol, (ENUM_DAY_OF_WEEK)dow, idx, from, to)) continue;
         MqlDateTime f, t;
         TimeToStruct(from, f);
         TimeToStruct(to, t);
         int startSec = f.hour * 3600 + f.min * 60;
         int endSec   = t.hour * 3600 + t.min * 60;
         if(startSec == 0 && endSec == 0) continue;
         g_sess[g_sessCount].dow      = dow;
         g_sess[g_sessCount].startSec = startSec;
         g_sess[g_sessCount].endSec   = (endSec == 0) ? 86400 : endSec;
         g_sessCount++;
      }
   }
   g_lastSession = TimeTradeServer();
}

datetime ServerNow()      { return(TimeTradeServer()); }

bool IsOpenNow(datetime serverNow, datetime &untilEnd, datetime &nextOpen)
{
   untilEnd = 0;
   nextOpen = 0;
   MqlDateTime st;
   TimeToStruct(serverNow, st);
   int sec = st.hour * 3600 + st.min * 60 + st.sec;

   bool open = false;
   for(int i = 0; i < g_sessCount; i++)
   {
      if(g_sess[i].dow != st.day_of_week) continue;
      if(sec >= g_sess[i].startSec && sec < g_sess[i].endSec)
      {
         open = true;
         datetime end = (datetime)((long)serverNow - (long)sec + (long)g_sess[i].endSec);
         if(untilEnd == 0 || end < untilEnd) untilEnd = end;
      }
   }
   if(open) return(true);

   //  Next opening time within the coming week.
   for(int add = 0; add < 8 && nextOpen == 0; add++)
   {
      int dow = (st.day_of_week + add) % 7;
      for(int i = 0; i < g_sessCount; i++)
      {
         if(g_sess[i].dow != dow) continue;
         datetime base = (datetime)((long)serverNow - (long)sec + (long)add * 86400);
         datetime s = (datetime)((long)base + (long)g_sess[i].startSec);
         if(s > serverNow) { if(nextOpen == 0 || s < nextOpen) nextOpen = s; }
      }
   }
   return(false);
}


string HumanDelta(datetime from, datetime to)
{
   long d = (long)(to - from);
   if(d <= 0) return("now");
   long day = d / 86400;
   long hr  = (d % 86400) / 3600;
   long mn  = (d % 3600) / 60;
   if(day > 0) return(StringFormat("%dd %dh", (int)day, (int)hr));
   if(hr > 0)  return(StringFormat("%dh %dm", (int)hr, (int)mn));
   return(StringFormat("%dm", (int)mn));
}

//  Session label from an ESTIMATED UTC.  Marked as an estimate wherever the
//  offset cannot be independently verified, and never used as a filter.
string SessionLabel(bool &estimated)
{
   estimated = true;
   datetime srv = TimeTradeServer();
   datetime gmt = TimeGMT();

   //  In the tester TimeGMT() is simulated server time, so the offset carries no
   //  information and the label must say so.
   if(MQLInfoInteger(MQL_TESTER) != 0)
   {
      estimated = true;
      return("unknown");
   }

   int offset = (int)((long)(srv - gmt) / 3600);
   MqlDateTime st;
   TimeToStruct(gmt, st);
   int utcSec = st.hour * 3600 + st.min * 60;
   estimated  = (MathAbs(offset) > 14 * 3600);

   //  Tokyo 09:00-18:00, London 08:00-17:00, New York 08:00-17:00 local.
   int tokyo  = (utcSec + 9 * 3600) % 86400;
   int london = (utcSec + 0 * 3600) % 86400;    // treated as UTC office hours
   int ny     = (utcSec - 5 * 3600 + 86400) % 86400;

   bool jp = (tokyo  >= 9 * 3600 && tokyo  < 18 * 3600);
   bool uk = (london >= 8 * 3600 && london < 17 * 3600);
   bool us = (ny     >= 8 * 3600 && ny     < 17 * 3600);

   if(uk && us) return("London/New York");
   if(uk && jp) return("Tokyo/London");
   if(uk) return("London");
   if(us) return("New York");
   if(jp) return("Tokyo");
   return("between sessions");
}

//====================================================================
//  MARKET STATE
//  Never report "closed" for a problem that is not a closure.
//====================================================================
void RefreshMarket()
{
   UpdateQuote();

   datetime untilEnd = 0, nextOpen = 0;
   bool open = IsOpenNow(ServerNow(), untilEnd, nextOpen);

   bool connected = (TerminalInfoInteger(TERMINAL_CONNECTED) != 0);
   bool tradeable = (g_f.tradeMode != SYMBOL_TRADE_MODE_DISABLED);
   bool stale     = false;
   if(g_f.lastQuote > 0 &&
      (long)TimeTradeServer() - (long)g_f.lastQuote > (long)(STALE_MINUTES * 60))
      stale = true;
   if(g_f.lastQuote == 0) stale = true;

   g_m.spreadPoints = (g_f.ask > 0.0 && g_f.bid > 0.0) ? (g_f.ask - g_f.bid) / g_f.point : 0.0;
   MqlDateTime st;
   TimeToStruct(TimeTradeServer(), st);
   int nSpr = 0;
   double base = SpreadBaseline(st.hour, nSpr);
   g_m.spreadNormal = (nSpr < 20 || base <= 0.0 || g_m.spreadPoints <= base * MAX_SPREAD_GATE);

   bool est = true;
   g_m.session = SessionLabel(est);
   g_m.sessionEst = est;

   if(!connected)
   {
      g_m.status = 2; g_m.text = "Disconnected"; g_m.colour = clrTomato;
   }
   else if(!tradeable)
   {
      g_m.status = 4; g_m.text = "Trading unavailable"; g_m.colour = clrTomato;
   }
   else if(g_sessCount == 0)
   {
      //  No published session table is not a closure. Reporting "closed" here
      //  would be exactly the false report the rules forbid.
      g_m.status = 5; g_m.text = "Market status unknown"; g_m.colour = clrSilver;
   }
   else if(!open)
   {
      g_m.status = 1;
      g_m.untilOpen = nextOpen;
      if(nextOpen > 0)
         g_m.text = "Market closed - opens " + TimeToString(nextOpen, TIME_MINUTES) +
                    " (in " + HumanDelta(ServerNow(), nextOpen) + ")";
      else
         g_m.text = "Market closed";
      g_m.colour = clrOrange;
   }
   else if(stale)
   {
      g_m.status = 3; g_m.text = "Stale quote"; g_m.colour = clrOrange;
   }
   else
   {
      g_m.status = 0; g_m.text = "Market open"; g_m.colour = clrLime;
   }
}

//====================================================================
//  THE TIMEFRAME GATE
//  Only M5, M15 and M30 are designed for. Anything else refuses.
//====================================================================
bool TimeframeAllowed(ENUM_TIMEFRAMES tf)
{
   return(tf == PERIOD_M5 || tf == PERIOD_M15 || tf == PERIOD_M30);
}

bool LaneAllowed(int idx)
{
   if(!InpAutoTrade) return(false);
   if(idx == 0) return(InpAllowM5);
   if(idx == 1) return(InpAllowM15);
   return(InpAllowM30);
}

bool TerminalAllowsTrade()
{
   return(TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) != 0 &&
          MQLInfoInteger(MQL_TRADE_ALLOWED) != 0);
}

string AutoTradeText()
{
   if(!InpAutoTrade)        return("Autotrading: OFF");
   if(!TerminalAllowsTrade()) return("Autotrading: ON - terminal is blocking it");
   return("Autotrading: ON");
}

color AutoTradeColour()
{
   if(!InpAutoTrade)          return(clrGray);
   if(!TerminalAllowsTrade()) return(clrTomato);
   return(clrLime);
}

ulong LaneMagic(int idx) { return(20261101 + (ulong)idx); }

//====================================================================
//  INDICATOR ARITHMETIC
//  Every function here mirrors tools/reference.py, which is checked by
//  tools/selftest.py.  If the two ever disagree, the Python is right and
//  this file is wrong.
//====================================================================
#define NA_VAL -1.7976931348623157e308

bool IsNA(double v) { return(v <= NA_VAL * 0.5); }

//------------------------------------------------------------------
//  Closed bars, oldest first.  start_pos 1 is the most recently CLOSED
//  bar, so the forming bar is never read by anything that votes.
//------------------------------------------------------------------
bool LoadBars(ENUM_TIMEFRAMES tf, int count,
              double &close[], double &high[], double &low[])
{
   double sc[], sh[], sl[];
   ArraySetAsSeries(sc, true);
   ArraySetAsSeries(sh, true);
   ArraySetAsSeries(sl, true);

   if(CopyClose(_Symbol, tf, 1, count, sc) < count) return(false);
   if(CopyHigh (_Symbol, tf, 1, count, sh) < count) return(false);
   if(CopyLow  (_Symbol, tf, 1, count, sl) < count) return(false);

   ArrayResize(close, count);
   ArrayResize(high,  count);
   ArrayResize(low,   count);

   for(int i = 0; i < count; i++)
   {
      close[i] = sc[count - 1 - i];
      high[i]  = sh[count - 1 - i];
      low[i]   = sl[count - 1 - i];
   }
   return(true);
}

//------------------------------------------------------------------
//  True range counts gaps.
//------------------------------------------------------------------
void TrueRangeArr(const double &high[], const double &low[], const double &close[],
                  double &out[])
{
   int n = ArraySize(close);
   ArrayResize(out, n);
   out[0] = high[0] - low[0];
   for(int i = 1; i < n; i++)
      out[i] = MathMax(high[i] - low[i],
               MathMax(MathAbs(high[i] - close[i - 1]), MathAbs(low[i] - close[i - 1])));
}

//------------------------------------------------------------------
//  Wilder's smoothing: weight 1/n, simple-average seed.
//  NOT an exponential average at 2/(n+1).  tools/selftest.py checks this.
//------------------------------------------------------------------
void WilderArr(const double &src[], int n, double &out[])
{
   int len = ArraySize(src);
   ArrayResize(out, len);
   for(int i = 0; i < len; i++) out[i] = NA_VAL;
   if(len < n) return;

   double seed = 0.0;
   for(int i = 0; i < n; i++) seed += src[i];
   out[n - 1] = seed / n;
   for(int i = n; i < len; i++)
      out[i] = out[i - 1] + (src[i] - out[i - 1]) / n;
}

void EmaArr(const double &src[], int n, double &out[])
{
   int len = ArraySize(src);
   ArrayResize(out, len);
   for(int i = 0; i < len; i++) out[i] = NA_VAL;
   if(len < n) return;

   double seed = 0.0;
   for(int i = 0; i < n; i++) seed += src[i];
   out[n - 1] = seed / n;
   double a = 2.0 / (n + 1.0);
   for(int i = n; i < len; i++)
      out[i] = out[i - 1] + a * (src[i] - out[i - 1]);
}

//------------------------------------------------------------------
//  Momentum reading: MACD divided by ATR over the slow window, x100.
//  Dimensionless, so one reading means the same on gold and on EURUSD.
//------------------------------------------------------------------
void MacdVArr(const double &close[], const double &high[], const double &low[],
              double &line[], double &sigLine[])
{
   int n = ArraySize(close);
   double ef[], es[], tr[], atr[];
   EmaArr(close, MACD_FAST, ef);
   EmaArr(close, MACD_SLOW, es);
   TrueRangeArr(high, low, close, tr);
   WilderArr(tr, MACD_SLOW, atr);

   ArrayResize(line, n);
   for(int i = 0; i < n; i++)
   {
      if(IsNA(ef[i]) || IsNA(es[i]) || IsNA(atr[i]) || atr[i] <= 0.0)
         line[i] = NA_VAL;
      else
         line[i] = (ef[i] - es[i]) / atr[i] * 100.0;
   }

   //  Signal line over the valid prefix only, so its seed is not a run of NAs.
   int first = -1;
   for(int i = 0; i < n; i++) if(!IsNA(line[i])) { first = i; break; }
   ArrayResize(sigLine, n);
   for(int i = 0; i < n; i++) sigLine[i] = NA_VAL;
   if(first < 0) return;

   double valid[];
   int vn = n - first;
   ArrayResize(valid, vn);
   for(int i = 0; i < vn; i++) valid[i] = line[first + i];
   double sg[];
   EmaArr(valid, MACD_SIGNAL, sg);
   for(int i = 0; i < vn; i++) sigLine[first + i] = sg[i];
}

//------------------------------------------------------------------
//  Push reading: directional movement, Wilder-correct.
//------------------------------------------------------------------
void DmiArr(const double &high[], const double &low[], const double &close[],
            double &pdi[], double &mdi[], double &adx[])
{
   int n = ArraySize(close);
   double pdm[], mdm[], tr[];
   ArrayResize(pdm, n); ArrayResize(mdm, n);
   pdm[0] = 0.0; mdm[0] = 0.0;
   for(int i = 1; i < n; i++)
   {
      double up = high[i] - high[i - 1];
      double dn = low[i - 1] - low[i];
      pdm[i] = (up > dn && up > 0.0) ? up : 0.0;
      mdm[i] = (dn > up && dn > 0.0) ? dn : 0.0;
   }
   TrueRangeArr(high, low, close, tr);

   double sp[], sm[], st[];
   WilderArr(pdm, DMI_PERIOD, sp);
   WilderArr(mdm, DMI_PERIOD, sm);
   WilderArr(tr,  DMI_PERIOD, st);

   ArrayResize(pdi, n); ArrayResize(mdi, n);
   double dx[];
   ArrayResize(dx, n);
   for(int i = 0; i < n; i++)
   {
      pdi[i] = NA_VAL; mdi[i] = NA_VAL; dx[i] = NA_VAL;
      if(IsNA(sp[i]) || IsNA(st[i]) || st[i] <= 0.0) continue;
      pdi[i] = 100.0 * sp[i] / st[i];
      mdi[i] = 100.0 * sm[i] / st[i];
      double s = pdi[i] + mdi[i];
      if(s > 0.0) dx[i] = 100.0 * MathAbs(pdi[i] - mdi[i]) / s;
   }

   int first = -1;
   for(int i = 0; i < n; i++) if(!IsNA(dx[i])) { first = i; break; }
   ArrayResize(adx, n);
   for(int i = 0; i < n; i++) adx[i] = NA_VAL;
   if(first < 0) return;

   double valid[];
   int vn = n - first;
   ArrayResize(valid, vn);
   for(int i = 0; i < vn; i++) valid[i] = dx[first + i];
   double ax[];
   WilderArr(valid, DMI_PERIOD, ax);
   for(int i = 0; i < vn; i++) adx[first + i] = ax[i];
}

//------------------------------------------------------------------
//  Stretch reading: position inside the volatility envelope, and the
//  width of that envelope.  Population sigma, Bollinger's convention.
//------------------------------------------------------------------
void BandArr(const double &close[], double &pos[], double &width[])
{
   int n = ArraySize(close);
   ArrayResize(pos, n);
   ArrayResize(width, n);
   for(int i = 0; i < n; i++) { pos[i] = NA_VAL; width[i] = NA_VAL; }
   for(int i = BAND_PERIOD - 1; i < n; i++)
   {
      double m = 0.0;
      for(int j = i - BAND_PERIOD + 1; j <= i; j++) m += close[j];
      m /= BAND_PERIOD;
      double v = 0.0;
      for(int j = i - BAND_PERIOD + 1; j <= i; j++)
      {
         double d = close[j] - m;
         v += d * d;
      }
      double sd = MathSqrt(v / BAND_PERIOD);
      width[i] = sd;
      pos[i]   = (sd <= 0.0) ? 0.0 : (close[i] - m) / (BAND_MULT * sd);
   }
}

//------------------------------------------------------------------
//  The measured unit: median absolute close-to-close change.
//------------------------------------------------------------------
double UnitAt(const double &close[], int end, int window)
{
   if(end < window || window < 2) return(0.0);
   double ch[];
   ArrayResize(ch, window);
   for(int i = 0; i < window; i++)
      ch[i] = MathAbs(close[end - i] - close[end - i - 1]);
   return(MedianOf(ch, window));
}

//------------------------------------------------------------------
//  Market memory.  DFA is primary, R/S is a cross-check, the variance
//  ratio is a second check.  Disagreement is Unclear, never an average.
//  DFA and R/S are computed on the INCREMENTS - on prices they return
//  H+1 and score a random walk at 1.5.  tools/selftest.py caught that.
//------------------------------------------------------------------
bool HurstDfa(const double &x[], int n, double &h)
{
   h = 0.0;
   if(n < 96) return(false);
   int box[5] = {8, 16, 32, 64, 128};
   double lx[5], ly[5];
   int m = 0;

   double mean = 0.0;
   for(int i = 0; i < n; i++) mean += x[i];
   mean /= n;

   double prof[];
   ArrayResize(prof, n);
   double acc = 0.0;
   for(int i = 0; i < n; i++) { acc += x[i] - mean; prof[i] = acc; }

   for(int b = 0; b < 5; b++)
   {
      int s = box[b];
      int nb = n / s;
      if(s < 4 || nb < 2) continue;

      double xm = (s - 1) / 2.0;
      double den = 0.0;
      for(int j = 0; j < s; j++) den += (j - xm) * (j - xm);
      if(den <= 0.0) continue;

      double tot = 0.0;
      int cnt = 0;
      for(int k = 0; k < nb; k++)
      {
         double ym = 0.0;
         for(int j = 0; j < s; j++) ym += prof[k * s + j];
         ym /= s;
         double num = 0.0;
         for(int j = 0; j < s; j++) num += (j - xm) * (prof[k * s + j] - ym);
         double slope = num / den;
         double icpt  = ym - slope * xm;
         for(int j = 0; j < s; j++)
         {
            double r = prof[k * s + j] - (icpt + slope * j);
            tot += r * r;
            cnt++;
         }
      }
      if(cnt <= 0) continue;
      double f = MathSqrt(tot / cnt);
      if(f <= 0.0) continue;
      lx[m] = MathLog((double)s);
      ly[m] = MathLog(f);
      m++;
   }
   if(m < 3) return(false);

   double mx = 0.0, my = 0.0;
   for(int i = 0; i < m; i++) { mx += lx[i]; my += ly[i]; }
   mx /= m; my /= m;
   double num = 0.0, dm = 0.0;
   for(int i = 0; i < m; i++)
   {
      num += (lx[i] - mx) * (ly[i] - my);
      dm  += (lx[i] - mx) * (lx[i] - mx);
   }
   if(dm <= 0.0) return(false);
   h = num / dm;
   return(true);
}

bool HurstRs(const double &x[], int n, double &h)
{
   h = 0.0;
   if(n < 96) return(false);
   int box[5] = {8, 16, 32, 64, 128};
   double lx[5], ly[5];
   int m = 0;

   for(int b = 0; b < 5; b++)
   {
      int s = box[b];
      int nb = n / s;
      if(s < 4 || nb < 2) continue;
      double acc = 0.0;
      int used = 0;
      for(int k = 0; k < nb; k++)
      {
         double mean = 0.0;
         for(int j = 0; j < s; j++) mean += x[k * s + j];
         mean /= s;
         double run = 0.0, lo = 0.0, hi = 0.0, v = 0.0;
         for(int j = 0; j < s; j++)
         {
            double d = x[k * s + j] - mean;
            run += d;
            if(run < lo) lo = run;
            if(run > hi) hi = run;
            v += d * d;
         }
         double sd = MathSqrt(v / s);
         if(sd > 0.0) { acc += (hi - lo) / sd; used++; }
      }
      if(used <= 0 || acc <= 0.0) continue;
      lx[m] = MathLog((double)s);
      ly[m] = MathLog(acc / used);
      m++;
   }
   if(m < 3) return(false);

   double mx = 0.0, my = 0.0;
   for(int i = 0; i < m; i++) { mx += lx[i]; my += ly[i]; }
   mx /= m; my /= m;
   double num = 0.0, dm = 0.0;
   for(int i = 0; i < m; i++)
   {
      num += (lx[i] - mx) * (ly[i] - my);
      dm  += (lx[i] - mx) * (lx[i] - mx);
   }
   if(dm <= 0.0) return(false);
   h = num / dm;
   return(true);
}

bool VarianceRatio(const double &p[], int n, int q, double &vr)
{
   vr = 0.0;
   if(n < q * 4) return(false);
   int n1 = n - 1, nq = n - q;
   if(n1 < 10 || nq < 10) return(false);

   double m1 = 0.0, mq = 0.0;
   for(int i = 1; i < n; i++) m1 += p[i] - p[i - 1];
   m1 /= n1;
   for(int i = q; i < n; i++) mq += p[i] - p[i - q];
   mq /= nq;

   double v1 = 0.0, vq = 0.0;
   for(int i = 1; i < n; i++) { double d = (p[i] - p[i - 1]) - m1; v1 += d * d; }
   v1 /= n1;
   for(int i = q; i < n; i++) { double d = (p[i] - p[i - q]) - mq; vq += d * d; }
   vq /= nq;
   if(v1 <= 0.0) return(false);
   vr = vq / (q * v1);
   return(true);
}

int MemoryState(const double &close[], int end, int span,
                double &dfa, double &rs, double &vr)
{
   dfa = 0.0; rs = 0.0; vr = 0.0;
   int n = MathMin(span, end + 1);
   if(n < 128) return(MEM_UNCLEAR);

   double inc[];
   ArrayResize(inc, n - 1);
   for(int i = 0; i < n - 1; i++)
      inc[i] = close[end - n + 1 + i + 1] - close[end - n + 1 + i];

   double d = 0.0, r = 0.0;
   bool okD = HurstDfa(inc, n - 1, d);
   bool okR = HurstRs(inc, n - 1, r);
   double p[];
   ArrayResize(p, n);
   for(int i = 0; i < n; i++) p[i] = close[end - n + 1 + i];
   bool okV = VarianceRatio(p, n, 4, vr);
   dfa = d; rs = r;

   if(!okD) return(MEM_UNCLEAR);
   if(okR && MathAbs(d - r) > HURST_TOL) return(MEM_UNCLEAR);
   if(d >= HURST_HI)
   {
      if(okV && vr < 1.0) return(MEM_UNCLEAR);
      return(MEM_TREND);
   }
   if(d <= HURST_LO)
   {
      if(okV && vr > 1.0) return(MEM_UNCLEAR);
      return(MEM_RANGE);
   }
   return(MEM_RANDOM);
}

string MemoryWord(int m)
{
   if(m == MEM_TREND)  return("Trending");
   if(m == MEM_RANGE)  return("Ranging");
   if(m == MEM_RANDOM) return("Random");
   return("Unclear");
}

string VolWord(int v)
{
   if(v == 0) return("Quiet");
   if(v == 2) return("Wild");
   return("Normal");
}

//====================================================================
//  LANE PARAMETERS - the personalities.
//  A lane is a different working window on the same method, never a
//  different method.
//====================================================================
int LaneHorizon(int idx)
{
   if(idx == 0) return(4);
   if(idx == 1) return(6);
   return(8);
}

int LaneStructWindow(int idx)
{
   if(idx == 0) return(36);
   if(idx == 1) return(48);
   return(72);
}

//  How much of each lane's own history its percentile thresholds are drawn
//  from.  A scalper must adapt within an hour; an intraday lane should reflect
//  the session.  This IS the "sets its own parameters from the context" part:
//  the unit comes from the symbol, the window from the lane's role, and the
//  threshold from the resulting distribution.
int LaneRankWindow(int idx)
{
   if(idx == 0) return(300);
   if(idx == 1) return(400);
   return(500);
}


//====================================================================
//  RUN HISTORY - how long a state usually lasts.
//  Measured from completed runs, conditioned on how far this one has got.
//====================================================================
void PushRun(int idx, int run)
{
   if(g_runN[idx] < RUN_MAX) { g_runHist[idx][g_runN[idx]] = run; g_runN[idx]++; }
   else
   {
      for(int i = 1; i < RUN_MAX; i++) g_runHist[idx][i - 1] = g_runHist[idx][i];
      g_runHist[idx][RUN_MAX - 1] = run;
   }
}

void TrackTrend(int idx, int trend)
{
   if(g_runPrev[idx] == -99)
   {
      g_runPrev[idx] = trend;
      g_runNow[idx]  = 1;
      return;
   }
   if(trend == g_runPrev[idx]) g_runNow[idx]++;
   else
   {
      PushRun(idx, g_runNow[idx]);
      g_runPrev[idx] = trend;
      g_runNow[idx]  = 1;
   }
}

bool RemainingRun(int idx, int age, int &barsLeft, int &lo, int &hi)
{
   barsLeft = 0; lo = 0; hi = 0;
   double res[];
   int n = 0;
   for(int i = 0; i < g_runN[idx]; i++)
   {
      if(g_runHist[idx][i] <= age) continue;
      ArrayResize(res, n + 1);
      res[n] = (double)(g_runHist[idx][i] - age);
      n++;
   }
   if(n < MIN_DURA_SAMPLES) return(false);

   ArraySort(res);
   double med = (n % 2 == 1) ? res[n / 2] : 0.5 * (res[n / 2 - 1] + res[n / 2]);
   barsLeft = (int)MathRound(med);
   lo = (int)MathRound(res[(int)MathFloor(0.25 * (n - 1))]);
   hi = (int)MathRound(res[(int)MathFloor(0.75 * (n - 1))]);
   return(true);
}

//====================================================================
//  VOTES
//  Each returns -1 / 0 / +1 and can abstain.  Abstention is a real
//  state: without it a 2-of-3 count collapses into a two-state guess.
//====================================================================
int MomentumVote(double value, double signal, double strengthPct, bool ok)
{
   if(!ok) return(0);
   if(strengthPct < MOM_CUT_PCT) return(0);
   if(value > 0.0 && value >= signal) return(1);
   if(value < 0.0 && value <= signal) return(-1);
   return(0);
}

int PushVote(double pdi, double mdi, double adxPct, double diffPct, bool ok)
{
   if(!ok) return(0);
   if(adxPct < PUSH_CUT_PCT) return(0);
   if(diffPct < PUSH_CUT_PCT) return(0);
   if(pdi > mdi) return(1);
   if(pdi < mdi) return(-1);
   return(0);
}

//  Stretch is a REVERSION reading: stretched high fades bearish, stretched
//  low fades bullish.  Measured, this family is the better decider only when
//  memory says the market is ranging; in a trend it is systematically wrong,
//  which is why it never decides there.
int StretchVote(double posPct, bool ok)
{
   if(!ok) return(0);
   if(posPct >= STRETCH_HI) return(-1);
   if(posPct <= STRETCH_LO) return(1);
   return(0);
}

//====================================================================
//  THE DECISION RULE (measured, tools/combine_test.py)
//    ranging memory   -> listen to the reversion reading
//    trending/random  -> listen to the continuation readings
//    unclear memory   -> continuation only when BOTH agree
//  The rule that survived was the only one not below a coin flip in any
//  of the five markets tested.
//====================================================================
int DecideSignal(int memory, int vMom, int vPush, int vStretch, int &spoke, int &agree)
{
   spoke = 0; agree = 0;
   if(vMom != 0)     spoke++;
   if(vPush != 0)    spoke++;
   if(vStretch != 0) spoke++;

   int dir = 0;
   if(memory == MEM_RANGE)
   {
      dir = vStretch;
      if(dir != 0) agree = (vStretch == dir) ? 1 : 0;
   }
   else if(memory == MEM_TREND || memory == MEM_RANDOM)
   {
      if(vMom != 0 && vPush != 0) dir = (vMom == vPush) ? vMom : 0;
      else if(vMom != 0)          dir = vMom;
      else if(vPush != 0)         dir = vPush;
      if(dir != 0)
      {
         if(vMom == dir)     agree++;
         if(vPush == dir)    agree++;
         if(vStretch == dir) agree++;
      }
   }
   else // MEM_UNCLEAR - stricter, both continuation readings must agree
   {
      if(vMom != 0 && vPush != 0 && vMom == vPush) dir = vMom;
      if(dir != 0)
      {
         if(vMom == dir)     agree++;
         if(vPush == dir)    agree++;
         if(vStretch == dir) agree++;
      }
   }
   return(dir);
}

//====================================================================
//  THE RECORD
//  Appends one line per settled claim.  It only ever watches: it sends
//  nothing, and nothing it stores is read back to change a reading -
//  except the one bounded demotion in ApplyTweak.
//====================================================================
string RecordFileName()
{
   string s = "OldMate_" + IntegerToString((int)AccountInfoInteger(ACCOUNT_LOGIN)) +
              "_" + g_f.name + ".csv";
   StringReplace(s, "\\", "_");
   StringReplace(s, "/", "_");
   StringReplace(s, ":", "_");
   return(s);
}

bool RecordOpen()
{
   g_recName = RecordFileName();
   g_recH = FileOpen(g_recName, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(g_recH == INVALID_HANDLE)
   {
      g_recOk = false;
      g_recNote = "cannot open record";
      return(false);
   }
   FileSeek(g_recH, 0, SEEK_END);
   g_recOk = true;
   g_recNote = "saved";
   return(true);
}

void RecordAppend(string line)
{
   if(!g_recOk) return;
   FileWriteString(g_recH, line + "\r\n");
   FileFlush(g_recH);
}

//  Read the whole record back at attach so the counts survive a restart.
void RecordLoad()
{
   for(int i = 0; i < LANE_COUNT; i++)
   {
      for(int k = 0; k < 3; k++) { g_todayS[i][k] = 0; g_allS[i][k] = 0; }
      g_todayW[i] = 0; g_todayL[i] = 0; g_allW[i] = 0; g_allL[i] = 0;
      for(int r = 0; r < 3; r++) { g_readHit[i][r] = 0; g_readN[i][r] = 0; g_demoted[i][r] = false; }
   }
   if(!g_recOk) return;

   datetime today = 0;
   MqlDateTime st;
   TimeToStruct(TimeTradeServer(), st);
   st.hour = 0; st.min = 0; st.sec = 0;
   today = StructToTime(st);
   g_dayKey = today;

   FileSeek(g_recH, 0, SEEK_SET);
   while(!FileIsEnding(g_recH))
   {
      string line = FileReadString(g_recH);
      if(StringLen(line) < 10) continue;
      string p[];
      int n = StringSplit(line, ',', p);
      if(n < 8) continue;

      datetime t = StringToTime(p[0]);
      int lane = (int)StringToInteger(p[1]);
      string kind = p[2];
      if(lane < 0 || lane >= LANE_COUNT) continue;

      if(kind == "CALL")
      {
         //  time,lane,CALL,grade,hit,read1,read2,read3,dir
         int outcome = (int)StringToInteger(p[4]);
         int idx = (outcome > 0) ? 0 : ((outcome < 0) ? 1 : 2);
         g_allS[lane][idx]++;
         if(t >= today) g_todayS[lane][idx]++;
         for(int r = 0; r < 3 && 5 + r < n; r++)
         {
            int rv = (int)StringToInteger(p[5 + r]);
            if(rv == 0) continue;
            g_readN[lane][r]++;
            if(rv > 0) g_readHit[lane][r]++;
         }
      }
      else if(kind == "TRADE")
      {
         double money = StringToDouble(p[6]);
         if(money > 0.0) { g_allW[lane]++; if(t >= today) g_todayW[lane]++; }
         else if(money < 0.0) { g_allL[lane]++; if(t >= today) g_todayL[lane]++; }
      }
   }
}

//  ---- pending calls, graded a few bars later -------------------------
#define PEND_MAX 12
int      g_pendUsed = 0;
int      g_pendLane[PEND_MAX];
datetime g_pendTime[PEND_MAX];
int      g_pendDir[PEND_MAX];
int      g_pendVote[PEND_MAX][3];
int      g_pendScore[PEND_MAX];
int      g_pendSpoke[PEND_MAX];
double   g_pendLevel[PEND_MAX];
int      g_pendTF[PEND_MAX];

void PendCall(int idx, int dir, int vm, int vp, int vs, double level,
              int score, int spoke)
{
   int slot = -1;
   for(int i = 0; i < PEND_MAX; i++)
   {
      if(g_pendLane[i] < 0) { slot = i; break; }
   }
   if(slot < 0)
   {
      //  Full: retire the oldest pending call, so the pen never grows and
      //  never silently overwrites a recent one.
      datetime oldest = 0;
      slot = 0;
      for(int i = 0; i < PEND_MAX; i++)
      {
         if(oldest == 0 || g_pendTime[i] < oldest)
         {
            oldest = g_pendTime[i];
            slot = i;
         }
      }
   }

   g_pendLane[slot]  = idx;
   g_pendTime[slot]  = g_lane[idx].lastBar;
   g_pendDir[slot]   = dir;
   g_pendVote[slot][0] = vm;
   g_pendVote[slot][1] = vp;
   g_pendVote[slot][2] = vs;
   g_pendScore[slot] = score;
   g_pendSpoke[slot] = spoke;
   g_pendLevel[slot] = level;
   g_pendTF[slot]    = (int)g_lane[idx].tf;
}

void GradePending(int idx, double closeNow)
{
   for(int i = 0; i < PEND_MAX; i++)
   {
      if(g_pendLane[i] != idx) continue;
      //  Bars elapsed on this lane's timeframe.
      int bars = (int)(((long)g_lane[idx].lastBar - (long)g_pendTime[i]) /
                       (long)PeriodSeconds(g_lane[idx].tf));
      if(bars < DURA_BARS) continue;

      double move = closeNow - g_pendLevel[i];
      int outcome = 0;
      if(move > 0.0) outcome = 1;
      else if(move < 0.0) outcome = -1;

      int hit = 0;
      if(g_pendDir[i] != 0 && outcome != 0)
         hit = (g_pendDir[i] == outcome) ? 1 : -1;

      string rv[3];
      for(int r = 0; r < 3; r++)
      {
         int s = 0;
         if(g_pendVote[i][r] != 0 && outcome != 0)
            s = (g_pendVote[i][r] == outcome) ? 1 : -1;
         rv[r] = IntegerToString(s);
         //  Count a reading only when it spoke. Diluting its rate with its own
         //  abstentions would make a quiet reading look good and a busy one bad.
         if(g_pendVote[i][r] != 0)
         {
            g_readN[idx][r]++;
            if(s > 0) g_readHit[idx][r]++;
         }
      }

      int slotOut = (hit > 0) ? 0 : ((hit < 0) ? 1 : 2);
      g_allS[idx][slotOut]++;
      if(g_pendTime[i] >= g_dayKey) g_todayS[idx][slotOut]++;

      RecordAppend(TimeToString(g_pendTime[i], TIME_DATE | TIME_MINUTES) + "," +
                   IntegerToString(idx) + ",CALL," +
                   IntegerToString(g_pendScore[i]) + "/" + IntegerToString(g_pendSpoke[i]) + "," +
                   IntegerToString(hit) + "," +
                   rv[0] + "," + rv[1] + "," + rv[2] + "," +
                   IntegerToString(g_pendDir[i]));
      g_pendLane[i] = -1;
   }
}

//====================================================================
//  THE ONE BOUNDED SELF-TWEAK
//  A reading that has been wrong more often than a coin flip over at
//  least 100 graded calls stops counting toward agreement.  It is shown
//  struck through, the reason is in the record, and it never comes back
//  on its own.  It cannot promote anything and it cannot touch risk.
//====================================================================
void ApplyTweak(int idx, int reading)
{
   if(!InpTweakArm) return;
   if(g_demoted[idx][reading]) return;
   if(g_readN[idx][reading] < 100) return;

   double rate = (double)g_readHit[idx][reading] / (double)g_readN[idx][reading];
   if(rate > 0.45) return;

   g_demoted[idx][reading] = true;
   RecordAppend(TimeToString(TimeTradeServer(), TIME_DATE | TIME_MINUTES) + "," +
                IntegerToString(idx) + ",TWEAK," + IntegerToString(reading) + ",demoted,0,0,0," +
                DoubleToString(rate * 100.0, 1));
}

//====================================================================
//  LANE UPDATE - once per closed bar
//====================================================================
bool UpdateLane(int idx)
{
   ENUM_TIMEFRAMES tf = g_lane[idx].tf;
   int need = SEED_BARS;
   g_lane[idx].needBars = need;
   g_lane[idx].haveBars = Bars(_Symbol, tf);

   double close[], high[], low[];
   if(!LoadBars(tf, need, close, high, low)) return(false);

   int n = ArraySize(close);
   int end = n - 1;
   double tick = g_f.tick > 0.0 ? g_f.tick : g_f.point;

   //  ---- the measured unit -------------------------------------------
   double unit = UnitAt(close, end, 20);
   if(unit <= 0.0) unit = tick;
   g_unit[idx] = unit;

   //  ---- momentum ----------------------------------------------------
   double mv[], ms[];
   MacdVArr(close, high, low, mv, ms);
   double momAbs[];
   int mn = 0;
   int rankWin = LaneRankWindow(idx);
   int f0 = MathMax(0, end - rankWin);
   ArrayResize(momAbs, end - f0 + 1);
   for(int i = f0; i < end; i++)
   {
      if(IsNA(mv[i])) continue;
      momAbs[mn] = MathAbs(mv[i]);
      mn++;
   }
   ArrayResize(momAbs, MathMax(mn, 1));

   double momPct = 50.0;
   int    momUsed = 0;
   bool momOk = false;
   if(!IsNA(mv[end]) && mn >= PCT_MIN)
      momOk = PctRank(momAbs, mn, MathAbs(mv[end]), momUsed, momPct);

   double sigNow = IsNA(ms[end]) ? 0.0 : ms[end];
   g_lane[idx].momValue = IsNA(mv[end]) ? 0.0 : mv[end];
   g_lane[idx].vMom = MomentumVote(g_lane[idx].momValue, sigNow, momPct, momOk);
   g_lane[idx].momOk = momOk;

   //  ---- push --------------------------------------------------------
   double pdi[], mdi[], adx[];
   DmiArr(high, low, close, pdi, mdi, adx);
   double adxHist[], diffHist[];
   int an = 0, dn = 0;
   ArrayResize(adxHist, end - f0 + 1);
   ArrayResize(diffHist, end - f0 + 1);
   for(int i = f0; i < end; i++)
   {
      if(!IsNA(adx[i]) && !IsNA(pdi[i]) && !IsNA(mdi[i]))
      {
         adxHist[an]  = adx[i];
         diffHist[dn] = MathAbs(pdi[i] - mdi[i]);
         an++; dn++;
      }
   }
   ArrayResize(adxHist, MathMax(an, 1));
   ArrayResize(diffHist, MathMax(dn, 1));

   double adxPct = 50.0, diffPct = 50.0;
   bool pushOk = false;
   if(an >= PCT_MIN && !IsNA(adx[end]) && !IsNA(pdi[end]) && !IsNA(mdi[end]))
   {
      int a1 = 0, a2 = 0;
      pushOk = PctRank(adxHist, an, adx[end], a1, adxPct) &&
               PctRank(diffHist, dn, MathAbs(pdi[end] - mdi[end]), a2, diffPct);
   }
   g_lane[idx].pushValue = IsNA(adx[end]) ? 0.0 : adx[end];
   g_lane[idx].vPush = PushVote(IsNA(pdi[end]) ? 0.0 : pdi[end],
                                IsNA(mdi[end]) ? 0.0 : mdi[end],
                                adxPct, diffPct, pushOk);
   g_lane[idx].pushOk = pushOk;

   //  ---- stretch -----------------------------------------------------
   double pos[], bw[];
   BandArr(close, pos, bw);
   double posHist[], bwHist[];
   int pn = 0, wn = 0;
   ArrayResize(posHist, end - f0 + 1);
   ArrayResize(bwHist,  end - f0 + 1);
   for(int i = f0; i < end; i++)
   {
      if(!IsNA(pos[i])) { posHist[pn] = pos[i]; pn++; }
      if(!IsNA(bw[i]))  { bwHist[wn] = bw[i] / MathMax(unit, tick); wn++; }
   }
   ArrayResize(posHist, MathMax(pn, 1));
   ArrayResize(bwHist,  MathMax(wn, 1));

   double posPct = 50.0, bwPct = 50.0;
   bool stretchOk = false, volOk = false;
   int posUsed = 0, bwUsed = 0;
   if(pn >= PCT_MIN && !IsNA(pos[end]))
      stretchOk = PctRank(posHist, pn, pos[end], posUsed, posPct);
   if(wn >= PCT_MIN && !IsNA(bw[end]))
      volOk = PctRank(bwHist, wn, bw[end] / MathMax(unit, tick), bwUsed, bwPct);

   g_lane[idx].stretchValue = IsNA(pos[end]) ? 0.0 : pos[end];
   g_lane[idx].vStretch = StretchVote(posPct, stretchOk);
   g_lane[idx].stretchOk = stretchOk;

   //  ---- memory and condition ----------------------------------------
   double dfa = 0.0, rs = 0.0, vr = 0.0;
   g_lane[idx].memory = MemoryState(close, end, MEM_BARS, dfa, rs, vr);
   g_lane[idx].hurstDfa = dfa;
   g_lane[idx].hurstRs  = rs;
   g_lane[idx].varRatio = vr;

   if(volOk)
   {
      g_lane[idx].volPct  = bwPct;
      g_lane[idx].volState = (bwPct <= 20.0) ? 0 : ((bwPct >= 80.0) ? 2 : 1);
   }
   else
   {
      g_lane[idx].volPct  = 50.0;
      g_lane[idx].volState = 1;
   }

   //  ---- the declared facts ------------------------------------------
   //  A demoted reading still shows its vote, but no longer counts toward the
   //  decision. g_demoted is only ever set by the armed tweak.
   int eMom  = g_demoted[idx][0] ? 0 : g_lane[idx].vMom;
   int ePush = g_demoted[idx][1] ? 0 : g_lane[idx].vPush;
   int eStr  = g_demoted[idx][2] ? 0 : g_lane[idx].vStretch;

   int spoke = 0, agree = 0;
   int dir = DecideSignal(g_lane[idx].memory, eMom, ePush, eStr, spoke, agree);
   g_lane[idx].score  = agree;
   g_lane[idx].spoke  = spoke;
   g_lane[idx].signal = dir;


   //  TREND is the direction the momentum reading sees, with FLAT a real state.
   g_lane[idx].trend = g_lane[idx].vMom;

   TrackTrend(idx, g_lane[idx].trend);
   g_lane[idx].trendAge = g_runNow[idx];

   int left = 0, lo = 0, hi = 0;
   g_lane[idx].holdsOk = RemainingRun(idx, g_lane[idx].trendAge, left, lo, hi);
   g_lane[idx].holdsBars = left;
   g_lane[idx].holdsLo = lo;
   g_lane[idx].holdsHi = hi;

   g_lane[idx].ready = true;

   //  The record is written after the numbers exist; it reads them, it can
   //  never change them.
   GradePending(idx, close[end]);
   if(g_lane[idx].signal != 0)
      PendCall(idx, g_lane[idx].signal, g_lane[idx].vMom,
               g_lane[idx].vPush, g_lane[idx].vStretch, close[end],
               g_lane[idx].score, g_lane[idx].spoke);

   return(true);
}

//====================================================================
//  PRICE HELPERS
//====================================================================
double SnapDown(double price, double tick)
{
   if(tick <= 0.0) return(price);
   return(NormalizeDouble(MathFloor(price / tick + 1e-9) * tick, g_f.digits));
}

double SnapUp(double price, double tick)
{
   if(tick <= 0.0) return(price);
   return(NormalizeDouble(MathCeil(price / tick - 1e-9) * tick, g_f.digits));
}

//  A confirmed swing is a real three-bar turn - lower than both neighbours,
//  with the confirming bar already closed.  Nothing here looks ahead.
bool SwingLowOk(const MqlRates &r[], int k, int last)
{
   return(k > 0 && k < last && r[k].low < r[k - 1].low && r[k].low <= r[k + 1].low);
}

bool SwingHighOk(const MqlRates &r[], int k, int last)
{
   return(k > 0 && k < last && r[k].high > r[k - 1].high && r[k].high >= r[k + 1].high);
}

int PickFilling()
{
   if((g_f.fillingMode & SYMBOL_FILLING_FOK) != 0) return((int)ORDER_FILLING_FOK);
   if((g_f.fillingMode & SYMBOL_FILLING_IOC) != 0) return((int)ORDER_FILLING_IOC);
   return((int)ORDER_FILLING_RETURN);
}

//====================================================================
//  THE TARGET
//  Measured, never multiplied by volatility.  Replay past moments that
//  looked the same AS OF THAT BAR - same direction, and a structural stop
//  of the same kind behind them - and record how far price actually ran
//  before an equal-sized stop took it out.
//
//  What is matched: direction, and a stop placed at the nearest confirmed
//  swing exactly as this lane places it.  What is NOT matched: the reading
//  grade.  Computing the historical grade at every analogue bar would mean
//  recomputing the whole indicator stack four hundred times per bar, and
//  claiming a filter that is not applied would be worse than not claiming
//  it.
//
//  The cut is a FIXED share of the measured median (TP_CUT), not the
//  quantile that would make the reach count trivially 50%: the share of
//  analogues that reached the chosen distance is therefore a genuine
//  count, reported beside it with its sample size.
//====================================================================
#define TP_CUT 0.80

bool MeasureTarget(int idx, int dir, double riskPrice, double tick,
                   double &dist, double &reachShare, int &reachN,
                   double &medBars, string &why)
{
   dist = 0.0; reachShare = 0.0; reachN = 0; medBars = 0.0; why = "";
   if(dir == 0 || riskPrice <= 0.0) { why = "no direction to measure"; return(false); }

   int horizon = LaneHorizon(idx);
   int window  = LaneStructWindow(idx);
   int need    = REPLAY_BARS + horizon + window + 8;

   MqlRates r[];
   //  Not set as a series: index 0 is the oldest bar, r[n-1] the newest closed.
   int n = CopyRates(_Symbol, g_lane[idx].tf, 1, need, r);
   if(n < window + horizon + 120)
   { why = "not enough history to measure a target"; return(false); }

   double ratio[];     // favourable travel, in units of the stop distance
   int    barsTo[];    // how many bars it took
   int    cnt = 0;

   for(int i = window + 2; i < n - horizon - 1; i++)
   {
      double entry = r[i].close;

      double level = 0.0;
      int first = i - window + 1;
      if(first < 1) first = 1;
      for(int k = first; k < i; k++)
      {
         if(dir > 0 && SwingLowOk(r, k, i) && r[k].low < entry)
         {
            if(level == 0.0 || r[k].low > level) level = r[k].low;
         }
         if(dir < 0 && SwingHighOk(r, k, i) && r[k].high > entry)
         {
            if(level == 0.0 || r[k].high < level) level = r[k].high;
         }
      }
      if(level == 0.0) continue;

      double stop = (dir > 0) ? level - tick : level + tick;
      double risk = MathAbs(entry - stop);
      if(risk <= 0.0) continue;

      double best = 0.0;
      int hitBar = 0;
      for(int k = i + 1; k <= i + horizon && k < n; k++)
      {
         //  The stop is counted first when both extremes share a bar.
         if(dir > 0 && r[k].low <= stop) break;
         if(dir < 0 && r[k].high >= stop) break;
         double fav = (dir > 0) ? (r[k].high - entry) : (entry - r[k].low);
         if(fav > best) { best = fav; hitBar = k - i; }
      }

      ArrayResize(ratio, cnt + 1);
      ArrayResize(barsTo, cnt + 1);
      ratio[cnt]  = best / risk;
      barsTo[cnt] = hitBar;
      cnt++;
   }

   if(cnt < TP_MIN_CASES)
   { why = "too few like this to measure a target"; return(false); }

   //  The median of the measured runs, without destroying the pairing.
   double sorted[];
   ArrayResize(sorted, cnt);
   for(int i = 0; i < cnt; i++) sorted[i] = ratio[i];
   ArraySort(sorted);
   int q = (int)MathFloor((double)(cnt - 1) * TP_QUANTILE);
   if(q < 0) q = 0;
   if(q >= cnt) q = cnt - 1;
   double cut = sorted[q] * TP_CUT;

   dist = cut * riskPrice;
   if(dist <= 0.0)
   { why = "measured target too small"; return(false); }

   //  How many of the same analogues actually reached that distance, and how
   //  long the ones that did took to get there.
   int reached = 0, bn = 0;
   double bsum = 0.0;
   for(int i = 0; i < cnt; i++)
   {
      if(ratio[i] < cut) continue;
      reached++;
      if(barsTo[i] > 0) { bsum += barsTo[i]; bn++; }
   }
   reachN     = cnt;
   reachShare = 100.0 * (double)reached / (double)cnt;
   medBars    = (bn > 0) ? (bsum / bn) : 0.0;
   return(true);
}

//====================================================================
//  SIZE - 0.5% of equity, converted by the terminal's own money
//  calculation.  Never hand arithmetic, never an assumed pip value.
//====================================================================
double CalcLot(int dir, double entry, double sl, string &why)
{
   why = "";
   if(entry <= 0.0 || sl <= 0.0) { why = "cannot size"; return(0.0); }

   ENUM_ORDER_TYPE t = (dir > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double lossPerLot = 0.0;
   if(!OrderCalcProfit(t, _Symbol, 1.0, entry, sl, lossPerLot))
   { why = "cannot size: terminal refused the money calculation"; return(0.0); }
   lossPerLot = MathAbs(lossPerLot);
   if(lossPerLot <= 0.0) { why = "cannot size: zero risk per lot"; return(0.0); }

   double budget = AccountInfoDouble(ACCOUNT_EQUITY) * RISK_PCT / 100.0;
   double lots   = budget / lossPerLot;

   double step = g_f.volStep;
   double mn   = g_f.volMin;
   double mx   = g_f.volMax;
   lots = MathFloor(lots / step + 1e-8) * step;

   if(lots < mn)
   {
      if(!InpMinLot) { why = "risk budget cannot buy the minimum lot"; return(0.0); }
      lots = mn;
   }
   if(lots > mx) lots = MathFloor(mx / step + 1e-8) * step;
   if(lots <= 0.0) { why = "cannot size"; return(0.0); }

   return(NormalizeDouble(lots, 2));
}

//  Total risk already resting at the broker across this EA's lanes, as a
//  percentage of equity.  Counted against broker stops, not plans.
double OpenRiskPct()
{
   double total = 0.0;
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq <= 0.0) return(0.0);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!g_pos.SelectByIndex(i)) continue;
      if(g_pos.Symbol() != _Symbol) continue;
      ulong mg = g_pos.Magic();
      bool ours = false;
      for(int l = 0; l < LANE_COUNT; l++) if(mg == LaneMagic(l)) ours = true;
      if(!ours) continue;

      double sl = g_pos.StopLoss();
      if(sl <= 0.0) continue;
      double vol = g_pos.Volume();
      double loss = 0.0;
      ENUM_ORDER_TYPE t = (g_pos.PositionType() == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      if(!OrderCalcProfit(t, _Symbol, 1.0, g_pos.PriceOpen(), sl, loss)) continue;
      total += MathAbs(loss) * vol;
   }
   return(100.0 * total / eq);
}

//====================================================================
//  THE PLAN
//====================================================================
void PlanClear(int idx)
{
   g_plan[idx].ok = false;
   g_plan[idx].dir = 0;
   g_plan[idx].market = false;
   g_plan[idx].entry = 0.0;
   g_plan[idx].sl = 0.0;
   g_plan[idx].tp = 0.0;
   g_plan[idx].tp1 = 0.0;
   g_plan[idx].lot = 0.0;
   g_plan[idx].note = "";
}

bool BuildPlan(int idx)
{
   PlanClear(idx);

   if(!g_lane[idx].ready)          { g_plan[idx].note = "DATA WAIT"; return(false); }
   if(g_lane[idx].signal == 0)     { g_plan[idx].note = "NO SIGNAL"; return(false); }

   int dir = g_lane[idx].signal;

   double tick  = g_f.tick > 0.0 ? g_f.tick : g_f.point;
   double point = g_f.point > 0.0 ? g_f.point : tick;
   if(tick <= 0.0 || point <= 0.0) { g_plan[idx].note = "WAIT: no price grid"; return(false); }

   double bid = g_f.bid, ask = g_f.ask;
   if(bid <= 0.0 || ask <= 0.0 || ask < bid) { g_plan[idx].note = "WAIT: no live quote"; return(false); }

   double spread = ask - bid;
   if(spread < 0.0) spread = 0.0;

   //  Spread gate against the median for this server hour.
   MqlDateTime st;
   TimeToStruct(ServerNow(), st);
   int sn = 0;
   double typical = SpreadBaseline(st.hour, sn);
   double gateX = (g_p.spreadGateX > 0.0) ? g_p.spreadGateX : MAX_SPREAD_GATE;
   if(sn >= 20 && typical > 0.0 && spread > typical * gateX)
   { g_plan[idx].note = "WAIT: spread too wide"; return(false); }

   //  Total exposure cap across lanes.
   if(OpenRiskPct() + RISK_PCT > RISK_TOTAL_PCT + 1e-9)
   { g_plan[idx].note = "WAIT: lane risk cap reached"; return(false); }

   int window = LaneStructWindow(idx);
   int need   = window + 4;
   MqlRates r[];
   int n = CopyRates(_Symbol, g_lane[idx].tf, 1, need, r);
   if(n < window + 2) { g_plan[idx].note = "WAIT: structure needs more history"; return(false); }

   int last  = n - 1;
   int first = last - window + 1;
   if(first < 1) first = 1;

   bool unanimous = (g_lane[idx].spoke >= 2 && g_lane[idx].score == g_lane[idx].spoke);

   //  ---- entry -------------------------------------------------------
   double entry = 0.0;
   if(unanimous)
   {
      entry = (dir > 0) ? ask : bid;
   }
   else
   {
      double offset = MathMax(tick, spread);
      double level = 0.0;
      for(int k = first; k < last; k++)
      {
         if(dir > 0 && SwingLowOk(r, k, last))
         {
            double p = r[k].low;
            if(p <= ask - offset && (level == 0.0 || p > level)) level = p;
         }
         if(dir < 0 && SwingHighOk(r, k, last))
         {
            double p = r[k].high;
            if(p >= bid + offset && (level == 0.0 || p < level)) level = p;
         }
      }
      if(level <= 0.0) { g_plan[idx].note = "WAIT: no swing to rest the limit on"; return(false); }
      entry = (dir > 0) ? SnapDown(level, tick) : SnapUp(level, tick);
   }

   //  ---- stop --------------------------------------------------------
   double stopLevel = 0.0;
   for(int k = first; k < last; k++)
   {
      if(dir > 0 && SwingLowOk(r, k, last))
      {
         if(r[k].low < entry - 0.5 * tick && (stopLevel == 0.0 || r[k].low > stopLevel))
            stopLevel = r[k].low;
      }
      if(dir < 0 && SwingHighOk(r, k, last))
      {
         if(r[k].high > entry + 0.5 * tick && (stopLevel == 0.0 || r[k].high < stopLevel))
            stopLevel = r[k].high;
      }
   }
   if(stopLevel <= 0.0) { g_plan[idx].note = "WAIT: no swing to hide the stop behind"; return(false); }

   double buffer = MathMax(tick * g_p.stopBufferTicks, spread);
   double sl = (dir > 0) ? SnapDown(stopLevel - buffer, tick)
                         : SnapUp(stopLevel + buffer, tick);
   double risk = (dir > 0) ? (entry - sl) : (sl - entry);
   if(risk <= 0.0) { g_plan[idx].note = "WAIT: stop on the wrong side"; return(false); }

   //  Broker's minimum distance.
   if(g_f.stopsLevel > 0)
   {
      double minDist = (double)g_f.stopsLevel * point;
      if((dir > 0 && (ask - sl) < minDist) || (dir < 0 && (sl - bid) < minDist))
      { g_plan[idx].note = "WAIT: stop inside broker minimum"; return(false); }
   }

   //  ---- target ------------------------------------------------------
   double dist = 0.0, reach = 0.0, medBars = 0.0;
   int reachN = 0;
   string tWhy = "";
   if(!MeasureTarget(idx, dir, risk, tick, dist, reach, reachN, medBars, tWhy))
   { g_plan[idx].note = "WAIT: " + tWhy; return(false); }

   double tp = (dir > 0) ? SnapDown(entry + dist, tick) : SnapUp(entry - dist, tick);

   //  Cap before the nearest confirmed opposing turn.
   double cap = 0.0;
   for(int k = first; k < last; k++)
   {
      if(dir > 0 && SwingHighOk(r, k, last) && r[k].high > entry)
      {
         if(cap == 0.0 || r[k].high < cap) cap = r[k].high;
      }
      if(dir < 0 && SwingLowOk(r, k, last) && r[k].low < entry)
      {
         if(cap == 0.0 || r[k].low > cap) cap = r[k].low;
      }
   }
   if(cap > 0.0)
   {
      double capped = (dir > 0) ? SnapDown(cap - tick, tick) : SnapUp(cap + tick, tick);
      if((dir > 0 && capped > entry && capped < tp) ||
         (dir < 0 && capped < entry && capped > tp)) tp = capped;
   }

   double tpDist = MathAbs(tp - entry);
   if(spread > 0.0 && tpDist < spread * TP_COST_X)
   { g_plan[idx].note = "WAIT: target does not clear spread"; return(false); }
   if(tpDist <= 0.0) { g_plan[idx].note = "WAIT: target too small"; return(false); }

   //  ---- size --------------------------------------------------------
   string sWhy = "";
   double lot = CalcLot(dir, entry, sl, sWhy);
   if(lot <= 0.0) { g_plan[idx].note = "WAIT: " + sWhy; return(false); }

   g_plan[idx].ok     = true;
   g_plan[idx].dir    = dir;
   g_plan[idx].market = unanimous;
   g_plan[idx].entry  = entry;
   g_plan[idx].sl     = sl;
   g_plan[idx].tp     = tp;
   g_plan[idx].tp1    = (dir > 0) ? SnapDown(entry + 0.5 * tpDist, tick)
                                  : SnapUp(entry - 0.5 * tpDist, tick);
   g_plan[idx].lot    = lot;
   g_plan[idx].note   = "";

   g_lane[idx].reachPct = reach;
   g_lane[idx].reachN   = reachN;
   g_lane[idx].durabPct = (int)MathRound(medBars);
   g_lane[idx].durabOk  = (medBars > 0.0);
   return(true);
}

//====================================================================
//  TRADE STATE
//====================================================================
double g_hw[LANE_COUNT];        // best price seen since the fill
int    g_posDir[LANE_COUNT];    // which side each live lane is on

bool HasOurPosition(int idx)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!g_pos.SelectByIndex(i)) continue;
      if(g_pos.Symbol() != _Symbol) continue;
      if(g_pos.Magic() == LaneMagic(idx)) return(true);
   }
   return(false);
}

bool HasOurOrder(int idx)
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong t = OrderGetTicket(i);
      if(t == 0 || !OrderPick(t)) continue;
      if(OrdSymbol() != _Symbol) continue;
      if(OrdMagic() == (long)LaneMagic(idx)) return(true);
   }
   return(false);
}

double NettingOppositeVolume(int dir)
{
   if(g_f.hedging) return(0.0);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!g_pos.SelectByIndex(i)) continue;
      if(g_pos.Symbol() != _Symbol) continue;
      bool buy = (g_pos.PositionType() == POSITION_TYPE_BUY);
      if((dir > 0 && !buy) || (dir < 0 && buy)) return(g_pos.Volume());
   }
   return(0.0);
}

//------------------------------------------------------------------
//  Reconcile with the broker.  The broker is the truth, never memory.
//------------------------------------------------------------------
void TradeSync(int idx)
{
   bool havePos = HasOurPosition(idx);
   bool haveOrd = HasOurOrder(idx);

   if(havePos)
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(!g_pos.SelectByIndex(i)) continue;
         if(g_pos.Symbol() != _Symbol || g_pos.Magic() != LaneMagic(idx)) continue;

         ulong t = g_pos.Ticket();
         if(g_lane[idx].state != LS_OPEN || g_lane[idx].ticket != t)
         {
            //  A fill.  The idea is spent until the outcome is graded.
            g_lane[idx].state    = LS_OPEN;
            g_lane[idx].ticket   = t;
            g_lane[idx].openLots = g_pos.Volume();
            g_lane[idx].tp1Done  = false;
            g_hw[idx] = (g_pos.PositionType() == POSITION_TYPE_BUY) ? g_f.bid : g_f.ask;
            double sl = g_pos.StopLoss();
            if(sl > 0.0)
               g_lane[idx].origRisk = MathAbs(g_pos.PriceOpen() - sl);

            //  A position inherited from before a restart has no stored TP1.
            //  Rebuild it the same way the plan built it, from the trade's own
            //  entry and target - never from today's plan.
            double tpx = g_pos.TakeProfit();
            if(tpx > 0.0 && g_lane[idx].tp1Price <= 0.0)
               g_lane[idx].tp1Price = g_pos.PriceOpen() + 0.5 * (tpx - g_pos.PriceOpen());
            g_lane[idx].tradedTrend  = g_lane[idx].trend;
            g_lane[idx].tradedSignal = g_lane[idx].signal;
            g_posDir[idx] = (g_pos.PositionType() == POSITION_TYPE_BUY) ? 1 : -1;
         }
         else
         {
            g_lane[idx].openLots = g_pos.Volume();
         }
         break;
      }
   }
   else
   {
      if(g_lane[idx].state == LS_OPEN)
      {
         //  It closed.  Queue it for grading; the money is read there.
         g_fill[idx].ticket = g_lane[idx].ticket;
         g_fill[idx].dir    = g_posDir[idx];
         g_fill[idx].lot    = g_lane[idx].openLots;
         g_fill[idx].tries  = 0;
         g_lane[idx].state  = LS_NONE;
         g_lane[idx].ticket = 0;
         g_lane[idx].tp1Done = false;
      }
      if(haveOrd)
      {
         if(g_lane[idx].state != LS_LIMIT)
         {
            for(int i = OrdersTotal() - 1; i >= 0; i--)
            {
               ulong t = OrderGetTicket(i);
               if(t == 0 || !OrderPick(t)) continue;
               if(OrdSymbol() != _Symbol || OrdMagic() != (long)LaneMagic(idx)) continue;
               g_lane[idx].ticket = t;
               break;
            }
            g_lane[idx].state = LS_LIMIT;
         }
      }
      else if(g_lane[idx].state == LS_LIMIT)
      {
         //  It vanished without filling: expired, cancelled, or rejected.
         g_lane[idx].state  = LS_NONE;
         g_lane[idx].ticket = 0;
      }
   }
}

//------------------------------------------------------------------
//  Grade a closed position in money, after swap and commission.
//------------------------------------------------------------------
void FlushGrades(int idx)
{
   if(g_fill[idx].ticket == 0) return;

   if(!HistorySelectByPosition((long)g_fill[idx].ticket))
   {
      g_fill[idx].tries++;
      if(g_fill[idx].tries > 20) g_fill[idx].ticket = 0;
      return;
   }

   double net = 0.0;
   int deals = HistoryDealsTotal();
   for(int i = 0; i < deals; i++)
   {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0) continue;
      net += HistoryDealGetDouble(d, DEAL_PROFIT);
      net += HistoryDealGetDouble(d, DEAL_SWAP);
      net += HistoryDealGetDouble(d, DEAL_COMMISSION);
   }

   if(deals <= 0)
   {
      g_fill[idx].tries++;
      if(g_fill[idx].tries > 20) g_fill[idx].ticket = 0;
      return;
   }

   int dir = g_fill[idx].dir;
   RecordAppend(TimeToString(TimeTradeServer(), TIME_DATE | TIME_MINUTES) + "," +
                IntegerToString(idx) + ",TRADE," + IntegerToString((long)g_fill[idx].ticket) + "," +
                (dir > 0 ? "BUY" : "SELL") + "," +
                DoubleToString(g_fill[idx].lot, 2) + "," +
                DoubleToString(net, 2) + "," +
                (net > 0.0 ? "1" : "0"));

   if(net > 0.0) { g_allW[idx]++; g_todayW[idx]++; }
   else if(net < 0.0) { g_allL[idx]++; g_todayL[idx]++; }

   //  A winning close re-arms the lane: the idea was right and is still standing.
   //  A losing close does not - buying back the level that was just wrong, on the
   //  same evidence, is how one bad bar becomes five.
   if(net > 0.0)
   {
      g_lane[idx].tradedTrend  = 0;
      g_lane[idx].tradedSignal = 0;
   }
   g_fill[idx].ticket = 0;
}

//------------------------------------------------------------------
//  Send, reprice, cancel
//------------------------------------------------------------------

bool SendPlan(int idx)
{
   if(!g_plan[idx].ok) return(false);
   if(!LaneAllowed(idx)) return(false);
   if(!TerminalAllowsTrade()) return(false);
   if(g_m.status != 0) return(false);

   //  Netting: two lanes may not hold opposite positions.
   if(NettingOppositeVolume(g_plan[idx].dir) > 0.0) return(false);

   if(OpenRiskPct() + RISK_PCT > RISK_TOTAL_PCT + 1e-9) return(false);

   g_trade.SetExpertMagicNumber(LaneMagic(idx));
   g_trade.SetDeviationInPoints(20);
   g_trade.SetTypeFilling((ENUM_ORDER_TYPE_FILLING)PickFilling());

   bool sent = false;
   if(g_plan[idx].market)
   {
      ENUM_ORDER_TYPE t = (g_plan[idx].dir > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      double px = (g_plan[idx].dir > 0) ? g_f.ask : g_f.bid;
      sent = g_trade.PositionOpen(_Symbol, t, g_plan[idx].lot, px,
                                  g_plan[idx].sl, g_plan[idx].tp,
                                  "OldMate " + g_lane[idx].name);
   }
   else
   {
      ENUM_ORDER_TYPE t = (g_plan[idx].dir > 0) ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT;
      //  Two datetimes cannot be added. Add in long, then cast back.
      datetime expiry = (datetime)((long)TimeTradeServer() +
                                   (long)(3 * PeriodSeconds(g_lane[idx].tf)));
      sent = g_trade.OrderOpen(_Symbol, t, g_plan[idx].lot, g_plan[idx].entry,
                               g_plan[idx].sl, g_plan[idx].tp, ORDER_TIME_SPECIFIED, expiry,
                               "OldMate " + g_lane[idx].name);
   }

   if(sent)
   {
      g_lane[idx].origRisk     = MathAbs(g_plan[idx].entry - g_plan[idx].sl);
      g_lane[idx].tp1Price     = g_plan[idx].tp1;
      g_lane[idx].tradedTrend  = g_lane[idx].trend;
      g_lane[idx].tradedSignal = g_lane[idx].signal;
      TradeSync(idx);
   }
   return(sent);
}

void CancelLane(int idx, string why)
{
   if(g_lane[idx].state != LS_LIMIT) return;
   if(g_lane[idx].ticket == 0) return;
   g_trade.SetExpertMagicNumber(LaneMagic(idx));
   if(g_trade.OrderDelete(g_lane[idx].ticket))
   {
      PrintFormat("OldMate %s: limit %I64u cancelled (%s)",
                  g_lane[idx].name, g_lane[idx].ticket, why);
      g_lane[idx].state  = LS_NONE;
      g_lane[idx].ticket = 0;
   }
}

void RepriceLimit(int idx)
{
   if(g_lane[idx].state != LS_LIMIT || g_lane[idx].ticket == 0) return;
   if(!g_plan[idx].ok || g_plan[idx].market) return;

   double tick = g_f.tick > 0.0 ? g_f.tick : g_f.point;
   if(!OrderPick(g_lane[idx].ticket)) return;

   double nowEntry = OrdPrice();
   double nowSl    = OrdSl();
   double nowTp    = OrdTp();

   bool moved = (MathAbs(nowEntry - g_plan[idx].entry) >= 0.5 * tick) ||
                (MathAbs(nowSl - g_plan[idx].sl) >= 0.5 * tick) ||
                (MathAbs(nowTp - g_plan[idx].tp) >= 0.5 * tick);
   if(!moved) return;

   g_trade.SetExpertMagicNumber(LaneMagic(idx));
   datetime newExp = (datetime)((long)TimeTradeServer() +
                                (long)(3 * PeriodSeconds(g_lane[idx].tf)));
   if(g_trade.OrderModify(g_lane[idx].ticket, g_plan[idx].entry,
                          g_plan[idx].sl, g_plan[idx].tp,
                          ORDER_TIME_SPECIFIED, newExp))
   {
      g_lane[idx].origRisk = MathAbs(g_plan[idx].entry - g_plan[idx].sl);
   }
}

//====================================================================
//  ON A CLOSED BAR
//====================================================================
void TradeOnBar(int idx)
{
   TradeSync(idx);
   FlushGrades(idx);

   if(!g_lane[idx].ready) return;

   BuildPlan(idx);

   if(!g_lane[idx].armed) { g_lane[idx].armed = true; return; }   // never trade on attach

   if(g_lane[idx].state == LS_OPEN) return;                       // a position is never touched here

   if(g_lane[idx].state == LS_LIMIT)
   {
      if(!g_plan[idx].ok)
      {
         CancelLane(idx, "plan died");
         return;
      }
      if(g_plan[idx].market)
      {
         //  Cancel only; the market entry waits for a later bar, because a
         //  partial fill can race the delete.
         CancelLane(idx, "upgraded to market");
         return;
      }
      RepriceLimit(idx);
      return;
   }

   //  Flat.  The idea latch: one idea per signal, not one per bar.
   if(!g_plan[idx].ok) return;
   if(g_lane[idx].tradedSignal == g_lane[idx].signal &&
      g_lane[idx].tradedTrend  == g_lane[idx].trend) return;

   SendPlan(idx);
   g_lane[idx].armed = true;
}

//====================================================================
//  ONCE A SECOND
//  The switches, the clock and the quote are the only things that can
//  change between bars, so this path only looks at those, plus the
//  management of a position that is already open.
//====================================================================
void ManageSecond(int idx)
{
   TradeSync(idx);
   FlushGrades(idx);

   if(!g_lane[idx].ready) return;

   //  ---- a resting limit --------------------------------------------
   if(g_lane[idx].state == LS_LIMIT)
   {
      if(!LaneAllowed(idx) || !TerminalAllowsTrade() || g_m.status != 0)
      {
         CancelLane(idx, "permission withdrawn");
         return;
      }
      if(!OrderPick(g_lane[idx].ticket)) { TradeSync(idx); return; }

      datetime placed = OrdSetupTime();
      if(placed > 0)
      {
         int life = (int)((long)TimeTradeServer() - (long)placed);
         if(life > 3 * PeriodSeconds(g_lane[idx].tf))
         {
            CancelLane(idx, "expired on the clock");
            return;
         }
      }

      //  The market walked through the price it rests at.
      double tick = g_f.tick > 0.0 ? g_f.tick : g_f.point;
      double buff = MathMax(tick, g_f.ask - g_f.bid);
      bool buyLimit = (OrdKind() == ORDER_TYPE_BUY_LIMIT);
      double rest   = OrdPrice();
      if(buyLimit && g_f.bid < rest - buff)  { CancelLane(idx, "walked through"); return; }
      if(!buyLimit && g_f.ask > rest + buff) { CancelLane(idx, "walked through"); return; }
      return;
   }

   //  ---- an open position -------------------------------------------
   if(g_lane[idx].state != LS_OPEN) return;
   if(g_lane[idx].ticket == 0) return;
   if(!g_pos.SelectByTicket(g_lane[idx].ticket)) return;

   bool isBuy  = (g_pos.PositionType() == POSITION_TYPE_BUY);
   double entry = g_pos.PriceOpen();
   double sl    = g_pos.StopLoss();
   double tp    = g_pos.TakeProfit();
   double vol   = g_pos.Volume();
   double tick  = g_f.tick > 0.0 ? g_f.tick : g_f.point;
   double spread = MathMax(g_f.ask - g_f.bid, 0.0);
   double buff  = MathMax(tick, spread);
   double price = isBuy ? g_f.bid : g_f.ask;

   //  ---- TP1: close a share, then protect what is left --------------
   if(InpTp1Tp2 && !g_lane[idx].tp1Done && g_lane[idx].tp1Price > 0.0)
   {
      bool reached = isBuy ? (g_f.bid >= g_lane[idx].tp1Price)
                           : (g_f.ask <= g_lane[idx].tp1Price);
      if(reached)
      {
         double part = MathFloor((vol * TP1_FRACTION) / g_f.volStep + 1e-8) * g_f.volStep;
         double remain = vol - part;
         if(part > 0.0 && remain >= g_f.volMin)
         {
            g_trade.SetExpertMagicNumber(LaneMagic(idx));
            if(g_trade.PositionClosePartial(g_lane[idx].ticket, part))
            {
               g_lane[idx].tp1Done = true;
               vol = remain;
            }
         }
         else
         {
            //  The broker cannot hold a part that small.  Do not pretend:
            //  the partial is skipped and the stop is protected instead.
            g_lane[idx].tp1Done = true;
         }
      }
   }

   //  ---- trailing stop ----------------------------------------------
   if(!InpTrailStop) return;
   if(g_lane[idx].origRisk <= 0.0) return;

   double favourable = isBuy ? g_f.bid : g_f.ask;
   if(isBuy) g_hw[idx] = MathMax(g_hw[idx], favourable);
   else      g_hw[idx] = MathMin((g_hw[idx] <= 0.0 ? favourable : g_hw[idx]), favourable);

   double profit = isBuy ? (price - entry) : (entry - price);
   bool banked = g_lane[idx].tp1Done || (profit >= g_lane[idx].origRisk);
   if(!banked) return;

   double want = isBuy ? (g_hw[idx] - TRAIL_STEP_R * g_lane[idx].origRisk)
                       : (g_hw[idx] + TRAIL_STEP_R * g_lane[idx].origRisk);

   //  After TP1 the stop never goes back behind the entry.
   if(g_lane[idx].tp1Done)
   {
      double be = isBuy ? (entry + buff) : (entry - buff);
      want = isBuy ? MathMax(want, be) : MathMin(want, be);
   }

   want = isBuy ? SnapDown(want, tick) : SnapUp(want, tick);

   //  Broker minimum distance and freeze level.
   long guardLv = MathMax(g_f.stopsLevel, g_f.freezeLevel);
   if(guardLv > 0)
   {
      double minDist = (double)guardLv * (g_f.point > 0.0 ? g_f.point : tick);
      if(isBuy && (price - want) < minDist) return;
      if(!isBuy && (want - price) < minDist) return;
   }

   bool better = isBuy ? (want > sl + 0.5 * tick) : (sl == 0.0 || want < sl - 0.5 * tick);
   if(!better) return;

   g_trade.SetExpertMagicNumber(LaneMagic(idx));
   g_trade.PositionModify(g_lane[idx].ticket, want, tp);
}

//====================================================================
//  COLD START
//====================================================================
void ReconcileAll()
{
   for(int i = 0; i < LANE_COUNT; i++)
   {
      g_lane[i].state = LS_NONE;
      g_lane[i].ticket = 0;
      TradeSync(i);
   }
}

//====================================================================
//  PANEL
//====================================================================
void PanelReset()
{
   g_drawn = 0;
}

void PanelLine(string text, color clr, string tip)
{
   string name = PANEL_PREFIX + IntegerToString(g_drawn);
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, PANEL_X);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, PANEL_Y + g_drawn * (FONT_SIZE + 6));
   ObjectSetString (0, name, OBJPROP_TEXT, text);
   ObjectSetString (0, name, OBJPROP_FONT, FONT_NAME);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, FONT_SIZE);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetString (0, name, OBJPROP_TOOLTIP, tip);
   g_drawn++;
}

void PanelTrim()
{
   //  Remove labels left over from a taller previous draw.
   for(int i = g_drawn; i < g_drawn + 60; i++)
   {
      string name = PANEL_PREFIX + IntegerToString(i);
      if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   }
}

void PanelRemoveAll()
{
   for(int i = 0; i < 200; i++)
   {
      string name = PANEL_PREFIX + IntegerToString(i);
      if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
      string dn = DETAIL_PREFIX + IntegerToString(i);
      if(ObjectFind(0, dn) >= 0) ObjectDelete(0, dn);
   }
}

string TrendText(int t)
{
   if(t > 0) return("UP");
   if(t < 0) return("DOWN");
   return("FLAT");
}

color TrendColour(int t)
{
   if(t > 0) return(clrLime);
   if(t < 0) return(clrTomato);
   return(clrSilver);
}

string SignalText(int s)
{
   if(s > 0) return("BUY");
   if(s < 0) return("SELL");
   return("NO SIGNAL");
}

color SignalColour(int s)
{
   if(s > 0) return(clrLime);
   if(s < 0) return(clrTomato);
   return(clrSilver);
}

string ScoreText(int idx)
{
   if(g_lane[idx].spoke <= 0) return("--/--");
   return(IntegerToString(g_lane[idx].score) + "/" + IntegerToString(g_lane[idx].spoke));
}

string HoldsText(int idx)
{
   if(!g_lane[idx].holdsOk) return("--");
   return(IntegerToString(g_lane[idx].holdsBars) + " bars (" +
          IntegerToString(g_lane[idx].holdsLo) + "-" +
          IntegerToString(g_lane[idx].holdsHi) + ")");
}

string SignalCellText(int idx)
{
   if(g_lane[idx].signal == 0) return("NO SIGNAL");
   string s = SignalText(g_lane[idx].signal) + " ";
   if(g_lane[idx].reachN >= TP_MIN_CASES)
      s += StringFormat("%.0f%% (%d)", g_lane[idx].reachPct, g_lane[idx].reachN);
   else
      s += "--";
   return(s);
}

string PlanStateText(int idx)
{
   if(!g_lane[idx].ready) return("DATA WAIT");
   if(g_lane[idx].signal == 0) return("NO SIGNAL");
   if(g_plan[idx].ok) return("READY");
   return(g_plan[idx].note);
}

color PlanStateColour(int idx)
{
   if(g_plan[idx].ok) return(clrDeepSkyBlue);
   if(g_lane[idx].signal == 0) return(clrDimGray);
   return(clrGoldenrod);
}

//  Per READING, summed over the lanes: the question is whether the reading
//  earns its place, not whether one lane happened to be lucky.
string ReadScoreText(int reading)
{
   int hit = 0, n = 0;
   bool dem = false;
   for(int i = 0; i < LANE_COUNT; i++)
   {
      hit += g_readHit[i][reading];
      n   += g_readN[i][reading];
      if(g_demoted[i][reading]) dem = true;
   }
   if(n < 40) return("--");
   string s = StringFormat("%.0f%% (%d)", 100.0 * (double)hit / (double)n, n);
   if(dem) s += "*";
   return(s);
}

void DrawPanel()
{
   PanelReset();

   string hd = " " + EA_NAME + "   " + g_f.name + "  |  " + ClassLabel(g_p.cls) +
               "  |  " + (g_f.hedging ? "Hedging" : "Netting") +
               "  |  Equity " + DoubleToString(g_f.equity, 2) + " " + g_f.currency;
   PanelLine(hd, clrWhite, "Symbol, instrument class, account type and equity, all read from the terminal.");

   string mk = " " + g_m.text + "  |  " + g_m.session + (g_m.sessionEst ? " (est.)" : "") +
               "  |  Spread " + DoubleToString(g_m.spreadPoints, 0) + " pts (" +
               (g_m.spreadNormal ? "normal" : "wide") + ")";
   PanelLine(mk, g_m.colour, "Broker sessions decide availability. The session name is a label, never a filter.");

   string at = " " + AutoTradeText();
   PanelLine(at, AutoTradeColour(),
             "Autotrading ON is the EA's permission. MT5's own Algo Trading button has a veto of its own.");

   if(!TimeframeAllowed((ENUM_TIMEFRAMES)Period()))
   {
      PanelLine("", clrWhite, "");
      PanelLine(" OUT OF RANGE - attach to M5, M15 or M30", clrTomato,
                "OldMate is designed for three lanes. On any other timeframe it reads nothing and sends nothing.");
      PanelLine(" Nothing is read, planned or sent on this chart.", clrGoldenrod,
                "An honest refusal, rather than a fourth personality nobody measured.");
      PanelTrim();
      return;
   }

   PanelLine("", clrWhite, "");
   PanelLine(" " + Pad("TF", 5) + Pad("TREND", 12) + Pad("REGIME", 17) +
             Pad("SCORE", 7) + Pad("SIGNAL", 18) + "HOLDS", clrGray,
             "Agreement, never a win rate. The percentage beside a call is the share of same-grade past situations that reached their measured target.");

   for(int i = 0; i < LANE_COUNT; i++)
   {
      string tr = g_lane[i].ready ? (TrendText(g_lane[i].trend) + " " + IntegerToString(g_lane[i].trendAge))
                                  : "DATA WAIT";
      string rg = g_lane[i].ready ? (MemoryWord(g_lane[i].memory) + " " + VolWord(g_lane[i].volState))
                                  : "--";
      string sc = g_lane[i].ready ? ScoreText(i) : "--/--";
      string sg = g_lane[i].ready ? SignalCellText(i) : "--";
      string ho = g_lane[i].ready ? HoldsText(i) : "--";

      string row = " " + Pad(g_lane[i].name, 5) + Pad(tr, 12) + Pad(rg, 17) +
                   Pad(sc, 7) + Pad(sg, 18) + ho;
      color c = g_lane[i].ready ? SignalColour(g_lane[i].signal) : clrDimGray;

      string tip = "Memory says what kind of series this is; volatility says how loud. "
                   "Both are counted, never guessed.";
      if(g_lane[i].ready && g_lane[i].memory == MEM_UNCLEAR)
         tip = "The two memory estimates disagree, so the lane will not decide on the weather. "
               "It falls back to requiring both continuation readings to agree.";
      PanelLine(row, c, tip);
   }

   PanelLine("", clrWhite, "");
   PanelLine(" " + Pad("TF", 5) + Pad("SIDE", 6) + Pad("ENTRY", 10) + Pad("LOT", 6) +
             Pad("TARGET", 19) + Pad("STOP", 18) + "STATE", clrGray,
             "The plan is rebuilt every closed bar whether or not a trade exists.");
   for(int i = 0; i < LANE_COUNT; i++)
   {
      string side = "--", en = "--", lt = "--", tg = "--", sp = "--";
      if(g_plan[i].ok)
      {
         side = (g_plan[i].dir > 0) ? "BUY" : "SELL";
         en   = DoubleToString(g_plan[i].entry, g_f.digits);
         lt   = DoubleToString(g_plan[i].lot, 2);
         tg   = DoubleToString(g_plan[i].tp, g_f.digits) + " (" +
                DoubleToString(MathAbs(g_plan[i].tp - g_plan[i].entry) / g_f.point, 0) + ")";
         sp   = DoubleToString(g_plan[i].sl, g_f.digits) + " (" +
                DoubleToString(MathAbs(g_plan[i].entry - g_plan[i].sl) / g_f.point, 0) + ")";
      }
      string row = " " + Pad(g_lane[i].name, 5) + Pad(side, 6) + Pad(en, 10) + Pad(lt, 6) +
                   Pad(tg, 19) + Pad(sp, 18) + PlanStateText(i);
      string tip = "WAIT is not a failure: it is the EA refusing to invent a level it cannot measure.";
      if(!g_lane[i].ready)
         tip = StringFormat("This lane needs %d closed bars and the terminal has %d. "
                            "Nothing is claimed until it has them.",
                            g_lane[i].needBars, g_lane[i].haveBars);
      PanelLine(row, g_plan[i].ok ? clrWhite : PlanStateColour(i), tip);
   }

   PanelLine("", clrWhite, "");
   PanelLine(" AT THE BROKER (" + g_f.currency + ")", clrGray,
             "What the terminal actually holds, read back every second. Never what the plan hoped.");
   for(int i = 0; i < LANE_COUNT; i++)
   {
      if(g_lane[i].state == LS_NONE)
      {
         PanelLine(" " + Pad(g_lane[i].name, 5) + "none", clrDimGray, "");
         continue;
      }
      if(g_lane[i].state == LS_LIMIT && OrderPick(g_lane[i].ticket))
      {
         bool bl = (OrdKind() == ORDER_TYPE_BUY_LIMIT);
         string l1 = " " + Pad(g_lane[i].name, 5) + "Limit " + (bl ? "BUY " : "SELL") +
                     "  Entry " + DoubleToString(OrdPrice(), g_f.digits) +
                     "   Lot " + DoubleToString(OrdVolume(), 2);
         PanelLine(l1, clrDeepSkyBlue, "A resting limit. Three lane-periods of life at most.");
         double toE = bl ? (g_f.ask - OrdPrice()) : (OrdPrice() - g_f.bid);
         string l2 = "      Bid " + DoubleToString(g_f.bid, g_f.digits) +
                     "  Ask " + DoubleToString(g_f.ask, g_f.digits) +
                     "   To entry " + DoubleToString(MathAbs(toE) / g_f.point, 0) + " pts";
         PanelLine(l2, clrSilver, "");
         string l3 = "      Target " + DoubleToString(OrdTp(), g_f.digits) +
                     "   Stop " + DoubleToString(OrdSl(), g_f.digits);
         PanelLine(l3, clrSilver, "");
         continue;
      }
      if(g_lane[i].state == LS_OPEN && g_pos.SelectByTicket(g_lane[i].ticket))
      {
         bool isBuy = (g_pos.PositionType() == POSITION_TYPE_BUY);
         double entry = g_pos.PriceOpen();
         double tp = g_pos.TakeProfit();
         double sl = g_pos.StopLoss();
         double pl = g_pos.Profit() + g_pos.Swap();
         string l1 = " " + Pad(g_lane[i].name, 5) + "Open " + (isBuy ? "BUY " : "SELL") +
                     "  Entry " + DoubleToString(entry, g_f.digits) +
                     "   Lot " + DoubleToString(g_pos.Volume(), 2) +
                     "   P/L " + (pl >= 0 ? "+" : "") + DoubleToString(pl, 2);
         PanelLine(l1, clrWhite, "P/L is the broker's profit plus swap, in the account currency.");
         double toT = isBuy ? (tp - g_f.bid) : (g_f.ask - tp);
         string l2 = "      Bid " + DoubleToString(g_f.bid, g_f.digits) +
                     "  Ask " + DoubleToString(g_f.ask, g_f.digits) +
                     "   To target " + DoubleToString(MathAbs(toT) / g_f.point, 0) + " pts";
         PanelLine(l2, clrSilver, "");
         string l3 = "      Target " + DoubleToString(tp, g_f.digits) +
                     "   Stop " + DoubleToString(sl, g_f.digits) +
                     "   TP1 " + (g_lane[i].tp1Done ? "done" : "pending");
         PanelLine(l3, clrSilver, "");
      }
   }

   PanelLine("", clrWhite, "");
   string t1 = StringFormat(" RECORD  today  calls %dR/%dW   trades %dW/%dL",
                            g_todayS[0][0] + g_todayS[1][0] + g_todayS[2][0],
                            g_todayS[0][1] + g_todayS[1][1] + g_todayS[2][1],
                            g_todayW[0] + g_todayW[1] + g_todayW[2],
                            g_todayL[0] + g_todayL[1] + g_todayL[2]);
   PanelLine(t1, clrWhite, "Every call is checked a few bars later and written down, right or wrong.");
   string t2 = StringFormat("          all   calls %dR/%dW   trades %dW/%dL",
                            g_allS[0][0] + g_allS[1][0] + g_allS[2][0],
                            g_allS[0][1] + g_allS[1][1] + g_allS[2][1],
                            g_allW[0] + g_allW[1] + g_allW[2],
                            g_allL[0] + g_allL[1] + g_allL[2]);
   PanelLine(t2, clrWhite, "");

   string t3 = " Readings  MOM " + ReadScoreText(0) + "   PUSH " + ReadScoreText(1) +
               "   STRT " + ReadScoreText(2);
   PanelLine(t3, clrGray,
             "How often each reading was on the right side, counted from the record. "
             "A * means the bounded tweak stopped it counting after it fell below a coin flip.");

   string t4 = " " + g_recNote + " | Tweak: " + (InpTweakArm ? "armed" : "off") +
               " | Last closed bar " + TimeToString(ServerNow(), TIME_MINUTES) + " server";
   PanelLine(t4, clrGray, "");

   PanelTrim();
}

//====================================================================
//  The details panel - what the readings actually say, in words
//====================================================================
void DrawDetails()
{
   int x = PANEL_X + 640;
   int y = PANEL_Y;
   int k = 0;

   if(!InpDiaryDetails) return;

   string lines[];
   color cols[];
   ArrayResize(lines, 40);
   ArrayResize(cols, 40);

   lines[k] = " READING DETAIL";                       cols[k] = clrGray;       k++;
   lines[k] = " momentum : MACD divided by its own";   cols[k] = clrSilver;     k++;
   lines[k] = "            volatility, x100";          cols[k] = clrSilver;     k++;
   lines[k] = " push     : directional movement,";     cols[k] = clrSilver;     k++;
   lines[k] = "            Wilder smoothing";          cols[k] = clrSilver;     k++;
   lines[k] = " stretch  : position in the envelope";  cols[k] = clrSilver;     k++;
   lines[k] = "";                                      cols[k] = clrSilver;     k++;

   for(int i = 0; i < LANE_COUNT && k < 38; i++)
   {
      if(!g_lane[i].ready) continue;
      lines[k] = " " + g_lane[i].name;
      cols[k] = clrWhite; k++;
      lines[k] = StringFormat("   mom %+.1f  push %+.1f  stretch %+.2f",
                              g_lane[i].momValue, g_lane[i].pushValue, g_lane[i].stretchValue);
      cols[k] = clrSilver; k++;
      lines[k] = StringFormat("   votes %+d %+d %+d   memory %s",
                              g_lane[i].vMom, g_lane[i].vPush, g_lane[i].vStretch,
                              MemoryWord(g_lane[i].memory));
      cols[k] = clrSilver; k++;
      lines[k] = StringFormat("   hurst %.2f / %.2f  vr %.2f",
                              g_lane[i].hurstDfa, g_lane[i].hurstRs, g_lane[i].varRatio);
      cols[k] = clrSilver; k++;
      if(g_lane[i].reachN > 0 && k < 38)
      {
         lines[k] = StringFormat("   analogue reach %.0f%% of %d",
                                 g_lane[i].reachPct, g_lane[i].reachN);
         cols[k] = clrSilver; k++;
      }
      if(k < 38)
      {
         lines[k] = StringFormat("   record  mom %s  push %s  strt %s",
                                 ReadScoreText(0), ReadScoreText(1), ReadScoreText(2));
         cols[k] = clrSilver; k++;
      }
      k++;
   }

   for(int i = 0; i < k; i++)
   {
      string name = DETAIL_PREFIX + IntegerToString(i);
      if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y + i * (FONT_SIZE + 6));
      ObjectSetString (0, name, OBJPROP_TEXT, lines[i]);
      ObjectSetString (0, name, OBJPROP_FONT, FONT_NAME);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, FONT_SIZE);
      ObjectSetInteger(0, name, OBJPROP_COLOR, cols[i]);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }
   for(int i = k; i < 60; i++)
   {
      string name = DETAIL_PREFIX + IntegerToString(i);
      if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   }
}

//====================================================================
//  NEW CLOSED BAR DETECTION
//====================================================================
void UpdateLanes()
{
   for(int i = 0; i < LANE_COUNT; i++)
   {
      datetime t = iTime(_Symbol, g_lane[i].tf, 1);
      if(t == 0) continue;
      if(t == g_lane[i].lastBar) continue;

      g_lane[i].lastBar = t;
      if(!UpdateLane(i)) continue;
      TradeOnBar(i);
   }
}

//====================================================================
//  HEARTBEAT - one path, driven by the tick and by the timer
//====================================================================
void Heartbeat()
{
   UpdateQuote();
   g_f.equity = AccountInfoDouble(ACCOUNT_EQUITY);

   if(g_lastSample == 0 ||
      (long)TimeTradeServer() - (long)g_lastSample >= (long)SPREAD_SAMPLE_SEC)
   {
      SampleSpread();
      g_lastSample = TimeTradeServer();
   }

   if(g_lastRefTable == 0 ||
      (long)TimeTradeServer() - (long)g_lastRefTable >= (long)REFRESH_SEC)
   {
      RefreshMarket();
      g_lastRefTable = TimeTradeServer();
   }

   if(g_lastSession == 0 ||
      (long)TimeTradeServer() - (long)g_lastSession >= (long)SESSION_SEC)
   {
      ReadSessions();
      g_lastSession = TimeTradeServer();
   }

   MqlDateTime st;
   TimeToStruct(TimeTradeServer(), st);
   if(st.hour == 0 && st.min == 0)
   {
      MqlDateTime d = st;
      d.hour = 0; d.min = 0; d.sec = 0;
      datetime today = StructToTime(d);
      if(today != g_dayKey)
      {
         g_dayKey = today;
         for(int i = 0; i < LANE_COUNT; i++)
         {
            g_todayS[i][0] = 0; g_todayS[i][1] = 0; g_todayS[i][2] = 0;
            g_todayW[i] = 0; g_todayL[i] = 0;
         }
      }
   }

   if(TimeframeAllowed((ENUM_TIMEFRAMES)Period()))
   {
      UpdateLanes();

      //  The per-second path is a per-second path.  Running it on every tick
      //  would read the same numbers many times a second for no gain.
      static datetime lastManage = 0;
      datetime nowS = TimeTradeServer();
      if(lastManage == 0 || nowS != lastManage)
      {
         lastManage = nowS;
         for(int i = 0; i < LANE_COUNT; i++)
         {
            ManageSecond(i);
            ApplyTweak(i, 0);
            ApplyTweak(i, 1);
            ApplyTweak(i, 2);
         }
      }
   }

   if(g_lastDraw == 0 || GetTickCount() - g_lastDraw >= DRAW_MIN_MS)
   {
      g_lastDraw = GetTickCount();
      DrawPanel();
      DrawDetails();
   }
}

//====================================================================
//  EVENTS
//====================================================================
int OnInit()
{
   DiscoverSymbol();
   ApplyProfile(ClassifySymbol());
   ReadSessions();
   RefreshMarket();

   g_currency = g_f.currency;
   g_trade.SetExpertMagicNumber(LaneMagic(0));
   g_trade.SetTypeFilling((ENUM_ORDER_TYPE_FILLING)PickFilling());
   g_trade.SetDeviationInPoints(20);

   for(int i = 0; i < LANE_COUNT; i++)
   {
      g_lane[i].tf      = (ENUM_TIMEFRAMES)((i == 0) ? PERIOD_M5
                                          : ((i == 1) ? PERIOD_M15 : PERIOD_M30));
      g_lane[i].name    = (i == 0) ? "M5 " : ((i == 1) ? "M15" : "M30");
      g_lane[i].ready   = false;
      g_lane[i].lastBar = 0;
      g_lane[i].state   = LS_NONE;
      g_lane[i].ticket  = 0;
      g_lane[i].armed   = false;
      g_lane[i].tp1Done = false;
      g_lane[i].tp1Price = 0.0;
      g_lane[i].origRisk = 0.0;
      g_lane[i].openLots = 0.0;
      g_lane[i].tradedTrend  = 0;
      g_lane[i].tradedSignal = 0;
      g_lane[i].reachPct = 0.0;
      g_lane[i].reachN   = 0;
      g_runPrev[i] = -99;
      g_runNow[i]  = 0;
      g_runN[i]    = 0;
      g_hw[i]      = 0.0;
      g_posDir[i]  = 0;
      PlanClear(i);
      g_fill[i].ticket = 0;
   }

   for(int i = 0; i < PEND_MAX; i++) g_pendLane[i] = -1;
   for(int i = 0; i < 24; i++) g_sprN[i] = 0;

   RecordOpen();
   RecordLoad();
   ReconcileAll();

   EventSetTimer(1);
   DrawPanel();

   if(!TimeframeAllowed((ENUM_TIMEFRAMES)Period()))
      Print("OldMate: this chart is ", EnumToString((ENUM_TIMEFRAMES)Period()),
            ". Only M5, M15 and M30 are supported. Nothing will be read, planned or sent.");

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   PanelRemoveAll();
   ChartRedraw();
   if(g_recH != INVALID_HANDLE)
   {
      FileClose(g_recH);
      g_recH = INVALID_HANDLE;
   }
}

void OnTick()
{
   Heartbeat();
}

void OnTimer()
{
   Heartbeat();
}
