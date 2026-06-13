# KY Sales Tax catch-up schedule: Sep 2020 - current
# Reallocates install-contract closeout credits back to source months (per account, proportional)
$ErrorActionPreference = 'Stop'
$out = "C:\Users\lmiller.INTEGRIBILT\ky-salestax"

# 1. Pull per-account per-month net sales tax and taxable from invoices
$q = @"
SET NOCOUNT ON;
SELECT i.Account, d.DocYYMM,
       SUM(i.SalesTax) AS SalesTax,
       SUM(i.TaxableTotal) AS Taxable,
       SUM(i.NontaxTotal) AS NonTax,
       SUM(i.ExemptTotal) AS Exempt
FROM InvoicesHdr i JOIN Documents d ON d.DocIDInternal = i.DocIDInternal
GROUP BY i.Account, d.DocYYMM
"@
sqlcmd -S "localhost\MSSQLSERVER2022" -E -d SpruceDotNet_IntegriBilt -Q $q -s "|" -W > "$out\raw_account_month.txt"

$rows = Get-Content "$out\raw_account_month.txt" | Select-Object -Skip 2 | Where-Object { $_ -match '\|' } | ForEach-Object {
    $p = $_ -split '\|'
    [pscustomobject]@{
        Account = $p[0].Trim(); YYMM = $p[1].Trim()
        SalesTax = [decimal]$p[2]; Taxable = [decimal]$p[3]
        NonTax = [decimal]$p[4]; Exempt = [decimal]$p[5]
    }
} | Where-Object { $_.YYMM -match '^\d{4}$' }

# Normalize YYMM -> sortable YYYYMM (Spruce DocYYMM is YYMM, all 20xx)
foreach ($r in $rows) { $r | Add-Member -NotePropertyName YM -NotePropertyValue ('20' + $r.YYMM) }

# 2. Per-account reallocation of negative months
$adjusted = @{}   # key "YM" -> [decimal] adjusted tax delta
$unallocated = [System.Collections.Generic.List[object]]::new()

$byAccount = $rows | Group-Object Account
foreach ($g in $byAccount) {
    $months = $g.Group | Sort-Object YM
    # walk months; when a negative net month found, spread it over prior positive months since last negative
    $windowStart = 0
    for ($i = 0; $i -lt $months.Count; $i++) {
        $m = $months[$i]
        if ($m.SalesTax -ge 0) { continue }
        $credit = [decimal]$m.SalesTax  # negative
        $window = $months[$windowStart..([Math]::Max($windowStart, $i-1))] | Where-Object { $_.SalesTax -gt 0 }
        $posSum = ($window | Measure-Object SalesTax -Sum).Sum
        if ($posSum -gt 0) {
            $applied = [decimal][Math]::Min([double]$posSum, [double](-$credit))
            foreach ($w in $window) {
                $share = [decimal]$applied * $w.SalesTax / $posSum
                if (-not $adjusted.ContainsKey($w.YM)) { $adjusted[$w.YM] = [decimal]0 }
                $adjusted[$w.YM] -= $share
            }
            $leftover = (-$credit) - $applied
            # the negative month itself keeps only the unabsorbed remainder
            if (-not $adjusted.ContainsKey($m.YM)) { $adjusted[$m.YM] = [decimal]0 }
            $adjusted[$m.YM] += (-$credit) - $leftover   # remove absorbed portion of the credit from this month
            if ($leftover -gt 0.005) {
                $unallocated.Add([pscustomobject]@{Account=$g.Name; YM=$m.YM; Leftover=-$leftover})
            }
        } else {
            $unallocated.Add([pscustomobject]@{Account=$g.Name; YM=$m.YM; Leftover=$credit})
        }
        $windowStart = $i + 1
    }
}

# 3. Build monthly schedule: original net tax + reallocation delta
$monthly = $rows | Group-Object YM | ForEach-Object {
    $tax = ($_.Group | Measure-Object SalesTax -Sum).Sum
    $taxable = ($_.Group | Measure-Object Taxable -Sum).Sum
    $nontax = ($_.Group | Measure-Object NonTax -Sum).Sum
    $exempt = ($_.Group | Measure-Object Exempt -Sum).Sum
    $delta = if ($adjusted.ContainsKey($_.Name)) { $adjusted[$_.Name] } else { [decimal]0 }
    [pscustomobject]@{
        YearMonth = $_.Name
        OrigTax = [Math]::Round($tax,2)
        ReallocDelta = [Math]::Round($delta,2)
        AdjTax = [Math]::Round($tax + $delta,2)
        AdjTaxable = [Math]::Round(($tax + $delta)/0.06,2)
        Taxable = [Math]::Round($taxable,2)
        NonTax = [Math]::Round($nontax,2)
        Exempt = [Math]::Round($exempt,2)
    }
} | Sort-Object YearMonth

$monthly | Export-Csv "$out\monthly_schedule_all.csv" -NoTypeInformation
$monthly | Where-Object { $_.YearMonth -ge '202009' } | Export-Csv "$out\monthly_schedule_filing.csv" -NoTypeInformation
$unallocated | Export-Csv "$out\unallocated_credits.csv" -NoTypeInformation

# Control totals
$origSum = ($monthly | Measure-Object OrigTax -Sum).Sum
$adjSum = ($monthly | Measure-Object AdjTax -Sum).Sum
"Original total tax (all months): $origSum"
"Adjusted total tax (all months): $adjSum"
"Difference (should be ~0):       $($adjSum - $origSum)"
"Months still negative after realloc:"
$monthly | Where-Object { $_.AdjTax -lt 0 } | Format-Table YearMonth, OrigTax, ReallocDelta, AdjTax -AutoSize | Out-String
"Unallocated credit rows: $($unallocated.Count)"
