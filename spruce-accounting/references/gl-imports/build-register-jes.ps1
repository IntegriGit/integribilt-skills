# Register -> monthly Spruce GL import files, with dedup vs Spruce-posted checks.
# Withdrawals: DR category / CR bank. Deposits: DR bank / CR 10300. Paychex: DR 21325 clearing.
$ErrorActionPreference = 'Stop'
$out = "C:\Users\lmiller.INTEGRIBILT\gl-imports"

$rules = @(
    @{Match='^Paychex';            Acct='21325'; Desc='Paychex draft -> payroll clearing'},
    @{Match='^HH pmnt|House Hasson'; Acct='21300'; Desc='House Hasson on account'},
    @{Match='^Consolidated';       Acct='21300'; Desc='Consolidated material'},
    @{Match='^Tri ?State';         Acct='21300'; Desc='TriState material'},
    @{Match='Boise|BlueLinx|PrimeSource|Prime Source|Silver Line|Mitek|MiTek|Quaker|Millworks|ECMD|Lumber One|Dons Lumber|Dixie Yard'; Acct='21300'; Desc='Material vendor'},
    @{Match='Levi Framing';        Acct='61700'; Desc='Subcontractor'}
)

# spruce-posted set (rebuild quickly)
$spruce = Get-Content "$out\spruce_bank_credits.txt" | Where-Object { $_ -match '^\d{4}-' } | ForEach-Object {
    $p = $_ -split '\|'
    $chk = if ($p[2] -match 'Check\((\d+)\)' -and $matches[1] -ne '0') { $matches[1] } else { '' }
    [pscustomobject]@{ Date=[datetime]$p[0]; Amt=[decimal]$p[1]; Chk=$chk }
}
$byChk = @{}; $byAmt = @{}
foreach ($s in $spruce) {
    if ($s.Chk) { $byChk["$($s.Chk)|$($s.Amt)"] = $true }
    $k = [string]$s.Amt; if (-not $byAmt.ContainsKey($k)) { $byAmt[$k] = [System.Collections.Generic.List[datetime]]::new() }
    $byAmt[$k].Add($s.Date)
}

$reg = Import-Csv "$out\register_normalized.csv"
$je = [System.Collections.Generic.List[object]]::new()
$hold = [System.Collections.Generic.List[object]]::new()
$dupSkipped = 0

foreach ($r in $reg) {
    if ($r.Void -eq 'True') { continue }
    $d = [datetime]$r.Date
    if ($d.Year -lt 2019 -or $d.Year -gt 2026) { $hold.Add([pscustomobject]@{Reason='bad date'; Row=$r}); continue }
    $ym = $d.ToString('yyyyMM')
    $w = [decimal]$r.Withdrawal; $dep = [decimal]$r.Deposit
    if ($dep -gt 0) {
        $je.Add([pscustomobject]@{ YM=$ym; Account=$r.Bank; Reference="REG-$ym"; Description="Deposit $($d.ToString('MM/dd/yy')) $($r.Payee)".Trim(); Debit=$dep; Credit=0 })
        $je.Add([pscustomobject]@{ YM=$ym; Account='10300'; Reference="REG-$ym"; Description="Deposit clearing $($d.ToString('MM/dd/yy'))"; Debit=0; Credit=$dep })
        continue
    }
    if ($w -le 0) { continue }
    # dedup vs Spruce
    $isDup = $false
    if ($r.Num -and $byChk.ContainsKey("$($r.Num)|$w")) { $isDup = $true }
    elseif ($byAmt.ContainsKey([string]$w)) { foreach ($sd in $byAmt[[string]$w]) { if ([Math]::Abs(($sd - $d).TotalDays) -le 7) { $isDup = $true; break } } }
    if ($isDup) { $dupSkipped++; continue }
    # category: explicit code, else rules, else special Wanda logic, else hold
    $acct = $r.Cat
    if (-not $acct) {
        if ($r.Payee -match 'Wanda|Basham') { $acct = if ($w -ge 15000) { '23300' } else { '61200' } }
        else { foreach ($rule in $rules) { if ($r.Payee -match $rule.Match) { $acct = $rule.Acct; break } } }
    }
    if (-not $acct) { $hold.Add([pscustomobject]@{Reason='uncoded'; Row=$r}); continue }
    $je.Add([pscustomobject]@{ YM=$ym; Account=$acct; Reference="REG-$ym"; Description="Chk $($r.Num) $($r.Payee)".Trim(); Debit=$w; Credit=0 })
    $je.Add([pscustomobject]@{ YM=$ym; Account=$r.Bank; Reference="REG-$ym"; Description="Chk $($r.Num) $($r.Payee)".Trim(); Debit=0; Credit=$w })
}

$je | Group-Object YM | ForEach-Object { $_.Group | Select-Object Account,Reference,Description,Debit,Credit | Export-Csv "$out\register-je-$($_.Name).csv" -NoTypeInformation }
$hold | ForEach-Object { [pscustomobject]@{ Reason=$_.Reason; Date=$_.Row.Date; Num=$_.Row.Num; Payee=$_.Row.Payee; Withdrawal=$_.Row.Withdrawal; Deposit=$_.Row.Deposit; File=$_.Row.File } } | Export-Csv "$out\register-holdlist.csv" -NoTypeInformation

"Monthly import files: $(($je | Group-Object YM).Count)"
"JE lines: $($je.Count)   Dup-skipped: $dupSkipped   Held for review: $($hold.Count)"
"Held value: $([Math]::Round(($hold | ForEach-Object { [decimal]$_.Row.Withdrawal } | Measure-Object -Sum).Sum,2))"
"Imported withdrawals: $([Math]::Round(($je | Where-Object {$_.Credit -gt 0 -and $_.Account -in '10400','10500'} | Measure-Object Credit -Sum).Sum,2))"
"Imported deposits:    $([Math]::Round(($je | Where-Object {$_.Debit -gt 0 -and $_.Account -in '10400','10500'} | Measure-Object Debit -Sum).Sum,2))"
