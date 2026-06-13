# Converts Vertex42 checkbook register CSVs into Spruce GL Journal Entry import files.
# Output: one CSV per month (Account,Reference,Description,Debit,Credit) + exceptions report.
# Withdrawals: DR category account / CR bank. Deposits: DR bank / CR 10300 Undeposited Funds.
$ErrorActionPreference = 'Stop'
$out = "C:\Users\lmiller.INTEGRIBILT\gl-imports"
$dl  = "C:\Users\lmiller.INTEGRIBILT\Downloads"

# file -> bank GL account
$sources = @(
    @{File="$dl\Checkbook Register 2020 - Register.csv";          Bank='10400'},
    @{File="$dl\2021 Register - Register.csv";                    Bank='10400'},
    @{File="$dl\WesBanco 2023_2024_2025 Register - Register.csv"; Bank='10500'}
)

# valid GL accounts from the copy DB
$validAccts = (sqlcmd -S "localhost\MSSQLSERVER2022" -E -d SpruceDotNet_IntegriBilt -Q "SET NOCOUNT ON; SELECT GLAcct FROM GLAccounts WHERE GLType IS NOT NULL" -W -h -1) | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d{5}$' }
$validSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$validAccts)

function Parse-Money($s) {
    if ([string]::IsNullOrWhiteSpace($s)) { return [decimal]0 }
    $clean = $s -replace '[",$\s]', ''
    if ($clean -eq '' -or $clean -eq '-') { return [decimal]0 }
    [decimal]$clean
}

$allRows = [System.Collections.Generic.List[object]]::new()
$exceptions = [System.Collections.Generic.List[object]]::new()

foreach ($src in $sources) {
    $lines = Import-Csv $src.File -Header (0..11 | ForEach-Object { "c$_" })
    $headerIdx = -1
    # locate the header row (first cell 'Date')
    for ($i=0; $i -lt [Math]::Min(15, $lines.Count); $i++) { if ($lines[$i].c0 -eq 'Date') { $headerIdx = $i; break } }
    if ($headerIdx -lt 0) { throw "No header row in $($src.File)" }
    $hdr = $lines[$headerIdx]
    # column positions vary between files: find Category / Withdrawal / Deposit columns
    $cols = @{}
    foreach ($p in 0..11) {
        $v = ($hdr."c$p" -replace '\s','')
        if ($v -like 'Payee*') { $cols.Payee = $p }
        elseif ($v -eq 'Category') { $cols.Cat = $p }
        elseif ($v -like 'Withdrawal*') { $cols.W = $p }
        elseif ($v -like 'Deposit*') { $cols.D = $p }
        elseif ($v -eq 'Num') { $cols.Num = $p }
    }
    # category may be unlabeled in files where header shows blank; fall back: column after payee(+1) holding 5-digit codes
    if (-not $cols.ContainsKey('Cat')) { $cols.Cat = $cols.Payee + 2 }  # 2020/2021 layout: Payee,,<blank>,Category? adjust below per-row

    for ($i = $headerIdx+1; $i -lt $lines.Count; $i++) {
        $r = $lines[$i]
        $date = $r.c0
        if ([string]::IsNullOrWhiteSpace($date) -and [string]::IsNullOrWhiteSpace($r."c$($cols.Payee)")) { continue }
        $payee = $r."c$($cols.Payee)"
        if ($payee -match '^\[?Balance' -or $payee -match 'Balance as of') { continue }
        # category: scan likely columns for a 5-digit code
        $cat = ''
        foreach ($p in @($cols.Cat, $cols.Payee+1, $cols.Payee+2)) {
            $v = ($r."c$p" -replace '\s','')
            if ($v -match '^\d{5}$') { $cat = $v; break }
        }
        $w = Parse-Money $r."c$($cols.W)"
        $d = Parse-Money $r."c$($cols.D)"
        if ($w -eq 0 -and $d -eq 0) { continue }
        $dt = [datetime]::MinValue
        $parsed = [datetime]::TryParse([string]$date, [System.Globalization.CultureInfo]::GetCultureInfo('en-US'), [System.Globalization.DateTimeStyles]::None, [ref]$dt)
        if (-not $parsed) {
            # carry forward last date if blank
            if ($allRows.Count -gt 0 -and [string]::IsNullOrWhiteSpace($date)) { $dt = $allRows[$allRows.Count-1].Date }
            else { $exceptions.Add([pscustomobject]@{File=(Split-Path $src.File -Leaf); Line=$i+1; Payee=$payee; Issue="bad date '$date'"}); continue }
        }
        $num = $r."c$($cols.Num)"
        $isVoid = $payee -match 'void'
        $row = [pscustomobject]@{
            Date=$dt; YM=$dt.ToString('yyyyMM'); Num=$num; Payee=$payee.Trim(); Cat=$cat
            Withdrawal=$w; Deposit=$d; Bank=$src.Bank; File=(Split-Path $src.File -Leaf); Void=$isVoid
        }
        $allRows.Add($row)
        if ($isVoid) { $exceptions.Add([pscustomobject]@{File=$row.File; Line=$i+1; Payee=$payee; Issue='voided - review'}) }
        elseif ($w -gt 0 -and $cat -eq '') { $exceptions.Add([pscustomobject]@{File=$row.File; Line=$i+1; Payee=$payee; Issue="withdrawal $w uncoded"}) }
        elseif ($cat -ne '' -and -not $validSet.Contains($cat)) { $exceptions.Add([pscustomobject]@{File=$row.File; Line=$i+1; Payee=$payee; Issue="account $cat not in chart"}) }
    }
}

"Parsed rows: $($allRows.Count)   Exceptions: $($exceptions.Count)"
"Date range: $((($allRows | Measure-Object Date -Minimum).Minimum).ToString('yyyy-MM-dd')) -> $((($allRows | Measure-Object Date -Maximum).Maximum).ToString('yyyy-MM-dd'))"
"Months: $(($allRows | Group-Object YM).Count)"
"Total withdrawals: $([Math]::Round(($allRows | Where-Object {-not $_.Void} | Measure-Object Withdrawal -Sum).Sum,2))"
"Total deposits:    $([Math]::Round(($allRows | Where-Object {-not $_.Void} | Measure-Object Deposit -Sum).Sum,2))"
$allRows | Export-Csv "$out\register_normalized.csv" -NoTypeInformation
$exceptions | Export-Csv "$out\register_exceptions.csv" -NoTypeInformation
"Top uncoded payees:"
$allRows | Where-Object { $_.Withdrawal -gt 0 -and $_.Cat -eq '' -and -not $_.Void } | Group-Object Payee | Sort-Object { ($_.Group | Measure-Object Withdrawal -Sum).Sum } -Descending | Select-Object -First 15 | ForEach-Object { "{0,-40} {1,8} rows  {2,12:N2}" -f $_.Name, $_.Count, ($_.Group | Measure-Object Withdrawal -Sum).Sum }
