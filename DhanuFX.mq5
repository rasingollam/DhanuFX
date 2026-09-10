#property copyright "DhanuFX"
#property version   "2.33"
#property strict
#property description "HTF areas with matching LTF entries, money risk sizing, HTF wick SL, RR TP and validated entry filters."

#include "core/EntrySignal.mqh"
#include "core/SyntheticCandle.mqh"
#include "core/SignalGeometry.mqh"
#include "core/TradeRules.mqh"
#include <Trade/Trade.mqh>

enum SIGNAL_TIMEFRAME
{
   TF_M1=PERIOD_M1,    // M1 (1 minute)
   TF_M2=PERIOD_M2,    // M2 (2 minutes)
   TF_M3=PERIOD_M3,    // M3 (3 minutes)
   TF_M4=PERIOD_M4,    // M4 (4 minutes)
   TF_M5=PERIOD_M5,    // M5 (5 minutes)
   TF_M6=PERIOD_M6,    // M6 (6 minutes)
   TF_M10=PERIOD_M10,  // M10 (10 minutes)
   TF_M12=PERIOD_M12,  // M12 (12 minutes)
   TF_M15=PERIOD_M15,  // M15 (15 minutes)
   TF_M20=PERIOD_M20,  // M20 (20 minutes)
   TF_M30=PERIOD_M30,  // M30 (30 minutes)
   TF_H1=PERIOD_H1,    // H1 (1 hour)
   TF_M90=90,         // M90 (90 minutes)
   TF_H2=PERIOD_H2,    // H2 (2 hours)
   TF_H3=PERIOD_H3,    // H3 (3 hours)
   TF_H4=PERIOD_H4,    // H4 (4 hours)
   TF_H6=PERIOD_H6,    // H6 (6 hours)
   TF_H8=PERIOD_H8,    // H8 (8 hours)
   TF_H12=PERIOD_H12,  // H12 (12 hours)
   TF_D1=PERIOD_D1,    // D1 (1 day)
   TF_W1=PERIOD_W1,    // W1 (1 week)
   TF_MN1=PERIOD_MN1   // MN1 (1 month)
};

enum RISK_TYPE
{
   RISK_FIXED_MONEY=0,    // Fixed money (account currency)
   RISK_EQUITY_PERCENT=1  // Percentage of current account equity
};

enum STOP_MODE
{
   SL_HTF_WICK=0,  // Structural invalidation: last two HTF candle wick extremes
   SL_HTF_BODY=1,  // Zone body edge (tighter than the wick extreme)
   SL_LTF_SWING=2  // Extreme of the last N closed LTF candles behind the entry
};

input SIGNAL_TIMEFRAME Timeframe=TF_M90; // Higher timeframe / area of interest
input SIGNAL_TIMEFRAME Lower_Timeframe=TF_M5; // Lower timeframe / entry confirmation
input double Body_to_wick_ratio=20.0; // Maximum directional wick percentage (strictly less)
input RISK_TYPE Risk_Type=RISK_FIXED_MONEY; // Risk sizing method
input double Risk_Money=100.0; // Risk per trade in account currency (before costs/slippage)
input double Risk_Percent=1.0; // Equity percentage per trade (percentage mode only)
input double Take_Profit_RR=2.0; // Reward / risk: 2.0 = 1:2
input double Min_HTF_Source_Body_Percent=20.0; // Min HTF source body / full-range % (0 = off; verdict 20)
input double Max_Entry_Distance_R=0.25; // Max entry chases R beyond zone (0 = off; verdict 0.25)
input int Min_Zone_Age_Minutes=90; // Min zone age before entry, minutes (0 = off; verdict 90)
input STOP_MODE Stop_Mode=SL_HTF_WICK; // Stop loss placement method
input int Stop_Swing_Count=3; // LTF swing mode: extreme over the last N closed LTF candles (1..10)
input bool Enable_Trading=true; // False = draw HTF areas only
input ulong Magic_Number=26090901; // EA order identifier
input ulong Deviation_Points=20; // Allowed execution deviation in symbol points

CTrade trade;
InterestArea areas[];
datetime last_lower_bar=0;
datetime lower_retry=0;
int lower_seconds=0;

datetime last_bar=0;
ENUM_TIMEFRAMES signal_timeframe;
int signal_seconds=0;
string signal_label;
datetime next_history_retry=0;
datetime history_warning_bar=0;
string object_prefix;

int OnInit()
{
   if(!MathIsValidNumber(Body_to_wick_ratio) || Body_to_wick_ratio<0.0
      || Body_to_wick_ratio>100.0)
   {
      Print("Body_to_wick_ratio must be a percentage from 0 to 100.");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(!MathIsValidNumber(Min_HTF_Source_Body_Percent) || Min_HTF_Source_Body_Percent<0.0
      || Min_HTF_Source_Body_Percent>100.0)
   {
      Print("Min_HTF_Source_Body_Percent must be a percentage from 0 to 100.");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(!MathIsValidNumber(Max_Entry_Distance_R) || Max_Entry_Distance_R<0.0)
   {
      Print("Max_Entry_Distance_R must be >= 0.");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(Min_Zone_Age_Minutes<0)
   {
      Print("Min_Zone_Age_Minutes must be >= 0.");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(Stop_Swing_Count<1 || Stop_Swing_Count>10)
   {
      Print("Stop_Swing_Count must be from 1 to 10.");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(Stop_Mode==SL_LTF_SWING && Lower_Timeframe==TF_M90)
      Print("Stop mode LTF swing cannot build native M90 bars; entries fall back to the HTF wick stop.");
   signal_timeframe=(Timeframe==TF_M90 ? PERIOD_M1 : (ENUM_TIMEFRAMES)Timeframe);
   signal_seconds=(Timeframe==TF_M90 ? 5400 : PeriodSeconds(signal_timeframe));
   if(signal_seconds<=0) return INIT_PARAMETERS_INCORRECT;
   lower_seconds=(Lower_Timeframe==TF_M90 ? 5400 : PeriodSeconds((ENUM_TIMEFRAMES)Lower_Timeframe));
   if(lower_seconds<=0 || lower_seconds>=signal_seconds
      || !MathIsValidNumber(Take_Profit_RR) || Take_Profit_RR<=0)
   {
      Print("Lower timeframe must be below HTF. Take_Profit_RR must be positive.");
      return INIT_PARAMETERS_INCORRECT;
   }
   if((Risk_Type!=RISK_FIXED_MONEY && Risk_Type!=RISK_EQUITY_PERCENT)
      || (Risk_Type==RISK_FIXED_MONEY && (!MathIsValidNumber(Risk_Money) || Risk_Money<=0))
      || (Risk_Type==RISK_EQUITY_PERCENT && (!MathIsValidNumber(Risk_Percent) || Risk_Percent<=0 || Risk_Percent>100)))
   {
      Print("Invalid risk input: fixed money must be positive; equity percent must be greater than 0 and at most 100.");
      return INIT_PARAMETERS_INCORRECT;
   }
   const double volume_min=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   const double volume_max=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   const double volume_step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(volume_step<=0 || volume_min<=0 || volume_max<volume_min)
   {
      Print("Invalid symbol volume limits. Min=",volume_min," max=",volume_max," step=",volume_step);
      return INIT_PARAMETERS_INCORRECT;
   }
   trade.SetExpertMagicNumber(Magic_Number);
   trade.SetDeviationInPoints(Deviation_Points);
   trade.SetAsyncMode(false);
   if(!trade.SetTypeFillingBySymbol(_Symbol)) return INIT_FAILED;
   ArrayResize(areas,0);
   last_lower_bar=0;
   lower_retry=0;
   signal_label=(Timeframe==TF_M90 ? "M90" : EnumToString(signal_timeframe));
   StringReplace(signal_label,"PERIOD_","");
   object_prefix="DhanuFX_"+_Symbol+"_"+signal_label+"_";
   // Remove stale zones from ALL earlier timeframes/versions on this chart.
   ObjectsDeleteAll(0,"DhanuFX_"+_Symbol+"_");
   last_bar=0;
   next_history_retry=0;
   history_warning_bar=0;
   const string legend=object_prefix+"Legend";
   ObjectCreate(0,legend,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,legend,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,legend,OBJPROP_XDISTANCE,12);
   ObjectSetInteger(0,legend,OBJPROP_YDISTANCE,24);
   ObjectSetInteger(0,legend,OBJPROP_COLOR,clrGold);
   ObjectSetInteger(0,legend,OBJPROP_FONTSIZE,10);
   ObjectSetString(0,legend,OBJPROP_TEXT,"DhanuFX | Signal: "+signal_label+" | Gold = [2] body | Blue = [1] body | Dashed = zone");
Print("DhanuFX visualization ready: ",signal_label,
          ", LTF=",EnumToString(Lower_Timeframe),", wick threshold ",DoubleToString(Body_to_wick_ratio,2),
          "%, risk mode=",EnumToString(Risk_Type),", risk input=",
          (Risk_Type==RISK_FIXED_MONEY ? Risk_Money : Risk_Percent),
          (Risk_Type==RISK_FIXED_MONEY ? " "+AccountInfoString(ACCOUNT_CURRENCY) : "% equity"),
          ", RR=",Take_Profit_RR,", filters: source body>=",DoubleToString(Min_HTF_Source_Body_Percent,2),
          "%, entry distance<=",DoubleToString(Max_Entry_Distance_R,3),"R, zone age>=",Min_Zone_Age_Minutes,"m, stop mode=",EnumToString(Stop_Mode),
          (Stop_Mode==SL_LTF_SWING ? " (swing "+(string)Stop_Swing_Count+")" : ""),", trading=",Enable_Trading);
    return INIT_SUCCEEDED;
}

bool DrawSignal(const EntrySignal signal,const MqlRates &older,const MqlRates &previous,
                const datetime confirmation)
{
   const string direction=(signal==ENTRY_SELL ? "SELL" : "BUY");
   const string name=object_prefix+direction+"_"+IntegerToString((long)older.time);
   SignalGeometry geometry;
   BuildSignalGeometry(older,previous,confirmation,signal_seconds,geometry);
   if(Timeframe==TF_MN1)
   {
      MqlDateTime date;
      if(!TimeToStruct(confirmation,date)) return false;
      date.mon+=5;
      if(date.mon>12) { date.mon-=12; date.year++; }
      geometry.right=StructToTime(date);
      if(!TimeToStruct(older.time,date)) return false;
      date.mon++;
      if(date.mon>12) { date.mon=1; date.year++; }
      geometry.body_right=StructToTime(date);
      if(!TimeToStruct(previous.time,date)) return false;
      date.mon++;
      if(date.mon>12) { date.mon=1; date.year++; }
      geometry.arrow_time=StructToTime(date)-1;
   }
   const string details=direction+" | "+signal_label
      +" | candle[2] "+TimeToString(older.time)
      +" O="+DoubleToString(older.open,_Digits)+" C="+DoubleToString(older.close,_Digits)
      +" | signal candle "+TimeToString(previous.time)
      +" open="+DoubleToString(previous.open,_Digits)
      +" close="+DoubleToString(previous.close,_Digits)
      +" | confirmed "+TimeToString(confirmation);
   ResetLastError();
   if(!ObjectCreate(0,name,OBJ_RECTANGLE,0,geometry.body_right,geometry.top,geometry.right,geometry.bottom))
   {
      Print("Rectangle creation failed: ",name," error ",GetLastError());
      return false;
   }
   bool success=true;
   if(!ObjectSetInteger(0,name,OBJPROP_COLOR,signal==ENTRY_SELL ? clrLightCoral : clrMediumSeaGreen)) success=false;
   if(!ObjectSetInteger(0,name,OBJPROP_FILL,false)) success=false;
   if(!ObjectSetInteger(0,name,OBJPROP_STYLE,STYLE_DASH)) success=false;
   if(!ObjectSetInteger(0,name,OBJPROP_WIDTH,1)) success=false;
   if(!ObjectSetInteger(0,name,OBJPROP_BACK,false)) success=false;
   if(!ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false)) success=false;
   if(!ObjectSetInteger(0,name,OBJPROP_HIDDEN,false)) success=false;
   if(!ObjectSetString(0,name,OBJPROP_TOOLTIP,details)) success=false;
   // Separate, bright source body: exact selected-timeframe O/C and duration.
   // No filled projection obscures the underlying chart candles.
   const string source=name+"_Body2";
   if(!ObjectCreate(0,source,OBJ_RECTANGLE,0,geometry.left,geometry.top,geometry.body_right,geometry.bottom)) success=false;
   if(!ObjectSetInteger(0,source,OBJPROP_COLOR,clrGold)) success=false;
   if(!ObjectSetInteger(0,source,OBJPROP_FILL,false)) success=false;
   if(!ObjectSetInteger(0,source,OBJPROP_WIDTH,2)) success=false;
   if(!ObjectSetInteger(0,source,OBJPROP_BACK,false)) success=false;
   if(!ObjectSetInteger(0,source,OBJPROP_SELECTABLE,false)) success=false;
   if(!ObjectSetString(0,source,OBJPROP_TOOLTIP,"SOURCE BODY | "+details)) success=false;
   const string label=name+"_BodyLabel";
   if(!ObjectCreate(0,label,OBJ_TEXT,0,geometry.left,geometry.top)) success=false;
   if(!ObjectSetString(0,label,OBJPROP_TEXT,signal_label+" [2]")) success=false;
   if(!ObjectSetInteger(0,label,OBJPROP_ANCHOR,ANCHOR_LEFT_LOWER)) success=false;
   if(!ObjectSetInteger(0,label,OBJPROP_COLOR,clrGold)) success=false;
   if(!ObjectSetInteger(0,label,OBJPROP_FONTSIZE,9)) success=false;
   if(!ObjectSetInteger(0,label,OBJPROP_BACK,false)) success=false;
   if(!ObjectSetInteger(0,label,OBJPROP_SELECTABLE,false)) success=false;
   if(!ObjectSetString(0,label,OBJPROP_TOOLTIP,"SOURCE BODY | "+details)) success=false;
   // Signal candle body spans its own interval only, including custom M90.
   const double signal_top=MathMax(previous.open,previous.close);
   const double signal_bottom=MathMin(previous.open,previous.close);
   const string body1=name+"_Body1";
   if(!ObjectCreate(0,body1,OBJ_RECTANGLE,0,previous.time,signal_top,
                    geometry.arrow_time+1,signal_bottom)) success=false;
   if(!ObjectSetInteger(0,body1,OBJPROP_COLOR,clrDeepSkyBlue)) success=false;
   if(!ObjectSetInteger(0,body1,OBJPROP_FILL,false)) success=false;
   if(!ObjectSetInteger(0,body1,OBJPROP_STYLE,STYLE_SOLID)) success=false;
   if(!ObjectSetInteger(0,body1,OBJPROP_WIDTH,2)) success=false;
   if(!ObjectSetInteger(0,body1,OBJPROP_BACK,false)) success=false;
   if(!ObjectSetInteger(0,body1,OBJPROP_SELECTABLE,false)) success=false;
   if(!ObjectSetInteger(0,body1,OBJPROP_HIDDEN,false)) success=false;
   if(!ObjectSetString(0,body1,OBJPROP_TOOLTIP,"SIGNAL BODY [1] | "+details)) success=false;
   const string label1=name+"_Body1Label";
   if(!ObjectCreate(0,label1,OBJ_TEXT,0,previous.time,signal_top)) success=false;
   if(!ObjectSetString(0,label1,OBJPROP_TEXT,signal_label+" [1]")) success=false;
   if(!ObjectSetInteger(0,label1,OBJPROP_ANCHOR,ANCHOR_LEFT_LOWER)) success=false;
   if(!ObjectSetInteger(0,label1,OBJPROP_COLOR,clrDeepSkyBlue)) success=false;
   if(!ObjectSetInteger(0,label1,OBJPROP_FONTSIZE,9)) success=false;
   if(!ObjectSetInteger(0,label1,OBJPROP_BACK,false)) success=false;
   if(!ObjectSetInteger(0,label1,OBJPROP_SELECTABLE,false)) success=false;
   if(!ObjectSetString(0,label1,OBJPROP_TOOLTIP,"SIGNAL BODY [1] | "+details)) success=false;
   if(!success)
      Print("Signal drawing failed: ",name," error ",GetLastError());
   ChartRedraw(0);
   return success;
}

bool ReadClosedCandles(const SIGNAL_TIMEFRAME timeframe,const datetime current_bar,
                       MqlRates &older,MqlRates &previous)
{
   if(timeframe==TF_M90)
   {
      const int seconds=5400;
      const datetime start=current_bar-(datetime)(2*seconds);
      MqlRates minutes[];
      // Fetch an earlier boundary too, to establish coverage before both candles.
      const int copied=CopyRates(_Symbol,PERIOD_M1,start-(datetime)seconds,(datetime)(current_bar-1),minutes);
      if(copied<=0 || !SeriesInfoInteger(_Symbol,PERIOD_M1,SERIES_SYNCHRONIZED))
         return false;
      if(minutes[0].time>start) return false;
      // MT5 compresses missing chart bars. A partly traded M90 session interval
      // would otherwise draw as a narrowed "M90" body and change its OHLC.
      if(!HasM90Components(minutes,start)
         || !HasM90Components(minutes,current_bar-(datetime)seconds))
         return false;
      return AggregateMinutes(minutes,start,current_bar-(datetime)seconds,older)
             && AggregateMinutes(minutes,current_bar-(datetime)seconds,current_bar,previous);
   }

   // Static arrays receive oldest data first: [0]=candle[2], [1]=candle[1].
   MqlRates candles[3];
   if(CopyRates(_Symbol,(ENUM_TIMEFRAMES)timeframe,0,3,candles)!=3)
      return false;
   if(candles[2].time!=current_bar)
      return false;
   older=candles[0];
   previous=candles[1];
   return true;
}

// Swing stop from the last N closed native LTF candles behind the entry pattern.
// Returns false when the lower timeframe is synthetic (M90) or history is missing,
// so the caller can fall back to a structural stop.
bool LtfSwingStop(const EntrySignal direction,const int count,double &result)
{
   if(Lower_Timeframe==TF_M90 || count<1 || count>10)
      return false;
   double extreme=0;
   for(int shift=1; shift<=count; shift++)
   {
      const double value=(direction==ENTRY_BUY
                          ? iLow(_Symbol,(ENUM_TIMEFRAMES)Lower_Timeframe,shift)
                          : iHigh(_Symbol,(ENUM_TIMEFRAMES)Lower_Timeframe,shift));
      if(value<=0)
         return false;
      extreme=(shift==1 ? value
               : (direction==ENTRY_BUY ? MathMin(extreme,value) : MathMax(extreme,value)));
   }
   result=extreme;
   return true;
}

void ProcessHigherTimeframe()
{
   const datetime now=TimeCurrent();
   const datetime current_bar=(Timeframe==TF_M90
                              ? SyntheticBarStart(now,90)
                              : iTime(_Symbol,signal_timeframe,0));
   if(current_bar==0 || current_bar==last_bar)
      return;

   // First attachment can occur mid-candle: wait for the next genuine new bar.
   if(last_bar==0)
   {
      last_bar=current_bar;
      return;
   }
   if(now<next_history_retry)
      return;
   MqlRates older,previous;
   if(!ReadClosedCandles(Timeframe,current_bar,older,previous))
   {
      // A failed history read is not a processed signal. Retry once per minute.
      next_history_retry=now-(now%60)+60;
      if(history_warning_bar!=current_bar)
      {
         Print("Waiting for complete closed-candle history | ",signal_label," | ",
               TimeToString(current_bar),". M90 requires data in each of its three M30 sections; partial session intervals will not signal.");
         history_warning_bar=current_bar;
      }
      return;
   }
   next_history_retry=0;
   last_bar=current_bar;
   const EntrySignal signal=DetectEntry(older,previous,Body_to_wick_ratio);
   if(signal==ENTRY_NONE)
      return;

   Print(signal==ENTRY_SELL ? "SELL" : "BUY"," signal | ",_Symbol," | ",
         signal_label," | confirmed ",TimeToString(current_bar),
         " | candle[2] ",TimeToString(older.time));
   const double body=MathAbs(previous.close-previous.open);
   const double wick=(signal==ENTRY_SELL ? previous.close-previous.low : previous.high-previous.close);
   Print("Signal evidence | candle[2] O/H/L/C=",older.open,"/",older.high,"/",older.low,"/",older.close,
         " | candle[1] O/H/L/C=",previous.open,"/",previous.high,"/",previous.low,"/",previous.close,
         " | directional wick %=",DoubleToString(100.0*wick/(body+wick),4));
   DrawSignal(signal,older,previous,current_bar);
   AddInterestArea(signal,older,previous,current_bar);
}

void AddInterestArea(const EntrySignal signal,const MqlRates &older,
                     const MqlRates &previous,const datetime confirmation)
{
   InterestArea area;
   area.direction=signal;
   area.confirmed=confirmation;
   area.available=TimeCurrent();
   area.expires=confirmation+(datetime)(5*signal_seconds);
   if(Timeframe==TF_MN1)
   {
      MqlDateTime date;
      if(!TimeToStruct(confirmation,date)) return;
      date.mon+=5;
      if(date.mon>12) { date.mon-=12; date.year++; }
      area.expires=StructToTime(date);
   }
   area.top=MathMax(older.open,older.close);
   area.bottom=MathMin(older.open,older.close);
   area.stop=(signal==ENTRY_BUY ? MathMin(older.low,previous.low) : MathMax(older.high,previous.high));
   area.source_body_percent=ComputeSourceBodyPercent(older);
   area.consumed=false;
   const int count=ArraySize(areas);
   if(ArrayResize(areas,count+1)!=count+1) { Print("Cannot allocate interest area"); return; }
   areas[count]=area;
   Print("Area activated | ",signal_label," | ",TimeToString(confirmation),
         " | body=",area.bottom,"..",area.top," | wick SL=",area.stop," | expires=",TimeToString(area.expires));
}

void MaintainAreas(const MqlTick &tick)
{
   int keep=0;
   for(int i=0;i<ArraySize(areas);i++)
   {
      if(areas[i].consumed || tick.time>=areas[i].expires) continue;
      if(AreaStopBreached(areas[i],tick.bid,tick.ask))
      {
         Print("Area invalidated at HTF wick extreme | ",TimeToString(areas[i].confirmed));
         continue;
      }
      areas[keep++]=areas[i];
   }
   ArrayResize(areas,keep);
}

bool SymbolHasExposure()
{
   // Avoid netting into, closing, or interfering with another symbol position.
   for(int i=PositionsTotal()-1;i>=0;i--)
      if(PositionGetSymbol(i)==_Symbol) return true;
   for(int i=OrdersTotal()-1;i>=0;i--)
      if(OrderGetTicket(i)>0 && OrderGetString(ORDER_SYMBOL)==_Symbol) return true;
   return false;
}

bool CalculateRiskVolume(const EntrySignal signal,const MqlTick &quote,const double stop,
                         double &volume,double &estimated_loss,double &risk_budget)
{
   // Snapshot equity once per candidate, including floating P/L on the account.
   risk_budget=(Risk_Type==RISK_FIXED_MONEY ? Risk_Money
                : PercentageRiskBudget(AccountInfoDouble(ACCOUNT_EQUITY),Risk_Percent));
   if(!MathIsValidNumber(risk_budget) || risk_budget<=0)
   {
      Print("Entry skipped: risk budget is not positive (check account equity).");
      return false;
   }
   const ENUM_ORDER_TYPE type=(signal==ENTRY_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   const double entry=(signal==ENTRY_BUY ? quote.ask : quote.bid);
   const double minimum=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maximum=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   const double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   const double directional_limit=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_LIMIT);
   if(directional_limit>0) maximum=MathMin(maximum,directional_limit);
   double reference_profit=0;
   // A broker-valid reference volume avoids assuming 1.0 lot is supported.
   if(!OrderCalcProfit(type,_Symbol,minimum,entry,stop,reference_profit)
      || !MathIsValidNumber(reference_profit) || reference_profit>=0)
   {
      Print("Entry skipped: cannot calculate stop loss in account currency. Error=",GetLastError());
      return false;
   }
   volume=NormalizeDouble(RiskSizedVolume(risk_budget,-reference_profit/minimum,minimum,maximum,step),8);
   if(volume<=0)
   {
      Print("Entry skipped: minimum lot exceeds risk budget ",risk_budget," ",AccountInfoString(ACCOUNT_CURRENCY));
      return false;
   }
   double profit=0;
   if(!OrderCalcProfit(type,_Symbol,volume,entry,stop,profit) || !MathIsValidNumber(profit) || profit>=0)
      return false;
   estimated_loss=-profit;
   if(estimated_loss>risk_budget+1e-8)
   {
      Print("Entry skipped: calculated volume exceeds risk budget.");
      return false;
   }
   return true;
}

void ProcessLowerTimeframe(const MqlTick &tick)
{
   const datetime bar=(Lower_Timeframe==TF_M90 ? SyntheticBarStart(tick.time,90)
                       : iTime(_Symbol,(ENUM_TIMEFRAMES)Lower_Timeframe,0));
   if(bar==0 || bar==last_lower_bar) return;
   if(last_lower_bar==0) { last_lower_bar=bar; return; }
   if(tick.time<lower_retry) return;
   MqlRates older,previous;
   if(!ReadClosedCandles(Lower_Timeframe,bar,older,previous))
   {
      lower_retry=tick.time+1;
      return;
   }
   lower_retry=0;
   last_lower_bar=bar; // Never submit more than once for this closed LTF pattern.
   if(!Enable_Trading || SymbolHasExposure()) return;
   const EntrySignal signal=DetectEntry(older,previous,Body_to_wick_ratio);
   if(signal==ENTRY_NONE) return;
   for(int i=ArraySize(areas)-1;i>=0;i--)
   {
      if(!AreaEntryMatches(areas[i],older,previous,tick.time,signal)) continue;
      if(!MQLInfoInteger(MQL_TRADE_ALLOWED) || !TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)
         || !AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) || !AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
      {
         Print("Entry skipped: automated trading is disabled.");
         return;
      }
      double stop=0,target=0;
      string stop_mode="wick";
      double raw_stop=areas[i].stop;
      if(Stop_Mode==SL_HTF_BODY)
      {
         raw_stop=(signal==ENTRY_BUY ? areas[i].bottom : areas[i].top);
         stop_mode="body";
      }
      else if(Stop_Mode==SL_LTF_SWING)
      {
         double swing=0;
         if(LtfSwingStop(signal,Stop_Swing_Count,swing))
         {
            raw_stop=swing;
            stop_mode="ltf_swing";
         }
         else Print("Stop mode LTF swing unavailable on LTF=",EnumToString(Lower_Timeframe),
                    "; using HTF wick stop for this entry.");
      }
      MqlTick entry_quote;
      if(!SymbolInfoTick(_Symbol,entry_quote)) return;
      if(entry_quote.time>=areas[i].expires
         || AreaStopBreached(areas[i],entry_quote.bid,entry_quote.ask)) return;
      const double tick_size=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
      const double minimum=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*_Point;
      if(!CalculateTradePrices(signal,entry_quote.bid,entry_quote.ask,raw_stop,Take_Profit_RR,tick_size,minimum,stop,target))
      {
         Print("Entry skipped: ",stop_mode," SL/TP is invalid at this quote or violates broker minimum distance.");
         return;
      }
      stop=NormalizeDouble(stop,_Digits);
      target=NormalizeDouble(target,_Digits);
      const double entry_price=(signal==ENTRY_BUY ? entry_quote.ask : entry_quote.bid);
      const double stop_distance=MathAbs(entry_price-stop);
      const double chase_r=EntryDistanceR(areas[i],entry_price,stop_distance);
      if(!EntryFilterPass(areas[i],chase_r,Min_HTF_Source_Body_Percent,Max_Entry_Distance_R,
                          (long)entry_quote.time,Min_Zone_Age_Minutes))
      {
         Print("Entry filter skipped | ",signal==ENTRY_BUY ? "BUY" : "SELL",
               " | zone=",TimeToString(areas[i].confirmed),
               " | source body %=",DoubleToString(areas[i].source_body_percent,2),
               " | chase R=",DoubleToString(chase_r,3),
               " | zone age min=",DoubleToString((long)(entry_quote.time-areas[i].confirmed)/60.0,1));
         return;
      }
      double volume=0,estimated_loss=0,risk_budget=0;
      if(!CalculateRiskVolume(signal,entry_quote,stop,volume,estimated_loss,risk_budget)) return;
      const string comment="DhanuFX "+IntegerToString((long)areas[i].confirmed);
      const bool submitted=(signal==ENTRY_BUY
         ? trade.Buy(volume,_Symbol,0,stop,target,comment)
         : trade.Sell(volume,_Symbol,0,stop,target,comment));
      const uint code=trade.ResultRetcode();
      // Accepted, partially filled, placed, or uncertain timeout: never duplicate.
      if(code==TRADE_RETCODE_DONE || code==TRADE_RETCODE_DONE_PARTIAL
         || code==TRADE_RETCODE_PLACED || code==TRADE_RETCODE_TIMEOUT)
         areas[i].consumed=true;
Print("LTF entry | ",EnumToString(Lower_Timeframe)," | ",signal==ENTRY_BUY ? "BUY" : "SELL",
             " | zone=",TimeToString(areas[i].confirmed)," | stop mode=",stop_mode,
             " | SL=",stop," TP=",target,
            " | lots=",volume," | estimated risk=",estimated_loss," ",AccountInfoString(ACCOUNT_CURRENCY),
            " | budget=",risk_budget," | risk mode=",EnumToString(Risk_Type),
            " | entry spread=",DoubleToString(entry_quote.ask-entry_quote.bid,_Digits),
            " | zone age min=",DoubleToString((long)(entry_quote.time-areas[i].confirmed)/60.0,1),
            " | chase R=",DoubleToString(chase_r,4),
            " | HTF body %=",DoubleToString(areas[i].source_body_percent,2),
            " | submitted=",submitted," | retcode=",code," ",trade.ResultRetcodeDescription(),
            " | deal=",trade.ResultDeal()," | fill=",trade.ResultPrice());
      return;
   }
}

void OnTick()
{
   ProcessHigherTimeframe();
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick) || tick.bid<=0 || tick.ask<tick.bid) return;
   MaintainAreas(tick);
   ProcessLowerTimeframe(tick);
}

// Keep rectangles after removal/test completion for inspection.
void OnDeinit(const int reason) {}
