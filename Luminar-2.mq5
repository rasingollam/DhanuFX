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
input int Anchor_sweep_lookback=3; // Prior HTF candles used for alternate anchor high/low sweep
input string Broker_day_start_time="00:00"; // Broker server session start (HH:MI)
input double Value_area_percent=68.8; // Prior-day tick-volume value area
input int Volume_profile_bin_points=10; // Price bin size in chart points
input int Day_separator_count=20; // Broker-day boundaries to draw

InterestArea areas[];
datetime last_bar=0;
ENUM_TIMEFRAMES signal_timeframe;
int signal_seconds=0;
string signal_label;
datetime next_history_retry=0;
datetime history_warning_bar=0;
string object_prefix;
int buy_signal_count=0;
int sell_signal_count=0;
const int dashboard_line_count=16;
int broker_day_hour=0;
int broker_day_minute=0;
datetime last_profile_session=0;

void UpdateSignalCounter()
{
   const string counter=object_prefix+"Counter";
   ObjectSetString(0,counter,OBJPROP_TEXT,
                    "SIGNALS     BUY  "+(string)buy_signal_count
                    +"     SELL  "+(string)sell_signal_count
                    +"     TOTAL  "+(string)(buy_signal_count+sell_signal_count));
}

string CheckBox(const bool passed)
{
   return (passed ? "[x]" : "[ ]");
}

bool WickPass(const double body,const double wick)
{
   return wick>=0.0 && body+wick>0.0
          && 100.0*wick<Body_to_wick_ratio*(body+wick);
}

double WickPercent(const double body,const double wick)
{
   return (body+wick>0.0 ? 100.0*wick/(body+wick) : 0.0);
}

string BuildFastChecks(const MqlRates &mid,const MqlRates &signal,
                       const double prior_high,const double prior_low)
{
   if(mid.close==mid.open)
      return "[2] -> [1]  WAITING\n[ ] Anchor [2] is a doji";
   const bool sell=(mid.close>mid.open);
   const string side=(sell ? "high" : "low");
   const bool breaker_direction=(sell ? signal.close<signal.open : signal.close>signal.open);
   const bool close_break=(sell ? signal.close<mid.open : signal.close>mid.open);
   const bool breaker_sweep=(sell ? signal.high>mid.high : signal.low<mid.low);
   const bool anchor_sweep=(sell ? mid.high>prior_high : mid.low<prior_low);
   const double breaker_body=MathAbs(signal.close-signal.open);
   const double breaker_wick=(sell ? signal.close-signal.low : signal.high-signal.close);
   const double anchor_body=MathAbs(mid.close-mid.open);
   const double anchor_wick=(sell ? mid.open-mid.low : mid.high-mid.close);
   const bool breaker_wick_pass=WickPass(breaker_body,breaker_wick);
   const bool anchor_wick_pass=WickPass(anchor_body,anchor_wick);
   const bool ready=breaker_direction && close_break && (breaker_sweep || anchor_sweep)
                    && breaker_wick_pass && anchor_wick_pass;
   return "[2] -> [1]  "+(sell ? "SELL" : "BUY")+"\n"
      +"[x] Anchor [2] "+(sell ? "bullish" : "bearish")+"\n"
      +CheckBox(breaker_direction)+" Breaker [1] "+(sell ? "bearish" : "bullish")+"\n"
      +CheckBox(close_break)+" [1] close crosses [2] open\n"
      +CheckBox(breaker_sweep)+" [1] takes [2] "+side+"\n"
      +CheckBox(anchor_sweep)+" [2] takes prior "+(string)Anchor_sweep_lookback+" HTF "+side+"\n"
      +CheckBox(breaker_wick_pass)+" [1] wick "+DoubleToString(WickPercent(breaker_body,breaker_wick),1)+"%\n"
      +CheckBox(anchor_wick_pass)+" [2] wick "+DoubleToString(WickPercent(anchor_body,anchor_wick),1)+"%\n"
      +CheckBox(ready)+" RESULT";
}

string BuildSlowChecks(const MqlRates &source,const MqlRates &mid,const MqlRates &signal,
                       const double prior_high,const double prior_low)
{
   if(source.close==source.open)
      return "[3] -> [2]+[1]  WAITING\n[ ] Anchor [3] is a doji";
   const bool sell=(source.close>source.open);
   const string side=(sell ? "high" : "low");
   const double breaker_open=mid.open;
   const double breaker_close=signal.close;
   const double breaker_high=MathMax(mid.high,signal.high);
   const double breaker_low=MathMin(mid.low,signal.low);
   const bool breaker_direction=(sell ? breaker_close<breaker_open : breaker_close>breaker_open);
   const bool open_side=(sell ? signal.open>=source.open : signal.open<=source.open);
   const bool close_break=(sell ? signal.close<source.open : signal.close>source.open);
   const bool breaker_sweep=(sell ? breaker_high>source.high : breaker_low<source.low);
   const bool anchor_sweep=(sell ? source.high>prior_high : source.low<prior_low);
   const double breaker_body=MathAbs(breaker_close-breaker_open);
   const double breaker_wick=(sell ? breaker_close-breaker_low : breaker_high-breaker_close);
   const double anchor_body=MathAbs(source.close-source.open);
   const double anchor_wick=(sell ? source.open-source.low : source.high-source.close);
   const bool breaker_wick_pass=WickPass(breaker_body,breaker_wick);
   const bool anchor_wick_pass=WickPass(anchor_body,anchor_wick);
   const bool ready=breaker_direction && open_side && close_break && (breaker_sweep || anchor_sweep)
                    && breaker_wick_pass && anchor_wick_pass;
   return "[3] -> [2]+[1]  "+(sell ? "SELL" : "BUY")+"\n"
      +"[x] Anchor [3] "+(sell ? "bullish" : "bearish")+"\n"
      +CheckBox(breaker_direction)+" Combined [2]+[1] "+(sell ? "bearish" : "bullish")+"\n"
      +CheckBox(open_side)+" [1] opens on unbroken side\n"
      +CheckBox(close_break)+" [1] close crosses [3] open\n"
      +CheckBox(breaker_sweep)+" Combined breaker takes [3] "+side+"\n"
      +CheckBox(anchor_sweep)+" [3] takes prior "+(string)Anchor_sweep_lookback+" HTF "+side+"\n"
      +CheckBox(breaker_wick_pass)+" Combined wick "+DoubleToString(WickPercent(breaker_body,breaker_wick),1)+"%\n"
      +CheckBox(anchor_wick_pass)+" [3] wick "+DoubleToString(WickPercent(anchor_body,anchor_wick),1)+"%\n"
      +CheckBox(ready)+" RESULT";
}

void UpdateLiveChecksText(const MqlRates &source,const MqlRates &mid,const MqlRates &signal,
                          const double source_prior_high,const double source_prior_low,
                          const double mid_prior_high,const double mid_prior_low)
{
   const string checks="LIVE CLOSED "+signal_label+" CANDLES  |  "+TimeToString(signal.time,TIME_DATE|TIME_MINUTES)
      +"\n\n"+BuildFastChecks(mid,signal,mid_prior_high,mid_prior_low)
      +"\n\n"+BuildSlowChecks(source,mid,signal,source_prior_high,source_prior_low);
   ObjectSetString(0,object_prefix+"Checks",OBJPROP_TEXT,checks);
}

void SetDashboardLine(const int row,const string text,const color line_color)
{
   if(row<0 || row>=dashboard_line_count)
      return;
   const string name=object_prefix+"CheckLine"+(string)row;
   ObjectSetString(0,name,OBJPROP_TEXT,(text=="" ? " " : text));
   ObjectSetInteger(0,name,OBJPROP_COLOR,line_color);
}

void AddDashboardLine(int &row,const string text,const color line_color)
{
   SetDashboardLine(row,text,line_color);
   row++;
}

void AddCheckLine(int &row,const bool passed,const string text)
{
   AddDashboardLine(row,CheckBox(passed)+"  "+text,(passed ? clrLimeGreen : clrLightCoral));
}

void AddFastDashboardChecks(const MqlRates &mid,const MqlRates &signal,
                            const double prior_high,const double prior_low,int &row)
{
   if(mid.close==mid.open)
   {
      AddDashboardLine(row,"ONE-CANDLE  [2] -> [1]  |  WAITING",clrDeepSkyBlue);
      AddCheckLine(row,false,"Anchor [2] direction: doji");
      return;
   }
   const bool sell=(mid.close>mid.open);
   const string side=(sell ? "high" : "low");
   const bool breaker_direction=(sell ? signal.close<signal.open : signal.close>signal.open);
   const bool close_break=(sell ? signal.close<mid.open : signal.close>mid.open);
   const bool breaker_sweep=(sell ? signal.high>mid.high : signal.low<mid.low);
   const bool anchor_sweep=(sell ? mid.high>prior_high : mid.low<prior_low);
   const double breaker_body=MathAbs(signal.close-signal.open);
   const double breaker_wick=(sell ? signal.close-signal.low : signal.high-signal.close);
   const double anchor_body=MathAbs(mid.close-mid.open);
   const double anchor_wick=(sell ? mid.open-mid.low : mid.high-mid.close);
   const bool breaker_wick_pass=WickPass(breaker_body,breaker_wick);
   const bool anchor_wick_pass=WickPass(anchor_body,anchor_wick);
   const bool ready=breaker_direction && close_break && (breaker_sweep || anchor_sweep)
                    && breaker_wick_pass && anchor_wick_pass;
   AddDashboardLine(row,"PRIORITY  ONE-CANDLE  [2] -> [1]  |  "+(sell ? "SELL" : "BUY"),clrDeepSkyBlue);
   AddDashboardLine(row,"[x]  Anchor [2] "+(sell ? "bullish" : "bearish")
                    +"    "+CheckBox(breaker_direction)+"  Breaker [1] "+(sell ? "bearish" : "bullish"),
                    (breaker_direction ? clrLimeGreen : clrLightCoral));
   AddCheckLine(row,close_break,"[1] close crosses [2] open");
   AddDashboardLine(row,CheckBox(breaker_sweep)+"  [1] takes [2] "+side
                    +"    "+CheckBox(anchor_sweep)+"  [2] takes prior "+(string)Anchor_sweep_lookback+" HTF "+side,
                    ((breaker_sweep || anchor_sweep) ? clrLimeGreen : clrLightCoral));
   AddDashboardLine(row,CheckBox(breaker_wick_pass)+"  [1] wick "+DoubleToString(WickPercent(breaker_body,breaker_wick),1)+"%"
                    +"    "+CheckBox(anchor_wick_pass)+"  [2] wick "+DoubleToString(WickPercent(anchor_body,anchor_wick),1)+"%",
                    ((breaker_wick_pass && anchor_wick_pass) ? clrLimeGreen : clrLightCoral));
   AddCheckLine(row,ready,"ONE-CANDLE RESULT");
}

void AddSlowDashboardChecks(const MqlRates &source,const MqlRates &mid,const MqlRates &signal,
                            const double prior_high,const double prior_low,int &row)
{
   if(source.close==source.open)
   {
      AddDashboardLine(row,"TWO-CANDLE  [3] -> [2]+[1]  |  WAITING",clrGold);
      AddCheckLine(row,false,"Anchor [3] direction: doji");
      return;
   }
   const bool sell=(source.close>source.open);
   const string side=(sell ? "high" : "low");
   const double breaker_open=mid.open;
   const double breaker_close=signal.close;
   const double breaker_high=MathMax(mid.high,signal.high);
   const double breaker_low=MathMin(mid.low,signal.low);
   const bool breaker_direction=(sell ? breaker_close<breaker_open : breaker_close>breaker_open);
   const bool open_side=(sell ? signal.open>=source.open : signal.open<=source.open);
   const bool close_break=(sell ? signal.close<source.open : signal.close>source.open);
   const bool breaker_sweep=(sell ? breaker_high>source.high : breaker_low<source.low);
   const bool anchor_sweep=(sell ? source.high>prior_high : source.low<prior_low);
   const double breaker_body=MathAbs(breaker_close-breaker_open);
   const double breaker_wick=(sell ? breaker_close-breaker_low : breaker_high-breaker_close);
   const double anchor_body=MathAbs(source.close-source.open);
   const double anchor_wick=(sell ? source.open-source.low : source.high-source.close);
   const bool breaker_wick_pass=WickPass(breaker_body,breaker_wick);
   const bool anchor_wick_pass=WickPass(anchor_body,anchor_wick);
   const bool ready=breaker_direction && open_side && close_break && (breaker_sweep || anchor_sweep)
                    && breaker_wick_pass && anchor_wick_pass;
   AddDashboardLine(row,"FALLBACK  TWO-CANDLE  [3] -> [2]+[1]  |  "+(sell ? "SELL" : "BUY"),clrGold);
   AddDashboardLine(row,"[x]  Anchor [3] "+(sell ? "bullish" : "bearish")
                    +"    "+CheckBox(breaker_direction)+"  Combined [2]+[1] "+(sell ? "bearish" : "bullish"),
                    (breaker_direction ? clrLimeGreen : clrLightCoral));
   AddDashboardLine(row,CheckBox(open_side)+"  [1] opens on unbroken side"
                    +"    "+CheckBox(close_break)+"  [1] close crosses [3] open",
                    ((open_side && close_break) ? clrLimeGreen : clrLightCoral));
   AddDashboardLine(row,CheckBox(breaker_sweep)+"  Combined takes [3] "+side
                    +"    "+CheckBox(anchor_sweep)+"  [3] takes prior "+(string)Anchor_sweep_lookback+" HTF "+side,
                    ((breaker_sweep || anchor_sweep) ? clrLimeGreen : clrLightCoral));
   AddDashboardLine(row,CheckBox(breaker_wick_pass)+"  Combined wick "+DoubleToString(WickPercent(breaker_body,breaker_wick),1)+"%"
                    +"    "+CheckBox(anchor_wick_pass)+"  [3] wick "+DoubleToString(WickPercent(anchor_body,anchor_wick),1)+"%",
                    ((breaker_wick_pass && anchor_wick_pass) ? clrLimeGreen : clrLightCoral));
   AddCheckLine(row,ready,"TWO-CANDLE RESULT");
}

void UpdateLiveChecks(const MqlRates &source,const MqlRates &mid,const MqlRates &signal,
                      const double source_prior_high,const double source_prior_low,
                      const double mid_prior_high,const double mid_prior_low)
{
   int row=0;
   AddDashboardLine(row,"LIVE CLOSED "+signal_label+"  |  "+TimeToString(signal.time,TIME_DATE|TIME_MINUTES),clrWhite);
   AddFastDashboardChecks(mid,signal,mid_prior_high,mid_prior_low,row);
   AddSlowDashboardChecks(source,mid,signal,source_prior_high,source_prior_low,row);
   for(;row<dashboard_line_count;row++)
      SetDashboardLine(row,"",clrWhite);
}

void ShowDashboardWaiting()
{
   SetDashboardLine(0,"WAITING FOR COMPLETE "+signal_label+" HISTORY",clrGold);
   SetDashboardLine(1,"M90 needs data in all three M30 sections.",clrLightCoral);
   for(int i=2;i<dashboard_line_count;i++)
      SetDashboardLine(i,"",clrWhite);
}

bool ParseBrokerDayStart()
{
   if(StringLen(Broker_day_start_time)!=5 || StringGetCharacter(Broker_day_start_time,2)!=58)
      return false;
   broker_day_hour=(int)StringToInteger(StringSubstr(Broker_day_start_time,0,2));
   broker_day_minute=(int)StringToInteger(StringSubstr(Broker_day_start_time,3,2));
   return broker_day_hour>=0 && broker_day_hour<=23 && broker_day_minute>=0 && broker_day_minute<=59;
}

datetime BrokerDayStart(const datetime time)
{
   MqlDateTime date;
   if(!TimeToStruct(time,date))
      return 0;
   date.hour=broker_day_hour;
   date.min=broker_day_minute;
   date.sec=0;
   datetime start=StructToTime(date);
   if(time<start)
      start-=86400;
   return start;
}

datetime ShiftBrokerDay(const datetime start,const int days)
{
   MqlDateTime date;
   if(!TimeToStruct(start,date))
      return 0;
   date.day+=days;
   return StructToTime(date);
}

void DrawDaySeparators(const datetime current_session)
{
   for(int i=0;i<Day_separator_count;i++)
   {
      const datetime boundary=ShiftBrokerDay(current_session,-i);
      if(boundary==0)
         continue;
      const string name=object_prefix+"VP_Day_"+IntegerToString((long)boundary);
      if(!ObjectCreate(0,name,OBJ_VLINE,0,boundary,0.0))
         continue;
      ObjectSetInteger(0,name,OBJPROP_COLOR,clrDimGray);
      ObjectSetInteger(0,name,OBJPROP_STYLE,STYLE_DOT);
      ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
      ObjectSetInteger(0,name,OBJPROP_BACK,true);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,false);
      ObjectSetString(0,name,OBJPROP_TOOLTIP,"Broker day start "+TimeToString(boundary,TIME_DATE|TIME_MINUTES));
   }
}

void DrawProfileLevel(const string suffix,const datetime start,const datetime end,const double price,
                      const color line_color,const int width)
{
   const string name=object_prefix+"VP_"+IntegerToString((long)start)+"_"+suffix;
   if(ObjectCreate(0,name,OBJ_TREND,0,start,price,end,price))
   {
      ObjectSetInteger(0,name,OBJPROP_COLOR,line_color);
      ObjectSetInteger(0,name,OBJPROP_STYLE,STYLE_SOLID);
      ObjectSetInteger(0,name,OBJPROP_WIDTH,width);
      ObjectSetInteger(0,name,OBJPROP_RAY_LEFT,false);
      ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,false);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetString(0,name,OBJPROP_TOOLTIP,"Previous broker day "+suffix+"  "+DoubleToString(price,_Digits));
   }
   const string label=name+"_Label";
   if(ObjectCreate(0,label,OBJ_TEXT,0,end,price))
   {
      ObjectSetString(0,label,OBJPROP_TEXT," "+suffix+" "+DoubleToString(price,_Digits));
      ObjectSetInteger(0,label,OBJPROP_COLOR,line_color);
      ObjectSetInteger(0,label,OBJPROP_ANCHOR,ANCHOR_LEFT);
      ObjectSetInteger(0,label,OBJPROP_FONTSIZE,8);
      ObjectSetInteger(0,label,OBJPROP_SELECTABLE,false);
   }
}

bool DrawPreviousDayVolumeProfile(const datetime current_session)
{
   DrawDaySeparators(current_session);
   datetime profile_end=current_session;
   datetime profile_start=ShiftBrokerDay(profile_end,-1);
   MqlRates bars[];
   bool found=false;
   for(int i=0;i<7;i++)
   {
      if(profile_start==0 || profile_end<=profile_start)
         return false;
      if(CopyRates(_Symbol,PERIOD_M1,profile_start,profile_end-1,bars)>0)
      {
         found=true;
         break;
      }
      profile_end=profile_start;
      profile_start=ShiftBrokerDay(profile_end,-1);
   }
   if(!found)
      return false;

   double low=1.0e100;
   double high=-1.0e100;
   for(int i=0;i<ArraySize(bars);i++)
   {
      low=MathMin(low,bars[i].low);
      high=MathMax(high,bars[i].high);
   }
   double bin_size=(double)Volume_profile_bin_points*_Point;
   if(bin_size<=0.0 || high<low)
      return false;
   int bins=(int)MathFloor((high-low)/bin_size)+1;
   if(bins>500)
   {
      bin_size=MathCeil((high-low)/(500.0*_Point))*_Point;
      bins=(int)MathFloor((high-low)/bin_size)+1;
   }
   if(bins<=0 || bins>500)
      return false;
   double volume[];
   if(ArrayResize(volume,bins)!=bins)
      return false;
   double total=0.0;
   double maximum=0.0;
   int poc=0;
   for(int i=0;i<ArraySize(bars);i++)
   {
      int bin=(int)MathFloor((bars[i].close-low)/bin_size);
      if(bin<0) bin=0;
      if(bin>=bins) bin=bins-1;
      volume[bin]+=(double)bars[i].tick_volume;
      total+=(double)bars[i].tick_volume;
   }
   if(total<=0.0)
      return false;
   for(int i=0;i<bins;i++)
   {
      if(volume[i]>maximum)
      {
         maximum=volume[i];
         poc=i;
      }
   }
   int value_low=poc;
   int value_high=poc;
   double value_volume=volume[poc];
   const double target=total*Value_area_percent/100.0;
   while(value_volume<target)
   {
      const double lower=(value_low>0 ? volume[value_low-1] : -1.0);
      const double upper=(value_high<bins-1 ? volume[value_high+1] : -1.0);
      if(lower<0.0 && upper<0.0)
         break;
      if(upper>lower)
      {
         value_high++;
         value_volume+=upper;
      }
      else
      {
         value_low--;
         value_volume+=lower;
      }
   }
   const datetime profile_width=(profile_end-profile_start)/3;
   for(int i=0;i<bins;i++)
   {
      if(volume[i]<=0.0)
         continue;
      const datetime width=(datetime)MathMax(60.0,(double)profile_width*volume[i]/maximum);
      const string name=object_prefix+"VP_"+IntegerToString((long)profile_start)+"_Bin_"+IntegerToString(i);
      if(!ObjectCreate(0,name,OBJ_RECTANGLE,0,profile_start,low+i*bin_size,
                       profile_start+width,low+(i+1)*bin_size))
         continue;
      ObjectSetInteger(0,name,OBJPROP_COLOR,ColorToARGB(clrSteelBlue,128));
      ObjectSetInteger(0,name,OBJPROP_FILL,true);
      ObjectSetInteger(0,name,OBJPROP_BACK,true);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,false);
   }
   DrawProfileLevel("VAH",profile_start,profile_end,low+(value_high+1)*bin_size,clrDeepSkyBlue,1);
   DrawProfileLevel("POC",profile_start,profile_end,low+(poc+0.5)*bin_size,clrGold,2);
   DrawProfileLevel("VAL",profile_start,profile_end,low+value_low*bin_size,clrDeepSkyBlue,1);
   return true;
}

void UpdatePreviousDayProfile()
{
   const datetime current_session=BrokerDayStart(TimeCurrent());
   if(current_session==0 || current_session==last_profile_session)
      return;
   DrawPreviousDayVolumeProfile(current_session);
   last_profile_session=current_session;
}

void ClearSignalObjectsKeepProfiles()
{
   const string prefix="Luminar_"+_Symbol+"_";
   for(int i=ObjectsTotal(0,0,-1)-1;i>=0;i--)
   {
      const string name=ObjectName(0,i,0,-1);
      if(StringFind(name,prefix)==0 && StringFind(name,"_VP_")<0)
         ObjectDelete(0,name);
   }
}

int OnInit()
{
   if(!ParseBrokerDayStart())
   {
      Print("Broker_day_start_time must use HH:MI broker server time.");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(!MathIsValidNumber(Body_to_wick_ratio) || Body_to_wick_ratio<0.0
      || Body_to_wick_ratio>100.0 || Anchor_sweep_lookback<1
      || !MathIsValidNumber(Value_area_percent) || Value_area_percent<=0.0 || Value_area_percent>100.0
      || Volume_profile_bin_points<1 || Day_separator_count<1)
   {
      Print("Invalid signal or volume-profile inputs.");
      return INIT_PARAMETERS_INCORRECT;
   }
   signal_timeframe=(SIGNAL_TIMEFRAME==TF_M90 ? PERIOD_M1 : (ENUM_TIMEFRAMES)SIGNAL_TIMEFRAME);
   signal_seconds=(SIGNAL_TIMEFRAME==TF_M90 ? 5400 : PeriodSeconds(signal_timeframe));
   if(signal_seconds<=0) return INIT_PARAMETERS_INCORRECT;
   signal_label=(SIGNAL_TIMEFRAME==TF_M90 ? "M90" : EnumToString(signal_timeframe));
   StringReplace(signal_label,"PERIOD_","");
   object_prefix="Luminar_"+_Symbol+"_"+signal_label+"_";
   // Refresh signal/dashboard drawings while retaining completed day profiles.
   ClearSignalObjectsKeepProfiles();
   ObjectsDeleteAll(0,"DhanuFX_"+_Symbol+"_");
   ArrayResize(areas,0);
   last_bar=0;
   next_history_retry=0;
   history_warning_bar=0;
   buy_signal_count=0;
   sell_signal_count=0;
   last_profile_session=0;
   const string panel=object_prefix+"Panel";
   ObjectCreate(0,panel,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,panel,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,panel,OBJPROP_XDISTANCE,8);
   ObjectSetInteger(0,panel,OBJPROP_YDISTANCE,8);
   ObjectSetInteger(0,panel,OBJPROP_XSIZE,350);
   ObjectSetInteger(0,panel,OBJPROP_YSIZE,260);
   ObjectSetInteger(0,panel,OBJPROP_BGCOLOR,ColorToARGB(clrBlack,145));
   ObjectSetInteger(0,panel,OBJPROP_COLOR,clrDimGray);
   ObjectSetInteger(0,panel,OBJPROP_WIDTH,1);
   ObjectSetInteger(0,panel,OBJPROP_BACK,false);
   ObjectSetInteger(0,panel,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,panel,OBJPROP_HIDDEN,false);
   const string legend=object_prefix+"Legend";
   ObjectCreate(0,legend,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,legend,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,legend,OBJPROP_XDISTANCE,20);
   ObjectSetInteger(0,legend,OBJPROP_YDISTANCE,18);
   ObjectSetInteger(0,legend,OBJPROP_COLOR,clrGold);
   ObjectSetInteger(0,legend,OBJPROP_FONTSIZE,11);
   ObjectSetString(0,legend,OBJPROP_TEXT,"LUMINAR-2  |  HTF: "+signal_label);
   const string counter=object_prefix+"Counter";
   ObjectCreate(0,counter,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,counter,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,counter,OBJPROP_XDISTANCE,20);
   ObjectSetInteger(0,counter,OBJPROP_YDISTANCE,40);
   ObjectSetInteger(0,counter,OBJPROP_COLOR,clrWhite);
   ObjectSetInteger(0,counter,OBJPROP_FONTSIZE,9);
   for(int i=0;i<dashboard_line_count;i++)
   {
      const string line=object_prefix+"CheckLine"+(string)i;
      ObjectCreate(0,line,OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,line,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,line,OBJPROP_XDISTANCE,20);
      ObjectSetInteger(0,line,OBJPROP_YDISTANCE,62+i*14);
      ObjectSetInteger(0,line,OBJPROP_COLOR,clrWhite);
      ObjectSetInteger(0,line,OBJPROP_FONTSIZE,8);
      ObjectSetInteger(0,line,OBJPROP_SELECTABLE,false);
   }
   ShowDashboardWaiting();
   UpdateSignalCounter();
   UpdatePreviousDayProfile();
   Print("Luminar-2 visualization ready: ",signal_label,
         ", wick threshold ",DoubleToString(Body_to_wick_ratio,2),"%.");
   return INIT_SUCCEEDED;
}

bool DrawSignal(const EntrySignal signal,const MqlRates &anchor,const MqlRates &mid,const MqlRates &breaker,
                const datetime confirmation,const int anchor_shift,const int breaker_shift)
{
   const string direction=(signal==ENTRY_SELL ? "SELL" : "BUY");
   const string name=object_prefix+direction+"_"+IntegerToString((long)anchor.time);
   SignalGeometry geometry;
   BuildSignalGeometry(anchor,breaker,confirmation,signal_seconds,geometry);
   if(SIGNAL_TIMEFRAME==TF_MN1)
   {
      MqlDateTime date;
      if(!TimeToStruct(confirmation,date)) return false;
      date.mon+=5;
      if(date.mon>12) { date.mon-=12; date.year++; }
      geometry.right=StructToTime(date);
      if(!TimeToStruct(anchor.time,date)) return false;
      date.mon++;
      if(date.mon>12) { date.mon=1; date.year++; }
      geometry.body_right=StructToTime(date);
      if(!TimeToStruct(breaker.time,date)) return false;
      date.mon++;
      if(date.mon>12) { date.mon=1; date.year++; }
      geometry.arrow_time=StructToTime(date)-1;
   }
   const string details=direction+" | "+signal_label
      +" | anchor["+(string)anchor_shift+"] "+TimeToString(anchor.time)
      +" O="+DoubleToString(anchor.open,_Digits)+" C="+DoubleToString(anchor.close,_Digits)
      +" | break candle ["+(string)breaker_shift+"] "+TimeToString(breaker.time)
      +" open="+DoubleToString(breaker.open,_Digits)
      +" close="+DoubleToString(breaker.close,_Digits)
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
   const string sourceBox=name+"_Body2";
   if(!ObjectCreate(0,sourceBox,OBJ_RECTANGLE,0,geometry.left,geometry.top,geometry.body_right,geometry.bottom)) success=false;
   if(!ObjectSetInteger(0,sourceBox,OBJPROP_COLOR,clrGold)) success=false;
   if(!ObjectSetInteger(0,sourceBox,OBJPROP_FILL,false)) success=false;
   if(!ObjectSetInteger(0,sourceBox,OBJPROP_WIDTH,2)) success=false;
   if(!ObjectSetInteger(0,sourceBox,OBJPROP_BACK,false)) success=false;
   if(!ObjectSetInteger(0,sourceBox,OBJPROP_SELECTABLE,false)) success=false;
   if(!ObjectSetString(0,sourceBox,OBJPROP_TOOLTIP,"SOURCE BODY | "+details)) success=false;
   const string label=name+"_BodyLabel";
   if(!ObjectCreate(0,label,OBJ_TEXT,0,geometry.left,geometry.top)) success=false;
   if(!ObjectSetString(0,label,OBJPROP_TEXT,signal_label+" ["+(string)anchor_shift+"]")) success=false;
   if(!ObjectSetInteger(0,label,OBJPROP_ANCHOR,ANCHOR_LEFT_LOWER)) success=false;
   if(!ObjectSetInteger(0,label,OBJPROP_COLOR,clrGold)) success=false;
   if(!ObjectSetInteger(0,label,OBJPROP_FONTSIZE,9)) success=false;
   if(!ObjectSetInteger(0,label,OBJPROP_BACK,false)) success=false;
   if(!ObjectSetInteger(0,label,OBJPROP_SELECTABLE,false)) success=false;
   if(!ObjectSetString(0,label,OBJPROP_TOOLTIP,"SOURCE BODY | "+details)) success=false;
   // Break candle body spans its own interval only, including custom M90.
   const double breaker_top=MathMax(breaker.open,breaker.close);
   const double breaker_bottom=MathMin(breaker.open,breaker.close);
   const string body1=name+"_Body1";
   if(!ObjectCreate(0,body1,OBJ_RECTANGLE,0,breaker.time,breaker_top,
                    geometry.arrow_time+1,breaker_bottom)) success=false;
   if(!ObjectSetInteger(0,body1,OBJPROP_COLOR,clrDeepSkyBlue)) success=false;
   if(!ObjectSetInteger(0,body1,OBJPROP_FILL,false)) success=false;
   if(!ObjectSetInteger(0,body1,OBJPROP_STYLE,STYLE_SOLID)) success=false;
   if(!ObjectSetInteger(0,body1,OBJPROP_WIDTH,2)) success=false;
   if(!ObjectSetInteger(0,body1,OBJPROP_BACK,false)) success=false;
   if(!ObjectSetInteger(0,body1,OBJPROP_SELECTABLE,false)) success=false;
   if(!ObjectSetInteger(0,body1,OBJPROP_HIDDEN,false)) success=false;
   if(!ObjectSetString(0,body1,OBJPROP_TOOLTIP,"BREAK BODY ["+(string)breaker_shift+"] | "+details)) success=false;
   const string label1=name+"_Body1Label";
   if(!ObjectCreate(0,label1,OBJ_TEXT,0,breaker.time,breaker_top)) success=false;
   if(!ObjectSetString(0,label1,OBJPROP_TEXT,signal_label+" ["+(string)breaker_shift+"]")) success=false;
   if(!ObjectSetInteger(0,label1,OBJPROP_ANCHOR,ANCHOR_LEFT_LOWER)) success=false;
   if(!ObjectSetInteger(0,label1,OBJPROP_COLOR,clrDeepSkyBlue)) success=false;
   if(!ObjectSetInteger(0,label1,OBJPROP_FONTSIZE,9)) success=false;
   if(!ObjectSetInteger(0,label1,OBJPROP_BACK,false)) success=false;
   if(!ObjectSetInteger(0,label1,OBJPROP_SELECTABLE,false)) success=false;
   if(!ObjectSetString(0,label1,OBJPROP_TOOLTIP,"BREAK BODY ["+(string)breaker_shift+"] | "+details)) success=false;
   // Two-candle-break variant: also draw the middle HTF candle[2] between the [3] anchor and [1] breaker.
   if(anchor_shift==3)
   {
      const double mid_top=MathMax(mid.open,mid.close);
      const double mid_bottom=MathMin(mid.open,mid.close);
      datetime mid_right=(mid.time+signal_seconds);
      if(SIGNAL_TIMEFRAME==TF_MN1)
      {
         MqlDateTime date;
         if(TimeToStruct(mid.time,date))
         {
            date.mon++;
            if(date.mon>12) { date.mon=1; date.year++; }
            mid_right=StructToTime(date);
         }
      }
      const string bodyMid=name+"_BodyMid";
      if(!ObjectCreate(0,bodyMid,OBJ_RECTANGLE,0,mid.time,mid_top,mid_right,mid_bottom)) success=false;
      if(!ObjectSetInteger(0,bodyMid,OBJPROP_COLOR,clrGold)) success=false;
      if(!ObjectSetInteger(0,bodyMid,OBJPROP_FILL,false)) success=false;
      if(!ObjectSetInteger(0,bodyMid,OBJPROP_STYLE,STYLE_SOLID)) success=false;
      if(!ObjectSetInteger(0,bodyMid,OBJPROP_WIDTH,1)) success=false;
      if(!ObjectSetInteger(0,bodyMid,OBJPROP_BACK,false)) success=false;
      if(!ObjectSetInteger(0,bodyMid,OBJPROP_SELECTABLE,false)) success=false;
      if(!ObjectSetInteger(0,bodyMid,OBJPROP_HIDDEN,false)) success=false;
      if(!ObjectSetString(0,bodyMid,OBJPROP_TOOLTIP,"MIDDLE BODY [2] | "+details)) success=false;
      const string labelMid=name+"_BodyMidLabel";
      if(!ObjectCreate(0,labelMid,OBJ_TEXT,0,mid.time,mid_top)) success=false;
      if(!ObjectSetString(0,labelMid,OBJPROP_TEXT,signal_label+" [2]")) success=false;
      if(!ObjectSetInteger(0,labelMid,OBJPROP_ANCHOR,ANCHOR_LEFT_LOWER)) success=false;
      if(!ObjectSetInteger(0,labelMid,OBJPROP_COLOR,clrGold)) success=false;
      if(!ObjectSetInteger(0,labelMid,OBJPROP_FONTSIZE,8)) success=false;
      if(!ObjectSetInteger(0,labelMid,OBJPROP_BACK,false)) success=false;
      if(!ObjectSetInteger(0,labelMid,OBJPROP_SELECTABLE,false)) success=false;
      if(!ObjectSetString(0,labelMid,OBJPROP_TOOLTIP,"MIDDLE BODY [2] | "+details)) success=false;
   }
   if(!success)
      Print("Signal drawing failed: ",name," error ",GetLastError());
   ChartRedraw(0);
   return success;
}

bool ReadClosedCandles(const SIGNAL_PERIOD timeframe,const datetime current_bar,
                       MqlRates &source,MqlRates &mid,MqlRates &signal)
{
   if(timeframe==TF_M90)
   {
      const int seconds=5400;
      const datetime start=current_bar-(datetime)(3*seconds);
      MqlRates minutes[];
      // Fetch an earlier boundary too, to establish coverage before all candles.
      const int copied=CopyRates(_Symbol,PERIOD_M1,start-(datetime)seconds,(datetime)(current_bar-1),minutes);
      if(copied<=0 || !SeriesInfoInteger(_Symbol,PERIOD_M1,SERIES_SYNCHRONIZED))
         return false;
      if(minutes[0].time>start) return false;
      // MT5 compresses missing chart bars. A partly traded M90 session interval
      // would otherwise draw as a narrowed "M90" body and change its OHLC.
      if(!HasM90Components(minutes,start)
         || !HasM90Components(minutes,current_bar-(datetime)(2*seconds))
         || !HasM90Components(minutes,current_bar-(datetime)seconds))
         return false;
      return AggregateMinutes(minutes,start,current_bar-(datetime)(2*seconds),source)
             && AggregateMinutes(minutes,current_bar-(datetime)(2*seconds),current_bar-(datetime)seconds,mid)
             && AggregateMinutes(minutes,current_bar-(datetime)seconds,current_bar,signal);
   }

   // Static arrays receive oldest data first: [0]=[3], [1]=[2], [2]=[1], [3]=forming.
   MqlRates candles[4];
   if(CopyRates(_Symbol,(ENUM_TIMEFRAMES)timeframe,0,4,candles)!=4)
      return false;
   if(candles[3].time!=current_bar)
      return false;
   source=candles[0];
   mid=candles[1];
   signal=candles[2];
   return true;
}

bool ReadPriorExtremes(const datetime anchor_time,double &prior_high,double &prior_low)
{
   prior_high=1.0e100;
   prior_low=-1.0e100;
   if(SIGNAL_TIMEFRAME==TF_M90)
   {
      const int seconds=5400;
      const datetime first=anchor_time-(datetime)(Anchor_sweep_lookback*seconds);
      MqlRates minutes[];
      const int copied=CopyRates(_Symbol,PERIOD_M1,first,anchor_time-1,minutes);
      if(copied<=0 || minutes[0].time>first || !SeriesInfoInteger(_Symbol,PERIOD_M1,SERIES_SYNCHRONIZED))
         return false;
      double high=-1.0e100;
      double low=1.0e100;
      for(int i=1;i<=Anchor_sweep_lookback;i++)
      {
         const datetime start=anchor_time-(datetime)(i*seconds);
         MqlRates prior;
         if(!HasM90Components(minutes,start) || !AggregateMinutes(minutes,start,start+(datetime)seconds,prior))
            return false;
         high=MathMax(high,prior.high);
         low=MathMin(low,prior.low);
      }
      prior_high=high;
      prior_low=low;
      return true;
   }

   const int shift=iBarShift(_Symbol,signal_timeframe,anchor_time,true);
   if(shift<0)
      return false;
   MqlRates prior[];
   if(CopyRates(_Symbol,signal_timeframe,shift+1,Anchor_sweep_lookback,prior)!=Anchor_sweep_lookback)
      return false;
   prior_high=-1.0e100;
   prior_low=1.0e100;
   for(int i=0;i<ArraySize(prior);i++)
   {
      prior_high=MathMax(prior_high,prior[i].high);
      prior_low=MathMin(prior_low,prior[i].low);
   }
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

   const bool observe_only=(last_bar==0);
   if(observe_only)
      last_bar=current_bar;
   if(!observe_only && now<next_history_retry)
      return;
   MqlRates source,mid,signal;
   if(!ReadClosedCandles(SIGNAL_TIMEFRAME,current_bar,source,mid,signal))
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
   double source_prior_high=1.0e100;
   double source_prior_low=-1.0e100;
   double mid_prior_high=1.0e100;
   double mid_prior_low=-1.0e100;
   ReadPriorExtremes(source.time,source_prior_high,source_prior_low);
   ReadPriorExtremes(mid.time,mid_prior_high,mid_prior_low);
   UpdateLiveChecks(source,mid,signal,source_prior_high,source_prior_low,mid_prior_high,mid_prior_low);
   if(observe_only)
      return;
   int anchor_shift=0;
   const EntrySignal entry=DetectEntry(source,mid,signal,Body_to_wick_ratio,
                                       source_prior_high,source_prior_low,mid_prior_high,mid_prior_low,
                                       anchor_shift);
   if(entry==ENTRY_NONE)
      return;
   if(entry==ENTRY_BUY) buy_signal_count++;
   else sell_signal_count++;
   UpdateSignalCounter();
   MqlRates anchor;
   if(anchor_shift==3) anchor=source;
   else anchor=mid;
   MqlRates breaker;
   breaker=signal;

   Print(entry==ENTRY_SELL ? "SELL" : "BUY"," signal | ",_Symbol," | ",
         signal_label," | confirmed ",TimeToString(current_bar),
         " | anchor[",(string)anchor_shift,"] ",TimeToString(anchor.time),
         " | break candle [1] ",TimeToString(breaker.time));
   const double body=MathAbs(breaker.close-breaker.open);
   const double wick=(entry==ENTRY_SELL ? breaker.close-breaker.low : breaker.high-breaker.close);
   Print("Signal evidence | anchor[",(string)anchor_shift,"] O/H/L/C=",anchor.open,"/",anchor.high,"/",anchor.low,"/",anchor.close,
         " | source[3] O/H/L/C=",source.open,"/",source.high,"/",source.low,"/",source.close,
         " | mid[2] O/H/L/C=",mid.open,"/",mid.high,"/",mid.low,"/",mid.close,
         " | break[1] O/H/L/C=",breaker.open,"/",breaker.high,"/",breaker.low,"/",breaker.close,
         " | directional wick %=",DoubleToString(100.0*wick/(body+wick),4));
   DrawSignal(entry,anchor,mid,breaker,current_bar,anchor_shift,1);
   AddInterestArea(entry,anchor,breaker,current_bar);
}

void AddInterestArea(const EntrySignal signal,const MqlRates &source,
                     const MqlRates &breaker,const datetime confirmation)
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
   area.top=MathMax(source.open,source.close);
   area.bottom=MathMin(source.open,source.close);
   area.stop=(signal==ENTRY_BUY ? MathMin(source.low,breaker.low) : MathMax(source.high,breaker.high));
   area.source_body_percent=ComputeSourceBodyPercent(source);
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
   UpdatePreviousDayProfile();
   ProcessHigherTimeframe();
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick) || tick.bid<=0 || tick.ask<tick.bid) return;
   MaintainAreas(tick);
}

// Keep rectangles after removal/test completion for inspection.
void OnDeinit(const int reason) {}
