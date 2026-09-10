#ifndef DHANU_ENTRY_SIGNAL_MQH
#define DHANU_ENTRY_SIGNAL_MQH

// Pure closed-candle logic, shared by the EA and deterministic tests.
enum EntrySignal { ENTRY_NONE=0, ENTRY_BUY=1, ENTRY_SELL=-1 };

EntrySignal DetectEntry(const MqlRates &source,const MqlRates &mid,const MqlRates &signal,
                        const double max_wick_percent,int &anchor_shift)
{
   anchor_shift=0;
   if(max_wick_percent<0.0 || max_wick_percent>100.0)
      return ENTRY_NONE;

   // One-candle break: candle[2] (mid) is the source, candle[1] (signal) breaks it.
   if(mid.close>mid.open)
   {
      const double sbody=mid.close-mid.open;
      const double swing=mid.open-mid.low;
      if(swing>=0.0 && 100.0*swing<max_wick_percent*(sbody+swing)
         && signal.close<signal.open)
      {
         const double body=signal.open-signal.close;
         const double wick=signal.close-signal.low;
         if(wick>=0.0 && signal.close<mid.open && signal.high>mid.high
            && 100.0*wick<max_wick_percent*(body+wick))
         {
            anchor_shift=2;
            return ENTRY_SELL;
         }
      }
   }
   else if(mid.close<mid.open)
   {
      const double sbody=mid.open-mid.close;
      const double swing=mid.high-mid.close;
      if(swing>=0.0 && 100.0*swing<max_wick_percent*(sbody+swing)
         && signal.close>signal.open)
      {
         const double body=signal.close-signal.open;
         const double wick=signal.high-signal.close;
         if(wick>=0.0 && signal.close>mid.open && signal.low<mid.low
            && 100.0*wick<max_wick_percent*(body+wick))
         {
            anchor_shift=2;
            return ENTRY_BUY;
         }
      }
   }

   // Two-candle break: candle[3] (source) is the anchor; candle[2]+candle[1] break it.
   if(source.close>source.open)
   {
      const double sbody=source.close-source.open;
      const double swing=source.open-source.low;
      if(swing>=0.0 && 100.0*swing<max_wick_percent*(sbody+swing)
         && signal.close<signal.open)
      {
         const double body=signal.open-signal.close;
         const double wick=signal.close-signal.low;
         const double spike=MathMax(signal.high,mid.high);
         if(wick>=0.0 && signal.close<source.open && spike>source.high
            && 100.0*wick<max_wick_percent*(body+wick))
         {
            anchor_shift=3;
            return ENTRY_SELL;
         }
      }
   }
   else if(source.close<source.open)
   {
      const double sbody=source.open-source.close;
      const double swing=source.high-source.close;
      if(swing>=0.0 && 100.0*swing<max_wick_percent*(sbody+swing)
         && signal.close>signal.open)
      {
         const double body=signal.close-signal.open;
         const double wick=signal.high-signal.close;
         const double spike=MathMin(signal.low,mid.low);
         if(wick>=0.0 && signal.close>source.open && spike<source.low
            && 100.0*wick<max_wick_percent*(body+wick))
         {
            anchor_shift=3;
            return ENTRY_BUY;
         }
      }
   }
   return ENTRY_NONE;
}

#endif
