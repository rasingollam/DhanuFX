#ifndef DHANU_SIGNAL_GEOMETRY_MQH
#define DHANU_SIGNAL_GEOMETRY_MQH

struct SignalGeometry
{
   datetime left;
   datetime right;
   datetime body_right;
   double top;
   double bottom;
   datetime arrow_time;
   double arrow_price;
};

void BuildSignalGeometry(const MqlRates &older,const MqlRates &previous,
                         const datetime confirmation,const int seconds,
                         SignalGeometry &geometry)
{
   geometry.left=older.time;
   geometry.body_right=older.time+(datetime)seconds;
   if(geometry.body_right>previous.time) geometry.body_right=previous.time;
   geometry.right=confirmation+(datetime)(5*seconds);
   geometry.top=(older.open>older.close ? older.open : older.close);
   geometry.bottom=(older.open<older.close ? older.open : older.close);
   // Last instant INSIDE the signal interval, at its exact closing price.
   // This prevents a higher-timeframe close appearing over its first chart bar.
   geometry.arrow_time=previous.time+(datetime)seconds-1;
   if(geometry.arrow_time>=confirmation) geometry.arrow_time=confirmation-1;
   geometry.arrow_price=previous.close;
}

#endif
