//+------------------------------------------------------------------+
//|                                                      Luminar-3.mq5 |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property link      ""
#property version   "1.00"
#property strict

input string Range_start_time="09:00";      // First range start (NY time HH:MM)
input int    Range_minutes   =90;           // Range length (minutes)
input color  InpBoxColor        =clrDodgerBlue; // Next-candle box color
input int    InpBoxOpacity      =115;       // Box opacity (0..255)
input int    InpMinM1Bars       =30;        // Min M1 bars to accept a window
input double Server_GMT_offset  =-999;      // Broker GMT offset in hours (e.g. 2, 3, 5.5); -999 = auto via TimeGMT()

string g_prefix;
int    g_hour=9;
int    g_minute=0;
int    g_server_offset=0;
bool   g_offset_ready=false;
datetime g_last_render=0;
long   g_last_range_key=0;

//+------------------------------------------------------------------+
//| Parse "HH:MM" input                                              |
//+------------------------------------------------------------------+
bool ParseSessionTime()
{
   string parts[];
   if(StringSplit(Range_start_time,':',parts)!=2)
      return false;
   int h=(int)StringToInteger(parts[0]);
   int m=(int)StringToInteger(parts[1]);
   if(h<0 || h>23 || m<0 || m>59)
      return false;
   g_hour=h;
   g_minute=m;
   return true;
}

//+------------------------------------------------------------------+
//| UTC midnight for a calendar date                                 |
//+------------------------------------------------------------------+
datetime UtcMidnight(const int y,const int m,const int d)
{
   MqlDateTime dt;
   dt.year=y;
   dt.mon=m;
   dt.day=d;
   dt.hour=0;
   dt.min=0;
   dt.sec=0;
   return StructToTime(dt);
}

//+------------------------------------------------------------------+
//| YYYYMMDD integer for a date                                      |
//+------------------------------------------------------------------+
int YMD(const int y,const int m,const int d)
{
   return y*10000+m*100+d;
}

//+------------------------------------------------------------------+
//| Second Sunday of March / first Sunday of November (US DST)       |
//+------------------------------------------------------------------+
datetime DSTStart(const int year)
{
   const datetime mar1=UtcMidnight(year,3,1);
   MqlDateTime dt;
   TimeToStruct(mar1,dt);
   return mar1+(datetime)(((7-dt.day_of_week)%7)*86400)+(datetime)(7*86400);
}

datetime DSTEnd(const int year)
{
   const datetime nov1=UtcMidnight(year,11,1);
   MqlDateTime dt;
   TimeToStruct(nov1,dt);
   return nov1+(datetime)(((7-dt.day_of_week)%7)*86400);
}

//+------------------------------------------------------------------+
//| US Daylight Saving active for a local NT date?                   |
//+------------------------------------------------------------------+
bool IsDaylightSaving(const int y,const int m,const int d)
{
   const datetime t=UtcMidnight(y,m,d);
   return t>=DSTStart(y) && t<DSTEnd(y);
}

//+------------------------------------------------------------------+
//| NY calendar date of a server/chart time                          |
//+------------------------------------------------------------------+
void NyDateOf(const datetime t,int &y,int &m,int &d)
{
   const datetime gmt=t-g_server_offset;
   const datetime est=gmt-(datetime)(5*3600);
   MqlDateTime dt;
   TimeToStruct(est,dt);
   y=dt.year;
   m=dt.mon;
   d=dt.day;
   const int off=(IsDaylightSaving(y,m,d) ? 4 : 5);
   const datetime local=gmt-(datetime)(off*3600);
   MqlDateTime dt2;
   TimeToStruct(local,dt2);
   if(YMD(dt2.year,dt2.mon,dt2.day)!=YMD(y,m,d))
   {
      y=dt2.year;
      m=dt2.mon;
      d=dt2.day;
   }
}

//+------------------------------------------------------------------+
//| Chart time of NY session start on a given NY date                |
//+------------------------------------------------------------------+
datetime NySessionStartChart(const int y,const int m,const int d)
{
   const int off=(IsDaylightSaving(y,m,d) ? 4 : 5);
   const datetime gmt=UtcMidnight(y,m,d)+(datetime)(off*3600)
                     +(datetime)(g_hour*3600+g_minute*60);
   return gmt+g_server_offset;
}

//+------------------------------------------------------------------+
//| Visible chart time range                                         |
//+------------------------------------------------------------------+
bool GetVisibleRange(datetime &vstart,datetime &vend)
{
   long first_visible=0;
   long width=0;
   if(!ChartGetInteger(0,CHART_FIRST_VISIBLE_BAR,0,first_visible))
      return false;
   if(!ChartGetInteger(0,CHART_WIDTH_IN_BARS,0,width) || width<1)
      width=1000;
   long right_num=first_visible-width+1;
   if(right_num<0)
      right_num=0;
   MqlRates r1[],r2[];
   if(CopyRates(_Symbol,_Period,(int)first_visible,1,r1)!=1)
      return false;
   if(CopyRates(_Symbol,_Period,(int)right_num,1,r2)!=1)
      return false;
   vstart=r1[0].time;
   vend=r2[0].time;
   if(vend<vstart)
   {
      datetime t=vstart;
      vstart=vend;
      vend=t;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Broker GMT offset in seconds (input overrides auto-detect)       |
//+------------------------------------------------------------------+
int ComputeServerOffset()
{
   if(Server_GMT_offset!=-999)
      return (int)MathRound(Server_GMT_offset*3600.0);
   const datetime srv=TimeTradeServer();
   const datetime gmt=TimeGMT();
   if(srv<=0 || gmt<=0)
      return 0;
   return (int)(srv-gmt);
}

//+------------------------------------------------------------------+
//| Blend fg toward bg by alpha (0..255) avoiding ARGB byte-order    |
//+------------------------------------------------------------------+
color BlendBoxColor(const color fg,const long bg,int alpha)
{
   const int a=(alpha<0 ? 0 : (alpha>255 ? 255 : alpha));
   const int inv=255-a;
   const int fr=(int)(fg&0xFF);
   const int fg_=(int)((fg>>8)&0xFF);
   const int fb=(int)((fg>>16)&0xFF);
   const int br=(int)(bg&0xFF);
   const int bg_=(int)((bg>>8)&0xFF);
   const int bb=(int)((bg>>16)&0xFF);
   return (color)((((fr*a+br*inv)/255))|
                  (((fg_*a+bg_*inv)/255)<<8)|
                  (((fb*a+bb*inv)/255)<<16));
}

//+------------------------------------------------------------------+
//| Draw one dotted horizontal level                                 |
//+------------------------------------------------------------------+
void DrawDottedLevel(const string name,const datetime t1,const datetime t2,
                     const double price,const color clr,const string tip)
{
   if(!ObjectCreate(0,name,OBJ_TREND,0,t1,price,t2,price))
      return;
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_STYLE,STYLE_DOT);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
   ObjectSetInteger(0,name,OBJPROP_RAY_LEFT,false);
   ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,false);
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,false);
   ObjectSetString(0,name,OBJPROP_TOOLTIP,tip);
}

//+------------------------------------------------------------------+
//| Render the blue next-candle boxes for all visible NY days        |
//+------------------------------------------------------------------+
void RenderBoxes()
{
   if(!g_offset_ready)
   {
      g_server_offset=ComputeServerOffset();
      g_offset_ready=true;
   }
   if(g_server_offset==0 && !g_offset_ready)
      return;
   datetime vstart=0;
   datetime vend=0;
   if(!GetVisibleRange(vstart,vend))
      return;
   const long range_key=(long)vstart^((long)vend<<32);
   ObjectsDeleteAll(0,g_prefix,0);
   const datetime now_server=TimeTradeServer();
   int y=0,m=0,d=0;
   NyDateOf(vstart,y,m,d);
   datetime cursor=UtcMidnight(y,m,d);
   int created=0;
   string box_log="";
   for(int i=0;i<60;i++)
   {
      MqlDateTime dt;
      TimeToStruct(cursor,dt);
      const int cy=dt.year;
      const int cm=dt.mon;
      const int cd=dt.day;
      const datetime s1=NySessionStartChart(cy,cm,cd);
      if(s1>vend+86400)
         break;
      const datetime e1=s1+(datetime)(Range_minutes*60);
      const datetime e2=e1+(datetime)(Range_minutes*60);
      const datetime e3=e2+(datetime)(Range_minutes*60);
      const datetime e4=e3+(datetime)(Range_minutes*60);
      if(e1<=now_server && e1>=vstart && s1<vend)
      {
         MqlRates bars[];
         const int copied=CopyRates(_Symbol,PERIOD_M1,s1,e1-1,bars);
         if(copied>=InpMinM1Bars)
         {
            double hi=-1.0e100;
            double lo=1.0e100;
            for(int b=0;b<copied;b++)
            {
               hi=MathMax(hi,bars[b].high);
               lo=MathMin(lo,bars[b].low);
            }
            box_log+=StringFormat("  box %s..%s win %s..%s bars %d high %.2f low %.2f\n",
               TimeToString(s1,TIME_DATE|TIME_MINUTES),
               TimeToString(e1,TIME_DATE|TIME_MINUTES),
               TimeToString(s1,TIME_DATE|TIME_MINUTES),
               TimeToString(e1,TIME_DATE|TIME_MINUTES),copied,hi,lo);
            if(hi>lo)
            {
               const string name=g_prefix+IntegerToString(YMD(cy,cm,cd));
               if(ObjectCreate(0,name,OBJ_RECTANGLE,0,s1,lo,e1,hi))
               {
                  const long chart_bg=ChartGetInteger(0,CHART_COLOR_BACKGROUND,0);
                  const color fill=BlendBoxColor(InpBoxColor,chart_bg,InpBoxOpacity);
                  ObjectSetInteger(0,name,OBJPROP_COLOR,InpBoxColor);
                  ObjectSetInteger(0,name,OBJPROP_BGCOLOR,fill);
                  ObjectSetInteger(0,name,OBJPROP_FILL,true);
                  ObjectSetInteger(0,name,OBJPROP_STYLE,STYLE_SOLID);
                  ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
                  ObjectSetInteger(0,name,OBJPROP_BACK,false);
                  ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
                  ObjectSetInteger(0,name,OBJPROP_HIDDEN,false);
                  ObjectSetString(0,name,OBJPROP_TOOLTIP,
                     TimeToString(s1,TIME_DATE|TIME_MINUTES)+".."+
                     TimeToString(e1,TIME_DATE|TIME_MINUTES)+" | range high "+
                     DoubleToString(hi,_Digits)+" low "+DoubleToString(lo,_Digits));
                  created++;
                  const string lbase=g_prefix+"Y"+IntegerToString(YMD(cy,cm,cd));
                  const datetime lstart=e1;
                  const datetime lend=s1+(datetime)(4*Range_minutes*60);
                  const string ltimes=TimeToString(lstart,TIME_DATE|TIME_MINUTES)+".."+
                                      TimeToString(lend,TIME_DATE|TIME_MINUTES)+" | ";
                  DrawDottedLevel(lbase+"_H",lstart,lend,hi,InpBoxColor,
                     ltimes+"box high "+DoubleToString(hi,_Digits));
                  DrawDottedLevel(lbase+"_M",lstart,lend,(hi+lo)/2.0,clrWhite,
                     ltimes+"box mid "+DoubleToString((hi+lo)/2.0,_Digits));
                  DrawDottedLevel(lbase+"_L",lstart,lend,lo,InpBoxColor,
                     ltimes+"box low "+DoubleToString(lo,_Digits));
                  created+=3;
               }
            }
         }
      }
      dt.day+=1;
      cursor=StructToTime(dt);
   }
   if(g_last_range_key!=range_key)
   {
      g_last_range_key=range_key;
      int ty=0,tm=0,td=0;
      NyDateOf(TimeTradeServer(),ty,tm,td);
      Print("Luminar3 range ",TimeToString(vstart,TIME_DATE|TIME_MINUTES),"..",
            TimeToString(vend,TIME_DATE|TIME_MINUTES),
            " | offset ",g_server_offset,"s | today NY start (chart) ",
            TimeToString(NySessionStartChart(ty,tm,td),TIME_DATE|TIME_MINUTES),
            " | boxes ",created);
      if(box_log!="")
      {
         Print(box_log);
      }
   }
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   g_prefix="Luminar3_"+_Symbol+"_";
   if(!ParseSessionTime())
   {
      Print("Invalid Range_start_time input. Expected HH:MM");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(Range_minutes<1 || Range_minutes>1440)
      return INIT_PARAMETERS_INCORRECT;
   if(InpMinM1Bars<1)
      return INIT_PARAMETERS_INCORRECT;
   if(Server_GMT_offset!=-999 && (Server_GMT_offset<-12.0 || Server_GMT_offset>14.0))
   {
      Print("Invalid Server_GMT_offset. Use -999 for auto or realistic hours (-12..14).");
      return INIT_PARAMETERS_INCORRECT;
   }
   RenderBoxes();
   return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0,g_prefix,0);
   ChartRedraw(0);
}
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if(TimeCurrent()-g_last_render>=30)
   {
      g_last_render=TimeCurrent();
      RenderBoxes();
   }
}
//+------------------------------------------------------------------+
//| Chart events                                                     |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   if(id==CHARTEVENT_CHART_CHANGE)
      RenderBoxes();
}
//+------------------------------------------------------------------+