## Inputs
- Timeframe = 30min
- Body_to_wick_ratio = 20

Ea should run on every candle open only.

## Sell Signal
If candle[2] == bullish && candle[1](previous candle) bearish, then check

    1. candle[1] close < candle[2] open
    2. candle[1] High > candle[2] high
    3. candle[1] wick to the downside / (candle[1] body + candle[1] downside wick) < Body_to_wick_ratio

    IF 1 && 2 && 3
        Sell Signal triggered

## Buy signal
Wise versa

## Ontick

If Sell:
    Draw a dark red rectangle on candle[2] close in left upper corner, candle[2] open in left bottom corner and for the consecutive 5 candle to future the right corners.

If Buy:
    Draw a dark Green rectangle on candle[2] open in left upper corner, candle[2] close in left bottom corner and for the consecutive 5 candle to future the right corners.

mt5 terminal direcory :  D:\Trading\terminal64