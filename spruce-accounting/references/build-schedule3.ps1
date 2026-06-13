# KY filing schedule v3 — tax basis = GL 21450 Accrued Sales Tax (authoritative),
# columns laid out as 51A102 form lines. Reallocation rule: each negative month's
# credit spreads proportionally across positive months since the previous negative.
$ErrorActionPreference = 'Stop'
$out = "C:\Users\lmiller.INTEGRIBILT\ky-salestax"

function RunSql($sql) {
    sqlcmd -S "localhost\MSSQLSERVER2022" -E -d SpruceDotNet_IntegriBilt -Q "SET NOCOUNT ON; $sql" -W -s "|"
}

# GL monthly net accrued sales tax (exclude the Notes Payable reclass 2108-503923)
$gl = @{}
RunSql "SELECT FORMAT(h.PostedDate,'yyyyMM'), SUM(d.GLCredAmt - d.GLDebAmt) FROM GLJournalDtl d JOIN GLJournalHdr h ON h.DocIDInternal=d.DocIDInternal WHERE d.GLID=177 AND h.JournalName <> '2108-503923' AND h.PostedDate >= '2020-09-01' GROUP BY FORMAT(h.PostedDate,'yyyyMM')" |
  Where-Object { $_ -match '^\d{6}\|' } | ForEach-Object { $p = $_ -split '\|'; $gl[$p[0]] = [decimal]$p[1] }

# Register columns for receipts/deduction categories
$reg = @{}
RunSql "SELECT YearMonth, SUM(TaxableItem), SUM(NonTaxItem), SUM(ExemptSales) FROM TaxCodeTotals WHERE YearMonth >= '202009' GROUP BY YearMonth" |
  Where-Object { $_ -match '^\d{6}\|' } | ForEach-Object { $p = $_ -split '\|'; $reg[$p[0]] = @([decimal]$p[1],[decimal]$p[2],[decimal]$p[3]) }

$farm = @{}; RunSql "SELECT FORMAT(d.EntryDate,'yyyyMM'), SUM(i.ExemptTotal) FROM InvoicesHdr i JOIN Documents d ON d.DocIDInternal=i.DocIDInternal WHERE i.ExemptTotal<>0 AND d.EntryDate>='2020-09-01' AND (i.TaxExemptNumber IN ('FARM','AFRM','AG ON FILE') OR i.TaxExemptNumber LIKE 'AE%') GROUP BY FORMAT(d.EntryDate,'yyyyMM')" |
  Where-Object { $_ -match '^\d{6}\|' } | ForEach-Object { $p = $_ -split '\|'; $farm[$p[0]] = [decimal]$p[1] }
$usps = @{}; RunSql "SELECT FORMAT(d.EntryDate,'yyyyMM'), SUM(i.ExemptTotal) FROM InvoicesHdr i JOIN Documents d ON d.DocIDInternal=i.DocIDInternal WHERE i.ExemptTotal<>0 AND d.EntryDate>='2020-09-01' AND (i.Account='1000032' OR i.Name LIKE '%POST OFFICE%' OR i.Name LIKE '%USPS%' OR i.TaxExemptNumber IN ('94-1308560','U.S POSTAL SERVICE','US POST OFFICE')) GROUP BY FORMAT(d.EntryDate,'yyyyMM')" |
  Where-Object { $_ -match '^\d{6}\|' } | ForEach-Object { $p = $_ -split '\|'; $usps[$p[0]] = [decimal]$p[1] }
$store = @{}; RunSql "SELECT FORMAT(h.PostingDate,'yyyyMM'), SUM(dt.TaxableAmount), SUM(dt.TaxCharged) FROM QuantityAdjustDtl dt JOIN QuantityAdjustHdr h ON h.DocIDInternal=dt.DocIDInternal WHERE dt.TaxableAmount<>0 AND h.PostingDate>='2020-09-01' GROUP BY FORMAT(h.PostingDate,'yyyyMM')" |
  Where-Object { $_ -match '^\d{6}\|' } | ForEach-Object { $p = $_ -split '\|'; $store[$p[0]] = @([decimal]$p[1],[decimal]$p[2]) }

function V($map,$ym) { if ($map.ContainsKey($ym)) { $map[$ym] } else { [decimal]0 } }

# Month list = union of register months (202009..)
$yms = $reg.Keys | Sort-Object
$months = foreach ($ym in $yms) {
    [pscustomobject]@{ YM = $ym; GLTax = (V $gl $ym); AdjTax = (V $gl $ym); Realloc = [decimal]0 }
}
$months = @($months)

# Backward reallocation of negative months
$windowStart = 0
for ($i = 0; $i -lt $months.Count; $i++) {
    if ($months[$i].GLTax -ge 0) { continue }
    $credit = -$months[$i].GLTax
    $window = @(); for ($j=$windowStart; $j -lt $i; $j++) { if ($months[$j].AdjTax -gt 0) { $window += $months[$j] } }
    if (-not $window) { for ($j=0; $j -lt $i; $j++) { if ($months[$j].AdjTax -gt 0) { $window += $months[$j] } } }
    $posSum = ($window | Measure-Object AdjTax -Sum).Sum
    $applied = if ($posSum) { [Math]::Min([double]$posSum,[double]$credit) } else { 0 }
    if ($applied -gt 0) {
        foreach ($w in $window) { $share = [decimal]$applied * $w.AdjTax / $posSum; $w.Realloc -= $share; $w.AdjTax -= $share }
    }
    $months[$i].Realloc += $applied; $months[$i].AdjTax += $applied
    $windowStart = $i + 1
}

$schedule = foreach ($m in $months) {
    $r = $reg[$m.YM]; $taxable = $r[0]; $nontax = $r[1]; $exempt = $r[2]
    $f = V $farm $m.YM; $u = V $usps $m.YM
    $other = [Math]::Round($exempt - $f - $u, 2)
    $line1 = [Math]::Round($taxable + $nontax + $exempt, 2)
    $line24Target = [Math]::Round($m.AdjTax / 0.06, 2)   # taxable that yields the GL tax at 6%
    $line10 = [Math]::Round([Math]::Max(0, $nontax), 2)
    if ($nontax -lt 0) { $line1 = [Math]::Round($line1 - $nontax, 2) }  # negative nontax: keep Line1 >= components
    $line17b = [Math]::Round($line1 - $f - $u - $other - $line10 - $line24Target, 2)
    $sc = (V $store $m.YM); $scCost = if ($sc -is [array]) { $sc[0] } else { [decimal]0 }
    $scTax  = if ($sc -is [array]) { $sc[1] } else { [decimal]0 }
    [pscustomobject]@{
        YearMonth                  = $m.YM
        L1_TotalReceipts           = $line1
        L3_AgricultureCerts        = $f
        L4_PurchaseExemptionCerts  = $other
        L6_GovernmentUnits         = $u
        L10_NonRetailServiceInstall = $line10
        L17a_OtherDeductDesc       = 'Installed sales billings reversed at contract closeout'
        L17b_OtherDeductAmt        = $line17b
        L20_TotalDeductions        = [Math]::Round($f + $u + $other + $line10 + $line17b, 2)
        L23a_CostOfTPPUsed         = $scCost
        L24_TotalTaxable           = [Math]::Round($line24Target + $scCost, 2)
        L25_SalesUseTax_6pct       = [Math]::Round(($line24Target + $scCost) * 0.06, 2)
        GLTaxOrig                  = [Math]::Round($m.GLTax, 2)
        ReallocApplied             = [Math]::Round($m.Realloc, 2)
    }
}
$schedule | Export-Csv "$out\ky_filing_FORM_v3.csv" -NoTypeInformation
"GL tax total:        $([Math]::Round(($schedule | Measure-Object GLTaxOrig -Sum).Sum,2))"
"Adjusted L25 total:  $([Math]::Round(($schedule | Measure-Object L25_SalesUseTax_6pct -Sum).Sum,2))"
"Negative L17b months: $(($schedule | Where-Object { [decimal]$_.L17b_OtherDeductAmt -lt 0 }).Count)"
"Negative L24 months:  $(($schedule | Where-Object { [decimal]$_.L24_TotalTaxable -lt 0 }).Count)"
$schedule | Select-Object YearMonth, L1_TotalReceipts, L20_TotalDeductions, L24_TotalTaxable, L25_SalesUseTax_6pct, GLTaxOrig | Format-Table -AutoSize | Out-String -Width 160
