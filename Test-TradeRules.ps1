$ErrorActionPreference='Stop'
$testRoot=$PSScriptRoot
if (-not $testRoot) { $testRoot=(Get-Location).Path }
# Execute the shared MQL decision/calculation bodies through .NET; adapt syntax only.
$source=(Get-Content (Join-Path $testRoot 'EntrySignal.mqh') -Raw)+"`n"+(Get-Content (Join-Path $testRoot 'TradeRules.mqh') -Raw)
$source=$source -replace '(?m)^#.*$',''
$source=$source -replace 'enum EntrySignal','public enum EntrySignal'
$source=$source -replace 'struct InterestArea','public struct InterestArea'
$source=$source -replace 'const (MqlRates|InterestArea) &','$1 '
$source=$source -replace 'const (double|datetime|EntrySignal) ','$1 '
$source=$source -replace 'const (long|int|ulong|uint) ','$1 '
$source=$source -replace 'datetime','long'
$source=$source -replace 'MathFloor\(','System.Math.Floor(' -replace 'MathCeil\(','System.Math.Ceiling(' -replace 'MathAbs\(','System.Math.Abs('
$source=$source -replace '(EntrySignal|double|bool) (DetectEntry|AreaEntryMatches|AreaStopBreached|CalculateTradePrices|ComputeSourceBodyPercent|EntryDistanceR|EntryFilterPass)\(','public static $1 $2('
$source=$source -replace 'double RiskSizedVolume\(','public static double RiskSizedVolume('
$source=$source -replace 'double PercentageRiskBudget\(','public static double PercentageRiskBudget('
$source=$source -replace 'double &(stop|target)','ref double $1'
$source=$source -replace '(?m)^   (EntrySignal|long|double|bool) (\w+);','   public $1 $2;'
$adapter=@'
public class TradeRuleTests {
public struct MqlRates { public long time; public double open, high, low, close; }
const EntrySignal ENTRY_NONE=EntrySignal.ENTRY_NONE;
const EntrySignal ENTRY_BUY=EntrySignal.ENTRY_BUY;
const EntrySignal ENTRY_SELL=EntrySignal.ENTRY_SELL;
'@
Add-Type ($adapter+$source+"`n}")
$script:passed=0
function Check($condition,$message) {
    if (-not $condition) { throw $message }
    $script:passed++
}
function Candle($time,$open,$high,$low,$close) {
    $bar=New-Object 'TradeRuleTests+MqlRates'
    $bar.time=$time; $bar.open=$open; $bar.high=$high; $bar.low=$low; $bar.close=$close
    return $bar
}
$buy=[TradeRuleTests+EntrySignal]::ENTRY_BUY
$sell=[TradeRuleTests+EntrySignal]::ENTRY_SELL
$none=[TradeRuleTests+EntrySignal]::ENTRY_NONE
$area=New-Object 'TradeRuleTests+InterestArea'
$area.direction=$buy; $area.confirmed=10000; $area.available=10001
$area.expires=37000; $area.top=110; $area.bottom=100; $area.stop=90; $area.consumed=$false
$older=Candle 10300 110 112 99 101
$previous=Candle 10600 100 114 98 113
Check ([TradeRuleTests]::DetectEntry($older,$previous,20) -eq $buy) 'LTF buy fixture invalid'
Check ([TradeRuleTests]::AreaEntryMatches($area,$older,$previous,10900,$buy)) 'Valid retest rejected'
Check (-not [TradeRuleTests]::AreaEntryMatches($area,$older,$previous,10900,$sell)) 'Opposite direction allowed'
Check (-not [TradeRuleTests]::AreaEntryMatches($area,$older,$previous,10900,$none)) 'Missing pattern allowed'
Check (-not [TradeRuleTests]::AreaEntryMatches($area,$older,$previous,37000,$buy)) 'Expiry boundary allowed'
Check (-not [TradeRuleTests]::AreaEntryMatches($area,$older,$previous,38000,$buy)) 'Expired area allowed'
$changed=$area; $changed.consumed=$true
Check (-not [TradeRuleTests]::AreaEntryMatches($changed,$older,$previous,10900,$buy)) 'Used area allowed a second entry'
$changed=$area; $changed.available=10700
Check (-not [TradeRuleTests]::AreaEntryMatches($changed,$older,$previous,10900,$buy)) 'Pattern predating area availability allowed'
$early=$older; $early.time=9700
Check (-not [TradeRuleTests]::AreaEntryMatches($area,$early,$previous,10900,$buy)) 'Pattern before HTF confirmation allowed'
$farOlder=Candle 10300 140 145 130 135
$farPrevious=Candle 10600 135 150 129 149
Check (-not [TradeRuleTests]::AreaEntryMatches($area,$farOlder,$farPrevious,10900,$buy)) 'Pattern away from zone allowed'
$touch=$farPrevious; $touch.low=110
Check ([TradeRuleTests]::AreaEntryMatches($area,$farOlder,$touch,10900,$buy)) 'Exact boundary touch rejected'
Check ([TradeRuleTests]::AreaStopBreached($area,90,90.2)) 'Buy stop boundary not invalidated'
Check (-not [TradeRuleTests]::AreaStopBreached($area,90.1,90.3)) 'Buy area invalidated prematurely'
$sellArea=$area; $sellArea.direction=$sell; $sellArea.stop=120
Check ([TradeRuleTests]::AreaStopBreached($sellArea,119.8,120)) 'Sell ask stop boundary not invalidated'
Check (-not [TradeRuleTests]::AreaStopBreached($sellArea,119.7,119.9)) 'Sell area invalidated prematurely'

$stop=0.0; $target=0.0
Check ([TradeRuleTests]::CalculateTradePrices($buy,100,100.2,95,2,0.01,0,[ref]$stop,[ref]$target)) 'Buy price calculation failed'
Check ([Math]::Abs($stop-95) -lt 1e-8 -and [Math]::Abs($target-110.6) -lt 1e-8) 'Buy RR must use ask entry'
Check ([TradeRuleTests]::CalculateTradePrices($sell,100,100.2,105,2,0.01,0,[ref]$stop,[ref]$target)) 'Sell price calculation failed'
Check ([Math]::Abs($stop-105) -lt 1e-8 -and [Math]::Abs($target-90) -lt 1e-8) 'Sell RR must use bid entry'
Check ([TradeRuleTests]::CalculateTradePrices($buy,100,100.2,95.07,3,0.1,0,[ref]$stop,[ref]$target)) 'Buy tick rounding failed'
Check ([Math]::Abs($stop-95) -lt 1e-8 -and $target -ge 115.8-1e-8) 'Buy SL must round outward and TP meet requested RR'
Check ([TradeRuleTests]::CalculateTradePrices($sell,100,100.2,105.03,3,0.1,0,[ref]$stop,[ref]$target)) 'Sell tick rounding failed'
Check ([Math]::Abs($stop-105.1) -lt 1e-8 -and $target -le 84.7+1e-8) 'Sell SL must round outward and TP meet requested RR'
Check (-not [TradeRuleTests]::CalculateTradePrices($buy,100,100.2,100,2,0.01,0,[ref]$stop,[ref]$target)) 'Buy SL at bid accepted'
Check (-not [TradeRuleTests]::CalculateTradePrices($sell,100,100.2,100.2,2,0.01,0,[ref]$stop,[ref]$target)) 'Sell SL at ask accepted'
Check (-not [TradeRuleTests]::CalculateTradePrices($buy,100,100.2,99.9,2,0.01,0.5,[ref]$stop,[ref]$target)) 'Broker stop distance violated'
Check (-not [TradeRuleTests]::CalculateTradePrices($sell,100,100.2,100.3,2,0.01,0.5,[ref]$stop,[ref]$target)) 'Sell broker stop distance violated'
Check (-not [TradeRuleTests]::CalculateTradePrices($buy,100,100.2,95,0,0.01,0,[ref]$stop,[ref]$target)) 'Zero RR accepted'
Check (-not [TradeRuleTests]::CalculateTradePrices($buy,100,100.2,95,2,0,0,[ref]$stop,[ref]$target)) 'Zero tick size accepted'
Check (-not [TradeRuleTests]::CalculateTradePrices($none,100,100.2,95,2,0.01,0,[ref]$stop,[ref]$target)) 'Invalid direction accepted'
Check (-not [TradeRuleTests]::CalculateTradePrices($buy,101,100,95,2,0.01,0,[ref]$stop,[ref]$target)) 'Inverted quote accepted'
foreach ($case in @(
    @(20,100,0.01,100,0.01,0.20),
    @(20,300,0.01,100,0.01,0.06),
    @(20,3000,0.01,100,0.01,0),
    @(20,2000,0.01,100,0.01,0.01),
    @(20,10,0.01,1,0.01,1),
    @(20,30,0.25,100,0.25,0.5),
    @(20,100,0.1,100,0.1,0.2),
    @(0,100,0.01,100,0.01,0),
    @(20,0,0.01,100,0.01,0),
    @(20,100,0.01,100,0,0),
    @(20,100,0.1,0.01,0.01,0)
)) {
    $volume=[TradeRuleTests]::RiskSizedVolume($case[0],$case[1],$case[2],$case[3],$case[4])
    Check ([Math]::Abs($volume-$case[5]) -lt 1e-8) "Incorrect risk-sized volume: $case -> $volume"
}
foreach ($case in @(
    @(2000,1,20), @(1500,1,15), @(2500,1,25), @(10000,0.5,50),
    @(0,1,0), @(-100,1,0), @(2000,0,0), @(2000,101,0), @(2000,100,2000)
)) {
    $budget=[TradeRuleTests]::PercentageRiskBudget($case[0],$case[1])
    Check ([Math]::Abs($budget-$case[2]) -lt 1e-8) "Percentage budget failed: $case"
}
$equityBudget=[TradeRuleTests]::PercentageRiskBudget(2000,1)
Check ([Math]::Abs([TradeRuleTests]::RiskSizedVolume($equityBudget,300,0.01,100,0.01)-0.06) -lt 1e-8) 'Percentage budget not integrated with rounded volume'

$sBody=Candle 10300 100 112 99 110
Check ([Math]::Abs([TradeRuleTests]::ComputeSourceBodyPercent($sBody)-76.9230769230769) -lt 1e-6) 'Source body percent wrong'
$flat=Candle 10300 100 100 100 100
Check ([TradeRuleTests]::ComputeSourceBodyPercent($flat) -eq 0) 'Flat-range source body percent nonzero'
$zone=$area; $zone.source_body_percent=25
Check ([TradeRuleTests]::EntryDistanceR($zone,105,10) -eq 0) 'In-zone entry has nonzero chase R'
Check ([Math]::Abs([TradeRuleTests]::EntryDistanceR($zone,115,10)-0.5) -lt 1e-9) 'Above-zone chase R wrong'
Check ([Math]::Abs([TradeRuleTests]::EntryDistanceR($zone,90,10)-1) -lt 1e-9) 'Below-zone chase R wrong'
Check ([TradeRuleTests]::EntryDistanceR($zone,90,0) -eq 0) 'Zero stop-distance chase R must be zero'
Check ([TradeRuleTests]::EntryFilterPass($zone,0.5,20,1,20000,0)) 'Valid entry wrongly rejected by filters'
Check (-not [TradeRuleTests]::EntryFilterPass($zone,0.5,30,1,20000,0)) 'Low source body allowed by filter'
Check (-not [TradeRuleTests]::EntryFilterPass($zone,0.6,0,0.25,20000,0)) 'High chase R allowed by filter'
Check (-not [TradeRuleTests]::EntryFilterPass($zone,0.1,0,1,10199,90)) 'Young zone allowed by age filter'
Check ([TradeRuleTests]::EntryFilterPass($zone,0.1,0,1,15400,90)) 'Mature 90-min zone rejected by age filter'
Check ([TradeRuleTests]::EntryFilterPass($zone,0.1,0,1,19999,90)) 'Older zone rejected by age filter'
Write-Output "PASS: $script:passed shared trade-rule checks. This does not execute broker orders or test MT5 runtime."
