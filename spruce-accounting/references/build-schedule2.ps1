# KY Sales Tax schedule from TaxCodeTotals (Spruce tax register)
# Rule: each negative month's credit is spread proportionally across the
# positive months since the previous negative month (the accumulation window).
$ErrorActionPreference = 'Stop'
$out = "C:\Users\lmiller.INTEGRIBILT\ky-salestax"

$q = @"
SET NOCOUNT ON;
SELECT YearMonth, SUM(TaxableItem) AS Taxable, SUM(NonTaxItem) AS NonTax,
       SUM(ExemptSales) AS Exempt, SUM(TaxCharged) AS TaxCharged
FROM TaxCodeTotals WHERE YearMonth >= '202009'
GROUP BY YearMonth ORDER BY YearMonth;
"@
$raw = sqlcmd -S "localhost\MSSQLSERVER2022" -E -d SpruceDotNet_IntegriBilt -Q $q -s "|" -W
$months = $raw | Where-Object { $_ -match '^\d{6}\|' } | ForEach-Object {
    $p = $_ -split '\|'
    [pscustomobject]@{
        YM = $p[0]; Taxable = [decimal]$p[1]; NonTax = [decimal]$p[2]
        Exempt = [decimal]$p[3]; TaxCharged = [decimal]$p[4]
        AdjTax = [decimal]$p[4]; Realloc = [decimal]0
    }
}

# Reallocation
$windowStart = 0
for ($i = 0; $i -lt $months.Count; $i++) {
    if ($months[$i].TaxCharged -ge 0) { continue }
    $credit = -$months[$i].TaxCharged   # positive magnitude
    $window = @()
    for ($j = $windowStart; $j -lt $i; $j++) { if ($months[$j].AdjTax -gt 0) { $window += $months[$j] } }
    if (-not $window) {
        # consecutive negative months (single closeout event spanning a month boundary):
        # fall back to all prior months that still have positive adjusted tax
        for ($j = 0; $j -lt $i; $j++) { if ($months[$j].AdjTax -gt 0) { $window += $months[$j] } }
    }
    $posSum = ($window | Measure-Object AdjTax -Sum).Sum
    if (-not $posSum) { $posSum = 0 }
    $applied = [Math]::Min([double]$posSum, [double]$credit)
    if ($applied -gt 0) {
        foreach ($w in $window) {
            $share = [decimal]$applied * $w.AdjTax / $posSum
            $w.Realloc -= $share
            $w.AdjTax -= $share
        }
    }
    # negative month keeps any unabsorbed remainder
    $months[$i].Realloc += $applied
    $months[$i].AdjTax += $applied
    $windowStart = $i + 1
}

$schedule = $months | ForEach-Object {
    [pscustomobject]@{
        YearMonth   = $_.YM
        GrossLikeReceipts = [Math]::Round($_.Taxable + $_.NonTax + $_.Exempt, 2)
        Exempt      = [Math]::Round($_.Exempt, 2)
        NonTax      = [Math]::Round($_.NonTax, 2)
        TaxableOrig = [Math]::Round($_.Taxable, 2)
        TaxOrig     = [Math]::Round($_.TaxCharged, 2)
        Realloc     = [Math]::Round($_.Realloc, 2)
        TaxAdj      = [Math]::Round($_.AdjTax, 2)
        TaxableAdj  = [Math]::Round($_.AdjTax / 0.06, 2)
    }
}
$schedule | Export-Csv "$out\ky_filing_schedule.csv" -NoTypeInformation

"Control: orig total = $([Math]::Round(($schedule | Measure-Object TaxOrig -Sum).Sum,2))  adj total = $([Math]::Round(($schedule | Measure-Object TaxAdj -Sum).Sum,2))"
"Negative adjusted months: $(($schedule | Where-Object { $_.TaxAdj -lt 0 }).Count)"
$schedule | Format-Table -AutoSize | Out-String -Width 200
