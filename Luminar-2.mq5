#property copyright "Luminar-2"
#property version   "3.00"
#property strict
#property description "HTF signal candle drawing and area selection with a configurable directional wick threshold. Visualization only; no order submission."

#include "core/EntrySignal.mqh"
#include "core/SyntheticCandle.mqh"
#include "core/SignalGeometry.mqh"
#include "core/TradeRules.mqh"

enum SIGNAL_PERIOD
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
   TF_M90=90,          // M90 (90 minutes)
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

input SIGNAL_PERIOD SIGNAL_TIMEFRAME=TF_M90; // Higher timeframe / signal candle
input double Body_to_wick_ratio=20.0; // Maximum directional wick percentage (strictly less)

InterestArea areas[];
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
   signal_timeframe=(SIGNAL_TIMEFRAME==TF_M90 ? PERIOD_M1 : (ENUM_TIMEFRAMES)SIGNAL_TIMEFRAME);
   signal_seconds=(SIGNAL_TIMEFRAME==TF_M90 ? 5400 : PeriodSeconds(signal_timeframe));
   if(signal_seconds<=0) return INIT_PARAMETERS_INCORRECT;
   signal_label=(SIGNAL_TIMEFRAME==TF_M90 ? "M90" : EnumToString(signal_timeframe));
   StringReplace(signal_label,"PERIOD_","");
   object_prefix="Luminar_"+_Symbol+"_"+signal_label+"_";
   // Remove stale zones from ALL earlier timeframes/versions on this chart,
   // including drawings left by the former DhanuFX releases.
   ObjectsDeleteAll(0,"Luminar_"+_Symbol+"_");
   ObjectsDeleteAll(0,"DhanuFX_"+_Symbol+"_");
   ArrayResize(areas,0);
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
   ObjectSetString(0,legend,OBJPROP_TEXT,"Luminar-2 | Signal: "+signal_label+" | Gold = [2] body | Blue = [1] body | Dashed = zone");
   Print("Luminar-2 visualization ready: ",signal_label,
         ", wick threshold ",DoubleToString(Body_to_wick_ratio,2),"%.");
   return INIT_SUCCEEDED;
}

bool DrawSignal(const EntrySignal signal,const MqlRates &older,const MqlRates &previous,
                const datetime confirmation)
{
   const string direction=(signal==ENTRY_SELL ? "SELL" : "BUY");
   const string name=object_prefix+direction+"_"+IntegerToString((long)older.time);
   SignalGeometry geometry;
   BuildSignalGeometry(older,previous,confirmation,signal_seconds,geometry);
   if(SIGNAL_TIMEFRAME==TF_MN1)
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

bool ReadClosedCandles(const SIGNAL_PERIOD timeframe,const datetime current_bar,
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

void ProcessHigherTimeframe()
{
   const datetime now=TimeCurrent();
   const datetime current_bar=(SIGNAL_TIMEFRAME==TF_M90
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
   if(!ReadClosedCandles(SIGNAL_TIMEFRAME,current_bar,older,previous))
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
   if(SIGNAL_TIMEFRAME==TF_MN1)
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

void OnTick()
{
   ProcessHigherTimeframe();
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick) || tick.bid<=0 || tick.ask<tick.bid) return;
   MaintainAreas(tick);
}

// Keep rectangles after removal/test completion for inspection.
void OnDeinit(const int reason) {}