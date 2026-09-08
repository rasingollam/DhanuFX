#ifndef DHANU_SYNTHETIC_CANDLE_MQH
#define DHANU_SYNTHETIC_CANDLE_MQH

// Intervals must divide a server day, giving fixed midnight-aligned boundaries.
datetime SyntheticBarStart(const datetime time,const int minutes)
{
   const long seconds=(long)minutes*60;
   return (datetime)((long)time-((long)time%seconds));
}

// A nominal M90 interval must have data in all three M30 components.
// Session breaks/partial history must not masquerade as a full M90 candle.
// Individual no-tick minutes inside a component remain valid.
bool HasM90Components(const MqlRates &minutes[],const datetime start)
{
   bool first=false;
   bool second=false;
   bool third=false;
   for(int i=0;i<ArraySize(minutes);i++)
   {
      const long elapsed=(long)minutes[i].time-(long)start;
      if(elapsed<0 || elapsed>=5400) continue;
      if(elapsed<1800) first=true;
      else if(elapsed<3600) second=true;
      else third=true;
   }
   return first && second && third;
}

// Aggregate available M1 bars inside [start,end). No-tick minutes need not exist.
// An empty interval is never fabricated. Caller must verify history coverage.
bool AggregateMinutes(const MqlRates &minutes[],const datetime start,
                      const datetime end,MqlRates &result)
{
   if(end<=start)
      return false;
   bool found=false;
   for(int i=0;i<ArraySize(minutes);i++)
   {
      const MqlRates bar=minutes[i];
      if(i>0 && bar.time<=minutes[i-1].time)
         return false;
      if(bar.time<start || bar.time>=end)
         continue;
      if(!found)
      {
         result=bar;
         result.time=start;
         found=true;
         continue;
      }
      if(bar.high>result.high) result.high=bar.high;
      if(bar.low<result.low) result.low=bar.low;
      result.close=bar.close;
      result.tick_volume+=bar.tick_volume;
      result.real_volume+=bar.real_volume;
      result.spread=bar.spread;
   }
   return found;
}

#endif
