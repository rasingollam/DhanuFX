#ifndef DHANU_ENTRY_SIGNAL_MQH
#define DHANU_ENTRY_SIGNAL_MQH

// Pure closed-candle logic, shared by the EA and deterministic tests.
enum EntrySignal { ENTRY_NONE=0, ENTRY_BUY=1, ENTRY_SELL=-1 };

EntrySignal DetectEntry(const MqlRates &older,const MqlRates &previous,
                        const double max_wick_percent)
{
   if(max_wick_percent<0.0 || max_wick_percent>100.0)
      return ENTRY_NONE;

   if(older.close>older.open && previous.close<previous.open)
   {
      const double body=previous.open-previous.close;
      const double wick=previous.close-previous.low;
      if(wick>=0.0 && previous.close<older.open && previous.high>older.high
         && 100.0*wick<max_wick_percent*(body+wick))
         return ENTRY_SELL;
   }
   else if(older.close<older.open && previous.close>previous.open)
   {
      const double body=previous.close-previous.open;
      const double wick=previous.high-previous.close;
      if(wick>=0.0 && previous.close>older.open && previous.low<older.low
         && 100.0*wick<max_wick_percent*(body+wick))
         return ENTRY_BUY;
   }
   return ENTRY_NONE;
}

#endif
