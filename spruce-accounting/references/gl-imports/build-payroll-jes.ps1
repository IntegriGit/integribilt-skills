# Builds monthly payroll JE drafts from the Paychex TCOW export (2022-07..2025-01).
# Wages split across labor accounts using Labor Cost position proportions.
# DR wage accounts + employer tax expense, CR 21325 payroll clearing (offsets Paychex bank drafts).
$ErrorActionPreference = 'Stop'
$out = "C:\Users\lmiller.INTEGRIBILT\gl-imports"
$export = "\\OFC01\Users\lmiller.INTEGRIBILT\Downloads\Export-report-2026-6-9_20-43.csv"
$laborCost = "\\OFC01\Users\lmiller.INTEGRIBILT\Downloads\20014055_Payroll_Labor_Cost_Tuesday_Jun_09_20_21_10_EDT_2026.csv"
$mapFile = "$out\position-gl-map.csv"

# --- wage split proportions from Labor Cost by position (col2 = wages) ---
$map = @{}; Import-Csv $mapFile | ForEach-Object { $map[$_.Position] = $_.GLAcct }
$lc = Import-Csv $laborCost -Header Company,Position,Wages,C3,C4,C5,TotComp,C7,Taxes,Total
$split = @{}
foreach ($r in $lc) {
    if ([string]::IsNullOrWhiteSpace($r.Position)) { continue }
    $acct = $map[$r.Position]; if (-not $acct) { $acct = '61650' }
    $w = [decimal]($r.Wages -replace ',','')
    if (-not $split.ContainsKey($acct)) { $split[$acct] = [decimal]0 }
    $split[$acct] += $w
}
$wageTotal = ($split.Values | Measure-Object -Sum).Sum
"Wage split proportions:"
$split.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object { "  {0}  {1,6:P2}" -f $_.Key, ($_.Value/$wageTotal) }

# --- parse TCOW export ---
$rows = Import-Csv $export -Header (0..11 | ForEach-Object {"c$_"}) | Select-Object -Skip 3
$wageTypes = @('Direct-BasePay','Supplemental-Overtime','Benefits-PayForTimeNotWorked','Supplemental-Other','Direct-LongTermIncentive')
$byMonth = $rows | Where-Object { $_.c0 -match '^\d{4}-\d{2}' } | Group-Object { $_.c0.Substring(0,7) }

$jeLines = [System.Collections.Generic.List[object]]::new()
$summary = [System.Collections.Generic.List[object]]::new()
foreach ($m in ($byMonth | Sort-Object Name)) {
    $wages = ($m.Group | Where-Object { $wageTypes -contains $_.c11 } | ForEach-Object { [decimal]$_.c8 } | Measure-Object -Sum).Sum
    $tax   = ($m.Group | Where-Object { $_.c11 -eq 'Actual Employer Tax Expenses' } | ForEach-Object { [decimal]$_.c8 } | Measure-Object -Sum).Sum
    if (-not $wages) { $wages = 0 }; if (-not $tax) { $tax = 0 }
    if ($wages -eq 0 -and $tax -eq 0) { continue }
    $ym = $m.Name -replace '-',''
    $totalDr = [decimal]0
    foreach ($kv in ($split.GetEnumerator() | Sort-Object Key)) {
        $amt = [Math]::Round($wages * $kv.Value / $wageTotal, 2)
        if ($amt -eq 0) { continue }
        $totalDr += $amt
        $jeLines.Add([pscustomobject]@{ YM=$ym; Account=$kv.Key; Reference="PAYROLL-$ym"; Description="Wages $($m.Name) (Paychex)"; Debit=$amt; Credit=0 })
    }
    $rounding = [Math]::Round($wages - $totalDr, 2)
    if ($rounding -ne 0) { $jeLines.Add([pscustomobject]@{ YM=$ym; Account='61650'; Reference="PAYROLL-$ym"; Description="Wage rounding"; Debit=$rounding; Credit=0 }) }
    $taxAmt = [Math]::Round($tax,2)
    if ($taxAmt -ne 0) { $jeLines.Add([pscustomobject]@{ YM=$ym; Account='62100'; Reference="PAYROLL-$ym"; Description="Employer payroll taxes $($m.Name)"; Debit=$taxAmt; Credit=0 }) }
    $cr = [Math]::Round($wages + $taxAmt, 2)
    $jeLines.Add([pscustomobject]@{ YM=$ym; Account='21325'; Reference="PAYROLL-$ym"; Description="Payroll clearing $($m.Name)"; Debit=0; Credit=$cr })
    $summary.Add([pscustomobject]@{ Month=$m.Name; Wages=[Math]::Round($wages,2); EmployerTax=$taxAmt; TotalJE=$cr })
}

# one import CSV per month (wizard format)
$jeLines | Group-Object YM | ForEach-Object {
    $_.Group | Select-Object Account,Reference,Description,Debit,Credit | Export-Csv "$out\payroll-je-$($_.Name).csv" -NoTypeInformation
}
$summary | Export-Csv "$out\payroll-summary.csv" -NoTypeInformation
"Months generated: $(($jeLines | Group-Object YM).Count)"
"Total wages: $([Math]::Round(($summary | Measure-Object Wages -Sum).Sum,2))   Total empl tax: $([Math]::Round(($summary | Measure-Object EmployerTax -Sum).Sum,2))"
$summary | Format-Table -AutoSize | Out-String
