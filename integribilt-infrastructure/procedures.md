# IntegriBilt Operations Procedures

Use these procedures as approved command patterns. Verify the target host, service, storage device, source of truth, and current state before making changes. Do not paste secrets or private configuration into chat output.

## Read-Only First Pass

### SVR02 Health Snapshot

Run from SVR02 or through approved SSH access:

```bash
hostnamectl
uptime
free -h
df -h | grep -E 'Filesystem| /$|/srv|/srv/mdl|/srv/bkp'
lsblk -f
mount | grep -E ' / |/srv|/srv/mdl|/srv/bkp'
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
docker stats --no-stream
```

### OFC01 Health Snapshot

Run from PowerShell on OFC01:

```powershell
hostname
Get-ComputerInfo | Select-Object CsName, OsName, WindowsVersion
Get-PSDrive -Name C,E,D
wsl --status
docker version
docker compose version
```

### SVR02 Compose Validation

```bash
cd /home/lmiller/integribilt-stack
ls -la docker-compose.yml
docker compose config --profiles
docker compose --profile svr02 config --quiet
docker compose --profile svr02 ps
```

### OFC01 Compose Validation

```powershell
cd E:\projects\codex\workspace\docker-configs
Test-Path .\docker-compose.yml
docker compose config --profiles
docker compose --profile <ofc01-profile> config --quiet
docker compose --profile <ofc01-profile> ps
```

If the active OFC01 task is using the reference clone, verify that path instead:

```powershell
Test-Path "E:\clones\docs\integribilt-stack\docker-compose.yml"
```

### Service Logs

SVR02:

```bash
cd /home/lmiller/integribilt-stack
docker compose --profile svr02 logs --tail=100 <service-name>
```

Use `-f` only when live log following is needed:

```bash
docker compose --profile svr02 logs -f <service-name>
```

OFC01:

```powershell
cd E:\projects\codex\workspace\docker-configs
docker compose --profile <ofc01-profile> logs --tail=100 <service-name>
```

## Direct SVR02 Access Pattern

Use the fully qualified IntegriBilt AD username for SSH to SVR02, especially for background agents and key-based access:

```bash
ssh -i <key> lmiller@integribilt.local@svr02.integribilt.local '<read-only-command>'
```

For multi-command checks, prefer a read-only shell block and avoid making changes until the source of truth has been checked:

```bash
ssh -i <key> lmiller@integribilt.local@svr02.integribilt.local '
  cd /home/lmiller/integribilt-stack &&
  hostnamectl &&
  uptime &&
  docker compose --profile svr02 ps &&
  df -h | grep -E "Filesystem| /$|/srv|/srv/mdl|/srv/bkp"
'
```

From OFC01, use the dedicated MCP/agent tunnel key when targeting SVR02:

```powershell
ssh -i C:\Users\lmiller.INTEGRIBILT\.ssh\id_ed25519_mcp lmiller@integribilt.local@svr02.integribilt.local "hostnamectl && uptime"
```

## Docker Operations

### Start SVR02 Stack Safely

Prefer the helper script:

```bash
cd /home/lmiller/integribilt-stack
./start-stack.sh
```

Use raw compose only when the helper script is unavailable or the task requires a specific compose operation:

```bash
cd /home/lmiller/integribilt-stack
docker compose --profile svr02 up -d
```

### Start OFC01 Stack Safely

```powershell
cd E:\projects\codex\workspace\docker-configs
.\start-stack.ps1
```

### Deploy or Update SVR02 Full Stack

Use only after confirming compose configuration, current backups for stateful services, and disk space.

```bash
cd /home/lmiller/integribilt-stack
docker compose --profile svr02 config --quiet
docker compose --profile svr02 pull
docker compose --profile svr02 up -d
docker compose --profile svr02 ps
```

### Restart One SVR02 Service

```bash
cd /home/lmiller/integribilt-stack
docker compose --profile svr02 restart <service-name>
docker compose --profile svr02 ps <service-name>
docker compose --profile svr02 logs --tail=80 <service-name>
```

### Check Container Health

```bash
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
docker inspect --format '{{.Name}} {{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}' <container-name>
docker stats --no-stream
```

Some containers do not define Docker healthchecks; use logs and port checks for those.

### Docker Cleanup Guardrail

Start with read-only size inspection:

```bash
docker system df
```

Any cleanup that deletes containers, images, build cache, logs, networks, or volumes requires explicit user confirmation and a service-impact note. Never delete volumes unless volume deletion is specifically approved.

## BWS / Bitwarden Secrets Management

Use BWS/Bitwarden as the only approved source for secrets, passwords, tokens, API keys, private keys, database credentials, service credentials, and auth headers.

Rules:

- Never print secret values into chat, logs, command output, saved files, screenshots, or troubleshooting notes.
- Never hardcode plaintext secrets into scripts, configuration files, compose files, docker commands, documentation, MCP configs, or tool JSON files.
- Refer to credentials by Bitwarden item name, secret ID, or placeholder, for example `<Bitwarden item: service-name / password>`.
- Do not invent local password files, local credential folders, or alternate credential stores.
- Do not run commands that return secret values into visible chat output.
- If the exact Bitwarden item is unknown, ask for the item name or identify it from an approved inventory before changing credentials.

### Confirm BWS Availability Without Printing Secrets

SVR02:

```bash
command -v bws
[ -n "$BWS_ACCESS_TOKEN" ] && echo "BWS_ACCESS_TOKEN is set" || echo "BWS_ACCESS_TOKEN is missing"
```

OFC01 PowerShell:

```powershell
Get-Command bws.exe
if ($env:BWS_ACCESS_TOKEN) { "BWS_ACCESS_TOKEN is set" } else { "BWS_ACCESS_TOKEN is missing" }
```

### Safe Secret Retrieval Pattern

SVR02 Bash:

```bash
SECRET_VALUE="$(bws secret get <SECRET_ID> -t "$BWS_ACCESS_TOKEN" | jq -r '.value')"
# Use SECRET_VALUE only inside the local command or script that needs it. Do not echo it.
```

OFC01 PowerShell:

```powershell
$secretObject = bws secret get <SECRET_ID> -t $env:BWS_ACCESS_TOKEN | ConvertFrom-Json
$secretValue = $secretObject.value
# Use $secretValue only inside the local command or script that needs it. Do not print it.
```

### Credential Rotation Guardrail

Credential rotation is high risk. Before changing any database or application credential, confirm the service, Bitwarden item or secret ID, backup state, dependent containers, and rollback path.

Approved pattern:

1. Verify the current service and dependent containers from `docker-compose.yml`.
2. Confirm the Bitwarden item name or secret ID.
3. Verify a backup exists before changing database or application credentials.
4. Retrieve the new credential through BWS in a secure local shell only.
5. Apply the credential using the service-specific command or admin interface without printing the value.
6. Restart only affected services.
7. Verify health, logs, ports, and application login.

## Docker_MCP Procedures

Neo4j and Redis are accessed by AI clients through Docker_MCP/MCP gateways, not direct raw database connections for AI memory work.

### SVR02 Local MCP Checks

```bash
test -x /home/lmiller/.local/bin/run-neo4j-mcp.sh && echo "neo4j mcp script present"
test -x /home/lmiller/.local/bin/run-redis-mcp.sh && echo "redis mcp script present"
ss -tulpn | grep 8445 || true
```

### OFC01 Docker Desktop MCP Gateway Checks

```powershell
Test-Path "C:\Users\lmiller.INTEGRIBILT\.docker\mcp\config.yaml"
docker mcp --help
```

Client config should use this pattern:

```toml
[mcp_servers.MCP_DOCKER]
command = 'docker.exe'
args = ['mcp', 'gateway', 'run', '--profile', 'dev_workflow']
```

### Remote SVR02 Memory Endpoint Checks

Use only non-secret health checks in chat. Do not print auth headers or secret values.

```powershell
Invoke-WebRequest -Method Head -Uri "https://svr02.tail7254e6.ts.net:8445/mcp/neo4j/mcp" -UseBasicParsing
Invoke-WebRequest -Method Head -Uri "https://svr02.tail7254e6.ts.net:8445/mcp/redis/sse" -UseBasicParsing
```

## ASM (Antigravity Storage Manager) Procedures

ASM is the sync and communication MCP server for non-IDE AI clients. Use these patterns for setup verification and read-only health checks. Never print, echo, log, or copy the Master Password, the Google OAuth client secret, or the AES key.

### Confirm ASM Prerequisites on a Workstation

```powershell
code --version
code --list-extensions | Select-String -Pattern 'antigravity'
```

Verify that the VS Code/Antigravity Settings UI has both `Antigravity: Client ID` and `Antigravity: Client Secret` populated. Confirm by opening Settings (`Ctrl+,`) and searching `Antigravity`; do not copy the secret value into chat output.

### First-Machine Setup (Read-Only Walkthrough)

The user runs the following Command Palette commands themselves; do not run them on the user's behalf:

```text
Antigravity Storage: Setup Google Drive Sync
```

Setup flow checklist to walk the user through:

1. Confirm the Google Cloud project exists with a kebab-case name (e.g. `antigravity-sync`).
2. Confirm Google Drive API is enabled in that project.
3. Confirm the OAuth consent screen has the user's email under **Audience > Test users**.
4. Confirm a Desktop-type OAuth client ID and secret have been issued and pasted into VS Code Settings.
5. User creates a strong Master Password and records it in BWS under an `asm-*` item before clicking through.
6. User authenticates with Google in the browser window the extension opens, then returns to VS Code.
7. Verify the `AG Sync` indicator appears in the VS Code Status Bar.

### Joining an Additional Machine to Existing Sync

```text
Antigravity Storage: Setup Google Drive Sync
```

Checklist:

1. Install ASM on the new machine.
2. Run the setup command; sign in with the same Google account.
3. When the extension detects an existing `AntigravitySync` folder, choose **Join Existing**.
4. Enter the Master Password from BWS without printing it into chat.
5. Wait for the initial decrypt-and-download to complete; confirm at least one expected conversation has decrypted successfully.

### Manual Sync and Status Check

```text
Antigravity Storage: Sync Now
```

Or click the `AG Sync` icon in the VS Code Status Bar. Confirm the last-sync timestamp updates and the status returns to idle without errors.

### Conflict Resolution

When ASM reports a conflict (same conversation edited on two machines while offline), prompt the user to choose one of:

- **Keep Local** — overwrites the cloud copy with the current workstation's version.
- **Keep Remote** — overwrites the workstation copy with the cloud version.
- **Keep Both** — keeps both copies; ASM renames one with a `-conflict` suffix.

Confirm with the user which side has the changes worth keeping before resolving. Do not auto-resolve.

### ASM Reset Guardrail

A full ASM reset is destructive and requires explicit user confirmation. Approved order:

1. Confirm the user has the Master Password (or accepts that it is lost) and has captured any conversations that must be preserved.
2. On every connected machine, run `Antigravity Storage: Disconnect Google Drive Sync`.
3. In the Google Drive web UI, delete the `AntigravitySync` folder.
4. Re-run `Antigravity Storage: Setup Google Drive Sync` on the primary machine with a fresh Master Password.
5. Re-join all other machines with the new Master Password.
6. Update the corresponding BWS `asm-*` item to reflect the new credentials.

### ASM "App not verified" / Error 403

If the user sees `Access blocked: application has not passed Google verification`:

1. Open Google Cloud Console > APIs & Services > OAuth consent screen (or Google Auth Platform).
2. Click **Audience** in the sidebar.
3. Under **Test users**, click **+ ADD USERS** and add the user's email address.
4. Save, then retry the sync setup.

### ASM Incorrect Password Error

If a workstation reports `Incorrect Password` after a Join Existing flow:

1. Confirm the user is entering the exact Master Password from the BWS `asm-*` item.
2. If still failing, run `Antigravity Storage: Disconnect Google Drive Sync` on that workstation only and re-run setup with the correct password.
3. Do not delete the `AntigravitySync` folder in Drive for this error; that would wipe other machines' data.

## Domain Controller, DNS, and DHCP Guardrails

SVR07 and SVR17 are critical domain, DNS, and DHCP servers. Use read-only checks first, and require explicit confirmation for restarts, scope changes, DNS zone edits, domain policy changes, certificate work, or demotion/promotion tasks.

Read-only examples from an appropriate admin shell:

```powershell
hostname
nltest /dsgetdc:integribilt.local
repadmin /replsummary
dcdiag /q
Get-DnsServerZone
Get-DhcpServerv4Scope
```

Before a change, confirm which host owns the role being changed and whether the other domain server is healthy.

## SVR12 SQL and MiTek Guardrails

SVR12 hosts SQL and the primary MiTek server role. Treat it as business-critical.

Before any change:

1. Confirm host identity, IP, and current logged-in users.
2. Confirm SQL instance name, MiTek services, dependent applications, and backup state.
3. Confirm whether a maintenance window is required.
4. Confirm credentials through BWS without printing values.
5. Prepare rollback steps before service restarts, database changes, or MiTek updates.

Read-only examples:

```powershell
hostname
Get-Service | Where-Object { $_.Name -match 'SQL|MSSQL|MiTek' -or $_.DisplayName -match 'SQL|MiTek' }
Get-Volume
```

Do not apply generic SQL or MiTek commands without verifying the exact service, database, instance, credential, and rollback path.

## Front Counter Endpoint Guardrails

FC01 and FC02 are front counter systems with cash drawers and credit card machines. Treat them as sales-critical.

Before rebooting or changing drivers, network settings, payment software, POS software, USB devices, printers, or peripherals:

1. Confirm whether the front counter is actively selling.
2. Confirm which peripherals are attached.
3. Capture current device status.
4. Get explicit approval for any downtime.
5. Verify cash drawer and credit card machine function afterward.

Read-only examples from an appropriate PowerShell session:

```powershell
hostname
Get-PnpDevice | Where-Object { $_.FriendlyName -match 'cash|drawer|card|payment|printer|receipt|usb' }
Get-NetAdapter
```

## Storage Triage

### SVR02 Storage

```bash
df -h
lsblk -f
sudo du -h --max-depth=2 /srv | sort -rh | head -20
docker system df
sudo journalctl --disk-usage
```

Deletion, truncation, cache cleanup, log cleanup, or volume actions require explicit confirmation and a rollback/risk note.

### OFC01 Storage

```powershell
Get-PSDrive -Name C,E,D
Get-ChildItem E:\projects -Directory | Select-Object FullName, LastWriteTime
```

Verify available space before large exports, imports, Docker Desktop moves, or local repository operations.

## Troubleshooting

### Container Will Not Start

1. Check compose source of truth: `docker-compose.yml`.
2. Validate config: `docker compose --profile <profile> config --quiet`.
3. Check logs: `docker compose --profile <profile> logs --tail=100 <service-name>`.
4. Check disk space and mounts.
5. Check BWS access if the service depends on injected secrets.
6. Check ports and dependent containers.

### Network Connectivity Issues

Use read-only tests first:

```bash
ip addr
ip route
ss -tulpn
docker network ls
docker network inspect <network>
```

From inside a container when appropriate:

```bash
docker exec <container> curl -v http://other-service:port
```

### Monitoring Health

```bash
cd /home/lmiller/integribilt-stack
docker compose --profile svr02 ps prometheus grafana graylog uptime-kuma opennms-horizon
```

If Zabbix is involved, confirm whether the active Zabbix services are still on OFC01 before changing monitoring routes or service ownership.
