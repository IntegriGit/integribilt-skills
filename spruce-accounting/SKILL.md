---
name: spruce-accounting
description: IntegriBilt's Spruce ERP accounting operations - database queries, GL mappings, KY sales tax filing, A/R workout, manufacturing cost fixes, and driving the hosted Spruce UI via RemoteApp. Use for any tax, GL, A/R, inventory-costing, or Spruce-configuration work at IntegriBilt.
---

# Spruce Accounting Operations (IntegriBilt)

## Environment
- **Live Spruce**: ECI-hosted (CONNFARM-C5.CLOUD5.ECIHOSTING.COM), reached via RemoteApp "IntegriBilt (Work Resources)". Launch: `Start-Process mstsc "<%APPDATA%\Microsoft\Workspaces\{GUID}\Resource\IntegriBilt (Work Resources).rdp>"`. Spruce app login is the user's. ALL config/data changes go through this UI.
- **Local copy DB** (analysis only, read-only): `sqlcmd -S "localhost\MSSQLSERVER2022" -E -d SpruceDotNet_IntegriBilt` on SVR12. Refreshed periodically — check `SELECT MAX(EntryDate) FROM Documents` for freshness. NEVER write SQL to it expecting live effect; never write SQL to live at all.

## Driving the Spruce UI (v31)
- Spruce logo (top-left) = Main Menu: Point of Sale / Purchasing / Inventory / Manufacturing / Receivables / Payables / General Ledger / Delivery / Maintenance.
- Function keys: F6 Save (adds to batch), **F12 Process (COMMITS — wait for "Database Updated" / "System Journal Saved")**, F9 Cancel (ROLLS BACK the batch incl. F6-saved rows), F10 Exit, F2 Import.
- Grid cell editing: **single-click the cell, then type over, then Return** (most reliable). Avoid ctrl+A (selects whole grid). If garbage gets in, the M300 "No matching selections" dialog reverts the cell on OK.
- Account fields auto-fill the account description after Tab — use it to verify (screen font renders 6/8 ambiguously).

## Key configuration (fixed 2026-06-09, audit trail in C:\Users\lmiller.INTEGRIBILT\ky-salestax\system_journal_audit.txt)
GL → Database → **System Journals** is the MASTER mapping (overrides front-end adjustment codes):
- Inventory #17 Manufacturing/Adjustments → 61660 Truss Labor (was 61650 Payroll-Dept#1; $1.18M had misposted since 2020)
- Inventory #14 Use Sales Tax Expense → 64600 (was 63800 Office Supplies)
- POS #74 Installed Sales Income → 41500 Installed Sales (was 41200 Charge Sales — blended exempt field labor into taxable retail = audit risk)
- POS #73 Real Property Tax → 64610; POS #82 AR Convenience Fee → 71300
- ACH/EFT rows are NULL and hidden until ACH is enabled — must be mapped (10300) when it is.
- GL → Database → Detail Mapping: Manufacturing Costs MapID 32 "Shop Labor - Truss" → 61660, linked from POS → Database → Adjustment Codes → SHOP LABOR. DESIGN TIME / MEASURE codes still unmapped (fall to system default 61660; candidate 61683 Design Labor).
- 81500 "Spruce Mapping" is the junk/fallback account — anything posting there is a mapping gap.

## KY sales tax catch-up (form 51A102)
- **Authoritative tax basis = GL account 21450 Accrued Sales Tax (GLID 177)** — NOT TaxCodeTotals.TaxCharged, which double-counts (~2x GL). Total owed Sep 2020–Jun 2026: **$962,224**; NOTHING ever remitted. $225,343 was reclassed to Notes Payable 23502 (journal 2108-503923, Aug 2021) — a reclass, not a payment; reverse it.
- Install contract closeouts create big negative-tax months; reallocate credits backward proportionally over the accumulation window (reduces late-filing P&I). Consecutive negative months = one closeout event.
- Filing schedule with form-line columns: `C:\Users\lmiller.INTEGRIBILT\ky-salestax\ky_filing_FORM_v3.csv` (+ build-schedule3.ps1 regenerates). Farm exempt = TaxExemptNumber in (FARM, AFRM, AG ON FILE) or LIKE 'AE%' → Line 3. USPS/gov → Line 6. Non-taxable labor → Line 10. Store use (taxable-flagged QuantityAdjustDtl) → Line 23a; tracking died mid-2023. Bad-debt write-offs → Line 12.
- Strongly consider KY voluntary disclosure (penalty waiver) before portal entry. CPA review of reallocation method required.

## A/R structure
- CustomerMaster is authoritative for balances (OutstandingBalance/CreditBalance); CustomerJob.CreditBalance per job is live too; CustomerJobTotals & ARPostingDtl are activity/session tables — do NOT sum as balances.
- True picture (Jun 2026): ~$462k collectible (accounts w/o credits: Fox KHI 96k, Tim Lowman 51k, KHI 49k, Jimmy Jenkins 49k, Vista 45k...) + ~$445k customer prepayments on UNCLOSED install contracts (Century acct 1000067 = $279k net across 8 lot jobs). Closing the install contracts final-bills and absorbs the credits. Punch list: ky-salestax\ar_punchlist_accounts.csv.
- Open invoices at doc level: InvoicesHdr.ChargeAmount - ARPaid joined to Documents.

## Manufacturing/inventory costing (open issue)
- Panel-shop/manufactured items carry per-MBF costs against each-quantities → avg costs 100-1000x reality (BBIRCH2030 $147,917/sheet; studs $500-900/ea; F04WYE -10 on hand @ $10M). InventoryStore.AverageCost vs LastReceiptCost flags them. Fix = correct UM conversions + one revaluation; pollutes COGS/inventory until done.
- 2024 GL contains 2 × $1.678B receipt journals (docs 139444/139833, item 27538289 received at $839,054,119/EA — phone number in cost field) — they cancel; Mar/Apr 2024 activity polluted.

## GL imports (to build)
GL → Journal Entry → F2 Import → Wizard: source = Windows File (CSV/Excel), map columns Account|Reference|Description|Debit|Credit, mappings saveable as named profiles, preview before Process. Plan: converters for check register (payee→account rules), payroll register (wages→61650-61695 by dept, taxes→62100/62200), credit cards (→24xxx). Recurring journals for depreciation/rent.

## Related
- Chart of accounts: 41100/41200 sales, 41500 installed sales, 515xx COGS, 616xx labor by dept, 21450 accrued sales tax, 23502 notes payable (holds the $225k reclass), 81500 junk.
- Session memory: `C:\Users\lmiller.INTEGRIBILT\.claude\projects\C--\memory\ky-sales-tax-project.md` and `spruce-ui-navigation.md`.

## Operational rhythm
- Spruce GL documents post via scheduled EOD run at ~11 PM; same-day verification requires waiting for it or force-posting (don't force casually). Local copy DB refreshes after that — same-day changes invisible in copy until refresh.
- Sales tax has never been remitted; until first filing, schedules can be regenerated freely as install closeouts land. Regenerate ky_filing_FORM_v3 after closeout waves, before KY portal entry.
- Install closeout flow: user closes contracts in Spruce; expect income→41500, tax→21450, COGS→51100. First verified test case: contract 2410-519399 'South Cherry Leaf Sonora' (June 2026).

## STATE SNAPSHOT 2026-06-10 (read this first in new sessions)
- KY sales tax: last filed Sep 2019. Final schedule references/ky_filing_FINAL_v5 (80 returns, $979,182.37). KY Collections case 2100000797804 (letter 5/25/2025, $475,371 demand on ESTIMATES of $252,400 for Oct19-Aug22; ACTUALS for window = $502,880 — filing trues UP; lien filed Jun 2022). All-in exposure ~$1.4-1.6M vs ~$1.5M hard assets (Master Asset Schedule). Plan: KY tax controversy attorney before completing portal filing. Filing = ORIGINAL returns. Pre-Spruce months Oct19-Jan20 pending (KY estimated $12k/mo — contest with actuals near zero/startup).
- GL pipeline complete on SVR12 C:\Users\lmiller.INTEGRIBILT\gl-imports (registers/payroll/amex/cash all coded; hold $1.01M small tail). Sales tax monthly PDFs: filenames from 202202 onward are one month BEHIND content; trust the YearMonth parameter inside.
- Open Spruce work: negative inventory fix, panel-shop UM/cost revaluation, install closeouts (user closing; priority list references/install_closeout_priority.csv), A/R judgments active (do NOT write off — only Maupin), F2 import test pending.

## STATE SNAPSHOT 2026-06-11: GL CATCH-UP COMPLETE
All 75 months Apr2020-Jun2026 imported via GL Journal Entry F2 wizard (JEIMPORT mapping) and POSTED. ~$60M+ total activity: registers, payroll, Amex, Amazon (41 mo from Unified Transaction report: 41400 sales/81200 fees/51200 labels/10300 payouts). Year-end closes FY2019-FY2023 run (first ever). AP Transfer $1.1M run (Payables>Utilities>Transfer A/P). Created: 30150 Owner Draws (30400=RE-current, NOT postable for draws), MKTP 0% tax code. Cycle window rule: manual journals post only ~current GL cycle +2yrs; advance via GL>Close Cycle (F12+Yes per month; blockers: unposted GL journals, untransferred AP). Import format: no header/quotes/commas-in-desc/negative amounts. Remaining: monthly closes 2024+, trial balance vs CPA, inventory cost repair (ECI ticket) then counts.
