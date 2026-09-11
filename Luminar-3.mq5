//+------------------------------------------------------------------+
//|                                                      Luminar-3.mq5 |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property link      ""
#property version   "1.01"
#property strict

//--- Range 1
input string R1_start         ="09:00";   // Range 1 start (NY HH:MM)
input int    R1_mins          =90;        // Range 1 length (minutes)
input string R1_inside_start  ="09:30";   // Range 1 inside start (NY HH:MM)
input int    R1_inside_mins   =15;        // Range 1 inside length (minutes)
input color  R1_color         =clrDodgerBlue;  // Range 1 box color

//--- Range 2
input string R2_start         ="01:30";   // Range 2 start (NY HH:MM)
input int    R2_mins          =90;        // Range 2 length (minutes)
input string R2_inside_start  ="01:30";   // Range 2 inside start (NY HH:MM)
input int    R2_inside_mins   =15;        // Range 2 inside length (minutes)
input color  R2_color         =clrGold;       // Range 2 box color

//--- Range 3
input string R3_start         ="21:00";   // Range 3 start (NY HH:MM)
input int    R3_mins          =90;        // Range 3 length (minutes)
input string R3_inside_start  ="21:00";   // Range 3 inside start (NY HH:MM)
input int    R3_inside_mins   =15;        // Range 3 inside length (minutes)
input color  R3_color         =clrLime;       // Range 3 box color

//--- Common
input color  Inside_color       =clrPurple;    // Inside range box color
input int    InpBoxOpacity      =115;     // Box opacity (0..255)
input int    InpMinM1Bars       =30;      // Min M1 bars to accept a window
input double Server_GMT_offset  =-999;    // Broker GMT offset hours (-999 = auto)
input bool   Show_Previous_Ranges=true; // Show ranges + volume profiles for previous days (OFF = today only)
input int    Profile_Levels     =20;      // Volume profile price bins
input int    Profile_MaxWidth   =60;      // Volume profile max width (minutes)
input int    Profile_FontSize   =7;       // Volume profile text font size
input color  Profile_TextColor  =clrWhite;  // Volume profile text color
input bool   Show_BuySell_Volume=true;      // Buy/Sell volume + difference below main range
input int    BuySell_FontSize   =9;         // Buy/Sell label font size

string g_prefix;
int    g_r1_h,g_r1_m,g_r1_ih,g_r1_im;
int    g_r2_h,g_r2_m,g_r2_ih,g_r2_im;
int    g_r3_h,g_r3_m,g_r3_ih,g_r3_im;
int    g_server_offset=0;
bool   g_offset_ready=false;
datetime g_last_render=0;
long   g_last_range_key=0;

//+------------------------------------------------------------------+
//| Parse "HH:MM" string into hours/minutes                          |
//+------------------------------------------------------------------+
bool ParseTimeStr(const string s,int &hh,int &mm)
{
   string parts[];
   if(StringSplit(s,':',parts)!=2)
      return false;
   const int h=(int)StringToInteger(parts[0]);
   const int m=(int)StringToInteger(parts[1]);
   if(h<0 || h>23 || m<0 || m>59)
      return false;
   hh=h;
   mm=m;
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
//| YYYYMMDD integer                                                 |
//+------------------------------------------------------------------+
int YMD(const int y,const int m,const int d)
{
   return y*10000+m*100+d;
}

//+------------------------------------------------------------------+
//| US DST: second Sunday March / first Sunday November               |
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
//| Chart time of an arbitrary NY time-of-day on a given NY date     |
//+------------------------------------------------------------------+
datetime NyTimeChart(const int y,const int m,const int d,const int hh,const int mm)
{
   const int off=(IsDaylightSaving(y,m,d) ? 4 : 5);
   const datetime gmt=UtcMidnight(y,m,d)+(datetime)(off*3600)
                     +(datetime)(hh*3600+mm*60);
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
//| Broker GMT offset in seconds                                    |
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
//| Blend fg toward bg by alpha avoiding ARGB byte-order issue       |
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
                     const double price,const color clr,const ENUM_LINE_STYLE style,
                     const string tip)
{
   if(!ObjectCreate(0,name,OBJ_TREND,0,t1,price,t2,price))
      return;
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_STYLE,style);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
   ObjectSetInteger(0,name,OBJPROP_RAY_LEFT,false);
   ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,false);
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,false);
   ObjectSetString(0,name,OBJPROP_TOOLTIP,tip);
}

//+------------------------------------------------------------------+
//| Draw a range box plus its extended high/mid/low dotted lines     |
//+------------------------------------------------------------------+
int DrawRangeObjects(const string box_name,const string line_base,const string label,
                     const color box_color,const color mid_color,
                     const bool solid_hl,
                     const datetime s,const datetime e,const datetime line_end)
{
   MqlRates bars[];
   const int copied=CopyRates(_Symbol,PERIOD_M1,s,e-1,bars);
   const int minutes=(int)((e-s)/60);
   const int want=MathMin(InpMinM1Bars,minutes/2+1);
   if(copied<want)
      return 0;
   double hi=-1.0e100;
   double lo=1.0e100;
   for(int b=0;b<copied;b++)
   {
      hi=MathMax(hi,bars[b].high);
      lo=MathMin(lo,bars[b].low);
   }
   if(hi<=lo)
      return 0;
   int n=0;
   if(ObjectCreate(0,box_name,OBJ_RECTANGLE,0,s,lo,e,hi))
   {
      const long chart_bg=ChartGetInteger(0,CHART_COLOR_BACKGROUND,0);
      const color fill=BlendBoxColor(box_color,chart_bg,InpBoxOpacity);
      ObjectSetInteger(0,box_name,OBJPROP_COLOR,box_color);
      ObjectSetInteger(0,box_name,OBJPROP_BGCOLOR,fill);
      ObjectSetInteger(0,box_name,OBJPROP_FILL,true);
      ObjectSetInteger(0,box_name,OBJPROP_STYLE,STYLE_SOLID);
      ObjectSetInteger(0,box_name,OBJPROP_WIDTH,1);
      ObjectSetInteger(0,box_name,OBJPROP_BACK,false);
      ObjectSetInteger(0,box_name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,box_name,OBJPROP_HIDDEN,false);
      ObjectSetString(0,box_name,OBJPROP_TOOLTIP,
         label+" "+TimeToString(s,TIME_DATE|TIME_MINUTES)+".."+
         TimeToString(e,TIME_DATE|TIME_MINUTES)+" | high "+
         DoubleToString(hi,_Digits)+" low "+DoubleToString(lo,_Digits));
      n++;
   }
   const double mid=(hi+lo)/2.0;
   const string lt=TimeToString(e,TIME_DATE|TIME_MINUTES)+".."+
                   TimeToString(line_end,TIME_DATE|TIME_MINUTES)+" | ";
   DrawDottedLevel(line_base+"_H",e,line_end,hi,box_color,
      (solid_hl?STYLE_SOLID:STYLE_DOT),lt+label+" high "+DoubleToString(hi,_Digits));
   DrawDottedLevel(line_base+"_M",e,line_end,mid,mid_color,STYLE_DOT,
      lt+label+" mid "+DoubleToString(mid,_Digits));
   DrawDottedLevel(line_base+"_L",e,line_end,lo,box_color,
      (solid_hl?STYLE_SOLID:STYLE_DOT),lt+label+" low "+DoubleToString(lo,_Digits));
   return n+3;
}

//+------------------------------------------------------------------+
//| Volume profile histogram extending left of a range               |
//+------------------------------------------------------------------+
void DrawVolumeProfile(const string base,const color rc,
                       const datetime rs,const datetime re)
{
   MqlRates bars[];
   const int copied=CopyRates(_Symbol,PERIOD_M1,rs,re-1,bars);
   const int minutes=(int)((re-rs)/60);
   const int want=MathMin(InpMinM1Bars,minutes/2+1);
   if(copied<want)
      return;
   double lo=1.0e100;
   double hi=-1.0e100;
   for(int b=0;b<copied;b++)
   {
      hi=MathMax(hi,bars[b].high);
      lo=MathMin(lo,bars[b].low);
   }
   if(hi<=lo)
      return;
   const int levels=MathMax(2,Profile_Levels);
   const double step=(hi-lo)/levels;
   double bin_lo[],bin_hi[],vol[];
   ArrayResize(bin_lo,levels);
   ArrayResize(bin_hi,levels);
   ArrayResize(vol,levels);
   ArrayInitialize(vol,0.0);
   for(int k=0;k<levels;k++)
   {
      bin_lo[k]=lo+k*step;
      bin_hi[k]=lo+(k+1)*step;
   }
   for(int b=0;b<copied;b++)
   {
      const double h=bars[b].high;
      const double l=bars[b].low;
      const double span=h-l;
      for(int k=0;k<levels;k++)
      {
         const double ol=MathMin(h,bin_hi[k])-MathMax(l,bin_lo[k]);
         if(ol<=0.0)
            continue;
         vol[k]+=bars[b].tick_volume*(span>0.0?ol/span:1.0);
      }
   }
   double vmax=0.0;
   for(int k=0;k<levels;k++)
      vmax=MathMax(vmax,vol[k]);
   if(vmax<=0.0)
      return;
   const long chart_bg=ChartGetInteger(0,CHART_COLOR_BACKGROUND,0);
   const color fill=BlendBoxColor(rc,chart_bg,InpBoxOpacity);
   const int max_sec=Profile_MaxWidth*60;
   const double pmax=ChartGetDouble(0,CHART_PRICE_MAX,0);
   const double pmin=ChartGetDouble(0,CHART_PRICE_MIN,0);
   const double hpix=(double)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS,0);
   const double bin_px=((hi-lo)>0.0 && pmax>pmin && hpix>0.0)
                       ? step*hpix/(pmax-pmin) : 8.0;
   for(int k=0;k<levels;k++)
   {
      if(vol[k]<=0.0)
         continue;
      const int w=MathMax(1,(int)MathRound((double)max_sec*vol[k]/vmax));
      const datetime t1=rs-(datetime)w;
      const string nm=base+"_VP"+IntegerToString(k);
      if(ObjectCreate(0,nm,OBJ_RECTANGLE,0,t1,bin_lo[k],rs,bin_hi[k]))
      {
         ObjectSetInteger(0,nm,OBJPROP_COLOR,fill);
         ObjectSetInteger(0,nm,OBJPROP_BGCOLOR,fill);
         ObjectSetInteger(0,nm,OBJPROP_FILL,true);
         ObjectSetInteger(0,nm,OBJPROP_STYLE,STYLE_SOLID);
         ObjectSetInteger(0,nm,OBJPROP_WIDTH,1);
         ObjectSetInteger(0,nm,OBJPROP_BACK,false);
         ObjectSetInteger(0,nm,OBJPROP_SELECTABLE,false);
         ObjectSetInteger(0,nm,OBJPROP_HIDDEN,false);
         const string txt=IntegerToString((long)MathRound(vol[k]));
         int fs=Profile_FontSize;
         int fh=(int)MathFloor(bin_px*0.7);
         if(fh>=5)
            fs=MathMin(fs,fh);
         if(fs<4)
            fs=4;
         const double cy=(bin_lo[k]+bin_hi[k])/2.0;
         const string nmT=nm+"_TXT";
         if(ObjectCreate(0,nmT,OBJ_TEXT,0,t1,cy))
         {
            ObjectSetString(0,nmT,OBJPROP_TEXT,txt);
            ObjectSetInteger(0,nmT,OBJPROP_COLOR,Profile_TextColor);
            ObjectSetInteger(0,nmT,OBJPROP_FONTSIZE,fs);
            ObjectSetInteger(0,nmT,OBJPROP_ANCHOR,ANCHOR_RIGHT);
            ObjectSetInteger(0,nmT,OBJPROP_BACK,false);
            ObjectSetInteger(0,nmT,OBJPROP_SELECTABLE,false);
            ObjectSetInteger(0,nmT,OBJPROP_HIDDEN,false);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Buy/Sell volume + difference labels below a main range box       |
//+------------------------------------------------------------------+
int DrawBuySellVolume(const string base,const datetime rs,const datetime re)
{
   MqlRates bars[];
   const int copied=CopyRates(_Symbol,PERIOD_M1,rs,re-1,bars);
   const int minutes=(int)((re-rs)/60);
   const int want=MathMin(InpMinM1Bars,minutes/2+1);
   if(copied<want)
      return 0;
   double buy=0.0;
   double sell=0.0;
   double lo=1.0e100;
   for(int b=0;b<copied;b++)
   {
      lo=MathMin(lo,bars[b].low);
      const double v=bars[b].tick_volume;
      if(bars[b].close>bars[b].open)
         buy+=v;
      else if(bars[b].close<bars[b].open)
         sell+=v;
      else
      {
         buy+=v*0.5;
         sell+=v*0.5;
      }
   }
   if(lo>=1.0e99)
      return 0;
   const double pmin=ChartGetDouble(0,CHART_PRICE_MIN,0);
   const double pmax=ChartGetDouble(0,CHART_PRICE_MAX,0);
   const double hpix=(double)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS,0);
   const double per_px=(pmax>pmin && hpix>0.0) ? (pmax-pmin)/hpix : _Point*20.0;
   const double gap=(double)BuySell_FontSize*per_px*1.35;
   const long bv=(long)MathRound(buy);
   const long sv=(long)MathRound(sell);
   const double diff=buy-sell;
   const string dTxt=(diff>=0?"Diff  +":"Diff  -")+
                     IntegerToString((long)MathRound(MathAbs(diff)));
   struct P { string nm; double price; string txt; color clr; };
   P items[3];
   items[0].nm=base+"_BSB"; items[0].price=lo-gap;
   items[0].txt="Buy  "+IntegerToString(bv); items[0].clr=clrLimeGreen;
   items[1].nm=base+"_BSS"; items[1].price=lo-2.0*gap;
   items[1].txt="Sell "+IntegerToString(sv); items[1].clr=clrTomato;
   items[2].nm=base+"_BSD"; items[2].price=lo-3.0*gap;
   items[2].txt=dTxt; items[2].clr=Profile_TextColor;
   int n=0;
   for(int k=0;k<3;k++)
   {
      if(!ObjectCreate(0,items[k].nm,OBJ_TEXT,0,rs,items[k].price))
         continue;
      ObjectSetString(0,items[k].nm,OBJPROP_TEXT,items[k].txt);
      ObjectSetInteger(0,items[k].nm,OBJPROP_COLOR,items[k].clr);
      ObjectSetInteger(0,items[k].nm,OBJPROP_FONTSIZE,BuySell_FontSize);
      ObjectSetInteger(0,items[k].nm,OBJPROP_ANCHOR,ANCHOR_LEFT);
      ObjectSetInteger(0,items[k].nm,OBJPROP_BACK,false);
      ObjectSetInteger(0,items[k].nm,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,items[k].nm,OBJPROP_HIDDEN,false);
      n++;
   }
   return n;
}

//+------------------------------------------------------------------+
//| Draw one range + its inside range for a given NY date            |
//+------------------------------------------------------------------+
void DrawRangePair(const int cy,const int cm,const int cd,
                   const int rh,const int rm,const int r_mins,
                   const int ih,const int im,const int i_mins,
                   const color rc,
                   const datetime now_server,
                   const datetime vstart,const datetime vend,
                   int &created)
{
   const datetime rs=NyTimeChart(cy,cm,cd,rh,rm);
   const datetime re=rs+(datetime)(r_mins*60);
   const string tag=IntegerToString(rh)+StringFormat("%02d",rm);
   const string ybase=IntegerToString(YMD(cy,cm,cd))+"_"+tag;
   const datetime line_end=rs+(datetime)(4*r_mins*60);

   if(re<=now_server && re>=vstart && rs<vend)
   {
      DrawVolumeProfile(g_prefix+"Y"+ybase,rc,rs,re);
      if(Show_BuySell_Volume)
         created+=DrawBuySellVolume(g_prefix+"Y"+ybase,rs,re);
      created+=DrawRangeObjects(g_prefix+ybase,g_prefix+"Y"+ybase,tag,
                                rc,clrWhite,true,rs,re,line_end);
   }
   const datetime is_=NyTimeChart(cy,cm,cd,ih,im);
   const datetime ie_=is_+(datetime)(i_mins*60);
   if(ie_<=now_server && ie_>=vstart && is_<vend && is_>=rs && ie_<=re)
      created+=DrawRangeObjects(g_prefix+ybase+"_IN",g_prefix+"Y"+ybase+"_IN",tag+"IN",
                                Inside_color,clrOrange,false,is_,ie_,line_end);
}

//+------------------------------------------------------------------+
//| Render all range boxes for all visible NY days                   |
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
   int ty=0,tm=0,td=0;
   NyDateOf(now_server,ty,tm,td);
   const int today_ymd=YMD(ty,tm,td);
   int created=0;
   for(int i=0;i<60;i++)
   {
      MqlDateTime dt;
      TimeToStruct(cursor,dt);
      const int cy=dt.year;
      const int cm=dt.mon;
      const int cd=dt.day;
      const datetime earliest=NyTimeChart(cy,cm,cd,0,0);
      if(earliest>vend+86400)
         break;
      const bool is_today=(YMD(cy,cm,cd)==today_ymd);
      if(!Show_Previous_Ranges && !is_today)
      {
         dt.day+=1;
         cursor=StructToTime(dt);
         continue;
      }
      DrawRangePair(cy,cm,cd,g_r1_h,g_r1_m,R1_mins,g_r1_ih,g_r1_im,R1_inside_mins,
                    R1_color,now_server,vstart,vend,created);
      DrawRangePair(cy,cm,cd,g_r2_h,g_r2_m,R2_mins,g_r2_ih,g_r2_im,R2_inside_mins,
                    R2_color,now_server,vstart,vend,created);
      DrawRangePair(cy,cm,cd,g_r3_h,g_r3_m,R3_mins,g_r3_ih,g_r3_im,R3_inside_mins,
                    R3_color,now_server,vstart,vend,created);
      dt.day+=1;
      cursor=StructToTime(dt);
   }
   if(g_last_range_key!=range_key)
   {
      g_last_range_key=range_key;
      Print("Luminar3 ",TimeToString(vstart,TIME_DATE|TIME_MINUTES),"..",
            TimeToString(vend,TIME_DATE|TIME_MINUTES),
            " | offset ",g_server_offset,"s | objects ",created);
   }
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   g_prefix="Luminar3_"+_Symbol+"_";
   if(!ParseTimeStr(R1_start,g_r1_h,g_r1_m))
   { Print("Invalid R1_start"); return INIT_PARAMETERS_INCORRECT; }
   if(!ParseTimeStr(R1_inside_start,g_r1_ih,g_r1_im))
   { Print("Invalid R1_inside_start"); return INIT_PARAMETERS_INCORRECT; }
   if(!ParseTimeStr(R2_start,g_r2_h,g_r2_m))
   { Print("Invalid R2_start"); return INIT_PARAMETERS_INCORRECT; }
   if(!ParseTimeStr(R2_inside_start,g_r2_ih,g_r2_im))
   { Print("Invalid R2_inside_start"); return INIT_PARAMETERS_INCORRECT; }
   if(!ParseTimeStr(R3_start,g_r3_h,g_r3_m))
   { Print("Invalid R3_start"); return INIT_PARAMETERS_INCORRECT; }
   if(!ParseTimeStr(R3_inside_start,g_r3_ih,g_r3_im))
   { Print("Invalid R3_inside_start"); return INIT_PARAMETERS_INCORRECT; }
   if(R1_mins<1||R1_mins>1440||R2_mins<1||R2_mins>1440||R3_mins<1||R3_mins>1440)
   { Print("Range minutes must be 1..1440"); return INIT_PARAMETERS_INCORRECT; }
   if(R1_inside_mins<1||R1_inside_mins>1440||R2_inside_mins<1||R2_inside_mins>1440||R3_inside_mins<1||R3_inside_mins>1440)
   { Print("Inside minutes must be 1..1440"); return INIT_PARAMETERS_INCORRECT; }
   if(InpMinM1Bars<1)
      return INIT_PARAMETERS_INCORRECT;
   if(Server_GMT_offset!=-999 && (Server_GMT_offset<-12.0 || Server_GMT_offset>14.0))
   { Print("Invalid Server_GMT_offset"); return INIT_PARAMETERS_INCORRECT; }
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
