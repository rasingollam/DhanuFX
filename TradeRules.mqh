#ifndef DHANU_TRADE_RULES_MQH
#define DHANU_TRADE_RULES_MQH

#include "EntrySignal.mqh"

struct InterestArea
{
   EntrySignal direction;
   datetime confirmed;
   datetime available;
   datetime expires;
   double top;
   double bottom;
   double stop;
   bool consumed;
};

bool AreaEntryMatches(const InterestArea &area,const MqlRates &older,
                      const MqlRates &previous,const datetime now,
                      const EntrySignal signal)
{
   if(area.consumed || signal==ENTRY_NONE || signal!=area.direction
      || now>=area.expires || older.time<area.confirmed
      || previous.time<area.available)
      return false;
   // The two-candle rejection must actually revisit the HTF body zone.
   return (older.low<=area.top && older.high>=area.bottom)
          || (previous.low<=area.top && previous.high>=area.bottom);
}

bool AreaStopBreached(const InterestArea &area,const double bid,const double ask)
{
   return area.direction==ENTRY_BUY ? bid<=area.stop : ask>=area.stop;
}

double RiskSizedVolume(const double risk,const double loss_per_lot,const double minimum,
                       const double maximum,const double step)
{
   if(risk<=0 || loss_per_lot<=0 || minimum<=0 || maximum<minimum || step<=0)
      return 0;
   double limit=risk/loss_per_lot;
   if(limit>maximum) limit=maximum;
   double volume=MathFloor(limit/step+1e-10)*step;
   if(volume*loss_per_lot>risk+1e-8) volume-=step;
   if(volume<minimum-1e-10 || volume<=0) return 0;
   return volume;
}

bool CalculateTradePrices(const EntrySignal direction,const double bid,const double ask,
                          const double raw_stop,const double rr,const double tick_size,
                          const double minimum_distance,double &stop,double &target)
{
   if(rr<=0 || tick_size<=0 || bid<=0 || ask<bid || minimum_distance<0)
      return false;
   if(direction==ENTRY_BUY)
   {
      stop=MathFloor(raw_stop/tick_size+1e-8)*tick_size;
      if(stop>=bid || bid-stop<minimum_distance) return false;
      target=MathCeil((ask+rr*(ask-stop))/tick_size-1e-8)*tick_size;
      return target>ask && target-bid>=minimum_distance;
   }
   if(direction==ENTRY_SELL)
   {
      stop=MathCeil(raw_stop/tick_size-1e-8)*tick_size;
      if(stop<=ask || stop-ask<minimum_distance) return false;
      target=MathFloor((bid-rr*(stop-bid))/tick_size+1e-8)*tick_size;
      return target>0 && target<bid && ask-target>=minimum_distance;
   }
   return false;
}

#endif
