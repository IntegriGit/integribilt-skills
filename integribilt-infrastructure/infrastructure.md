# IntegriBilt Infrastructure Reference

Use this as the current baseline for IntegriBilt infrastructure work. Verify live state before changing systems. The live SVR02 `docker-compose.yml`, BWS/Bitwarden, Docker_MCP config, monitoring tools, and read-only commands outrank this static reference if they differ.

## Naming Convention

All folders, repositories, container/service names, compose stacks, scripts, BWS slugs, MCP server IDs, and ASM namespaces use **kebab-case**: lowercase letters, hyphens between words, no spaces, no underscores, no camelCase, no dots. See the Naming section in `SKILL.md` for examples and renaming guardrails.

## Network Pattern

- Primary subnet: `192.168.254.0/24`
- Common server OS IP pattern: `192.168.254.X`
- Common iDRAC IP pattern: `192.168.254.(X+200)`
- Use explicit hostnames or IPs only after verification. Do not assume an IP for hosts marked verify.

## Current Device and Server Inventory

| Asset | Role | Known network details | Criticality and notes |
|---|---|---|---|
| SVR02 | Ubuntu/Docker primary infrastructure hub | OS `192.168.254.2`; iDRAC `192.168.254.202` | Critical Docker, monitoring, AI, and infrastructure host |
| OFC01 | Windows operations/developer workstation | OS `192.168.254.86`; no iDRAC | Docker Desktop, local AI client tooling, Zabbix monitoring hub |
| SVR07 | Domain controller, DNS, DHCP | Verify; likely follows server IP pattern | Critical authentication and network service host |
| SVR09 | TrueNAS storage | OS `192.168.254.9`; iDRAC `192.168.254.209` | Central storage, 60TB raw capacity baseline |
| SVR12 | SQL server and primary MiTek server | Verify; likely follows server IP pattern | Business-critical SQL and MiTek workloads |
| SVR15 | Print server baseline | OS `192.168.254.15`; iDRAC `192.168.254.215` | SQL role moved to SVR12 |
| SVR17 | Domain controller, DNS, DHCP | Verify; likely follows server IP pattern | Critical authentication and network service host |
| FC01 | Front counter endpoint | Verify | Critical; attached cash drawer and credit card machine |
| FC02 | Front counter endpoint | Verify | Critical; attached cash drawer and credit card machine |
| OFC02 | Office desktop | Verify | Standard office endpoint |
| LT01 | Lester's laptop | Verify | Owner laptop endpoint |
| SVR10 | Removed from active inventory | None | Do not plan work for it unless user provides new current details |

## SVR02 - Primary Infrastructure Hub

### Hardware and OS

- Hardware: Dell PowerEdge
- iDRAC: `192.168.254.202`
- OS: Ubuntu 24.04.3 LTS baseline
- Role: primary Docker/container infrastructure host

### Disk Architecture and Mounts

| Device | Label | Mount | Purpose | Rule |
|---|---|---|---|---|
| `sde` | OS | `/` | Ubuntu OS plus Docker engine/root at `/var/lib/docker` | Active |
| `sdd` | COR01 | `/srv` | Primary container data | Active |
| `sdb` | MDL02 | `/srv/mdl` | Redis, AI models, high-I/O model data | Active |
| `sdc` | BKP03 | `/srv/bkp` | Neo4j graph data and system backups | Active |
| `sda` | OLD_OS_REMOVE | `/mnt/docker-data` baseline | Old OS disk pending physical removal | Do not use for new work |

### Docker Configuration and ONE YAML RULE

- Live stack directory: `/home/lmiller/integribilt-stack`
- Live source-of-truth file: `/home/lmiller/integribilt-stack/docker-compose.yml`
- Compose syntax: `docker compose` only; do not use the legacy hyphenated command.
- Required raw-command profile: `--profile svr02`
- Preferred SVR02 startup: `./start-stack.sh`
- Docker root: `/var/lib/docker` on the OS disk.
- Main container data roots: `/srv`, `/srv/mdl`, and `/srv/bkp`.
- Secrets source of truth: BWS/Bitwarden only.

### Docker Data Directories Under `/srv`

```text
/srv/
├── core/       # core infrastructure services
├── biz/        # business applications
├── mon/        # monitoring stack
├── sec/        # security services
└── services/   # legacy service configs
```

Do not treat a local folder or local file as a credential source. Credentials must come from BWS/Bitwarden.

### Container Service Map

Verify exact service names, image names, profiles, volumes, and ports in `docker-compose.yml` before changing anything.

#### Monitoring Stack

- `prometheus` on 9090: metrics collection
- `grafana` on 3000: dashboards
- `loki`: log aggregation
- `promtail`: log shipping
- `cadvisor`: container metrics
- `netdata`: system monitoring
- `opennms-horizon` on 8980: network management
- `opennms-postgres`: OpenNMS database
- Zabbix services may remain on OFC01 until the user confirms a move

#### Business Applications

- `invoiceninja`: invoicing
- `snipe-it`: asset management
- `bookstack`: documentation wiki
- `bookstack-db`: Bookstack database
- `netbox`: DCIM/IPAM
- `paperless-ngx`: document management
- `gotenberg`: document conversion
- `tika`: content extraction

#### AI and MCP Stack

- `openwebui` on 3000: LLM interface
- `agent-zero`: AI agent container
- `litellm-proxy`: LLM routing
- `mcp-memory-server`: persistent memory MCP
- `mcp-postgres-server`: database MCP
- `mcp-filesystem-server`: file access MCP

#### Security

- `wazuh-manager`: SIEM manager
- `wazuh-dashboard`: Wazuh UI
- `wazuh-indexer`: Wazuh data/indexer
- `vaultwarden`: password manager service if present; not a substitute for BWS as the infrastructure secret source of truth

#### Infrastructure

- `traefik`: reverse proxy
- `redis-cache` on 6379: caching
- `neo4j` on 7474 and 7687: graph database
- `postgres`: general PostgreSQL database
- `postgres-backup`: backup service
- `gitea`: git hosting
- `graylog`: log management
- `opensearch-graylog`: Graylog backend
- `mongo-graylog`: Graylog metadata

#### Utilities

- `portainer` on 9000 and 9443: Docker UI
- `portainer-agent`: Portainer agent
- `dashy`: dashboard
- `heimdall`: app launcher
- `dozzle`: log viewer
- `stirling-pdf`: PDF tools
- `uptime-kuma`: uptime monitoring
- `beszel`: system monitor
- `n8n-server`: workflow automation
- `pihole`: DNS/ad blocking

## OFC01 - Operations and Developer Workstation

### System Architecture and Storage

OFC01 is a Windows Server/Desktop style workstation used for operations, local developer workspaces, Docker Desktop, monitoring, and local AI client tooling.

| Drive | Purpose | Notes |
|---|---|---|
| `C:\` | OS and application data | Windows OS, Docker Desktop WSL2 disk image, user profiles, global application data |
| `E:\` | Projects and workspaces | `E:\projects\Antigravity`, `E:\projects\codex`, Git repositories, Docker Compose checkouts |
| `D:\` | Scratch / secondary data | File-system tooling and temporary work |

Primary AD workstation user:

```text
INTEGRIBILT\lmiller
```

Local user mapping:

```text
OFC01\lmiller
```

Primary local profile path:

```text
C:\Users\lmiller.INTEGRIBILT
```

### OFC01 Docker Configuration and ONE YAML RULE

- Docker Engine runtime: Docker Desktop backed by WSL2.
- Active Codex workspace compose file: `E:\projects\codex\workspace\docker-configs\docker-compose.yml`.
- Workspace mappings may also reference `compose.yaml`.
- Known reference clone path: `E:\clones\docs\integribilt-stack\docker-compose.yml` when present.
- Keep OFC01 compose checkouts aligned with SVR02's live `/home/lmiller/integribilt-stack/docker-compose.yml`.
- Compose syntax: `docker compose` only; do not use the legacy hyphenated command.
- Preferred OFC01 startup: `.\start-stack.ps1`.

### OFC01 Monitoring Role

Keep these running unless the user explicitly authorizes downtime:

- Zabbix Server: monitoring 19 hosts baseline
- Zabbix Web: `http://192.168.254.86:8090`
- Zabbix PostgreSQL database

### OFC01 Docker Desktop MCP Gateway

OFC01 runs the local Docker Desktop MCP Gateway for local AI clients such as Codex, Claude Desktop, and Cursor.

Local config path:

```text
C:\Users\lmiller.INTEGRIBILT\.docker\mcp\config.yaml
```

Client profile:

```text
dev_workflow
```

Codex/client config pattern:

```toml
[mcp_servers.MCP_DOCKER]
command = 'docker.exe'
args = ['mcp', 'gateway', 'run', '--profile', 'dev_workflow']
```

Remote SVR02 memory endpoints over Tailscale:

| Service | Transport | URL | Auth |
|---|---|---|---|
| Neo4j GraphRAG | `streamable-http` | `https://svr02.tail7254e6.ts.net:8445/mcp/neo4j/mcp` | Basic Auth header injected from `SVR02_NEO4J_BASIC_AUTH` via BWS |
| Redis Cache | `sse` | `https://svr02.tail7254e6.ts.net:8445/mcp/redis/sse` | BWS-backed config if required |

Nginx on SVR02 is configured to intercept standard client pre-flight `HEAD` requests and return `200 OK` directly so the upstream Node/Supergateway service does not drop the connection.

### OFC01 SSH and Keys

Client SSH keys are managed under:

```text
C:\Users\lmiller.INTEGRIBILT\.ssh\
```

Dedicated tunneling key for automated agent tasks, stdio tunnels, and script syncs targeting SVR02:

```powershell
ssh -i C:\Users\lmiller.INTEGRIBILT\.ssh\id_ed25519_mcp lmiller@integribilt.local@svr02.integribilt.local
```

## BWS / Bitwarden Secrets Manager

BWS/Bitwarden is the only approved source for infrastructure secrets, passwords, API keys, tokens, private keys, database credentials, service credentials, and tool auth headers.

### SVR02 BWS

- CLI: `bws`
- Auth variable: `$BWS_ACCESS_TOKEN`

### OFC01 BWS

- CLI: `bws.exe`
- Auth variable: `$env:BWS_ACCESS_TOKEN`
- Windows helper scripts such as `run-compose.ps1` may run under `bws run` and process injected secrets without printing them.
- Helper scripts may clean newline characters and format application-specific arguments, such as prepending `neo4j/` to database auth strings.

## AI Client Access Patterns

IntegriBilt runs two parallel access paths for AI clients reaching shared memory and services. Pick the path that matches the client type.

| Client type | Access path | Where it lives | Purpose |
|---|---|---|---|
| IDE / desktop agent (Cursor, Claude Code, Codex, Antigravity, Cline, Claude Desktop, ChatGPT desktop with MCP) | Docker_MCP gateway | OFC01 Docker Desktop + SVR02 Tailscale endpoints | Direct, full-fidelity MCP access to Neo4j, Redis, filesystem, postgres, etc. |
| Non-IDE / web / mobile agent (claude.ai web, Claude mobile, ChatGPT web/app, browser agents, anything that cannot speak Docker_MCP) | ASM (Antigravity Storage Manager) | VS Code / Antigravity extension acting as MCP server, Google Drive as transport, AES-256-GCM at rest | Encrypted conversation/memory sync across machines and into non-IDE clients |

### Docker_MCP Access from SVR02

Neo4j and Redis are the backbone of the shared AI memory pipeline. IDE/desktop agents should use Docker_MCP/MCP gateways for memory access. Docker_MCP remains the encouraged path for any client that can reach the gateway.

Neo4j GraphRAG MCP:

- Local stdio access on SVR02: `/home/lmiller/.local/bin/run-neo4j-mcp.sh`
- Tailscale SSE/network access: `https://100.84.138.13:8445/mcp/neo4j/`

Redis Cache MCP:

- Local stdio access on SVR02: `/home/lmiller/.local/bin/run-redis-mcp.sh`
- SSE/network access is proxied by Supergateway and Nginx over Tailscale on port `8445`.

For AI clients on OFC01, use the Docker Desktop MCP Gateway profile and remote endpoints listed above.

### ASM (Antigravity Storage Manager) for Non-IDE Clients

ASM is a VS Code / Antigravity extension that doubles as the IntegriBilt sync-and-communication MCP server for AI clients that cannot reach the Docker_MCP gateway. It exists because claude.ai web, Claude mobile, ChatGPT web/app, and browser-based agents cannot run a local MCP gateway, so they need a shared, encrypted, network-reachable conversation/memory store.

#### What ASM does

- Encrypts all conversation and metadata with **AES-256-GCM** under a user-chosen Master Password.
- Stores ciphertext blobs in the user's private Google Drive folder `AntigravitySync` (file names look like `encrypted-blobs.zip.enc`).
- Syncs automatically every 5 minutes by default; supports manual sync from the VS Code Status Bar (`AG Sync` button) or `Antigravity Storage: Sync Now`.
- Exposes the synced store to non-IDE AI clients through an MCP server interface so claude.ai and other web/mobile clients can read and write shared conversation/memory context.
- Resolves cross-machine conflicts with `Keep Local`, `Keep Remote`, or `Keep Both` (the last appends a `-conflict` suffix).

#### Required configuration

- VS Code 1.96.0 or higher.
- Antigravity Storage Manager extension v0.3.0 or higher installed on each machine.
- A Google account with the Google Drive API enabled in a dedicated Google Cloud project (e.g. `antigravity-sync`).
- A Desktop-type OAuth client ID and secret for that project, pasted into VS Code Settings under `Antigravity`.
- A Master Password identical on every machine that joins the sync.
- The user's email added under **OAuth consent screen > Audience > Test users** for any project in External mode that has not passed Google verification.

#### Naming

Apply kebab-case to ASM-related resources where the user controls the name:

- Google Cloud project: `antigravity-sync` (or another kebab-case slug).
- OAuth client name: `antigravity-sync-client`.
- Any future per-namespace ASM stores: `asm-<context>`, e.g. `asm-integribilt-ops`, `asm-truss-design`.

The Google Drive folder name itself is fixed as `AntigravitySync` by the extension; do not rename it.

#### Secrets and security rules

- The ASM Master Password, Google OAuth client secret, and AES key are treated like BWS secrets: never print, echo, log, save to chat, paste into scripts, or commit to repos.
- Store the Master Password and OAuth client secret in BWS/Bitwarden under an `asm-*` item so they are recoverable without being in plaintext anywhere else.
- If the Master Password is lost, the only recovery is to disconnect ASM on all machines, delete the `AntigravitySync` folder in Google Drive, and re-run setup with a new password. Plan accordingly.

#### Operational guardrails

- ASM is sync-and-communication only. It does not replace Neo4j or Redis as the long-term memory backbone, and it does not replace BWS as the secret store.
- For destructive ASM actions (Disconnect on all machines, deleting `AntigravitySync` in Drive, changing the Master Password), require explicit user confirmation just like a credential rotation.
- Treat the ASM client config and OAuth secrets on OFC01, LT01, and any other workstation as workstation-critical. A broken ASM config does not break business operations but does break non-IDE AI memory continuity.

## SSH and Permissions

Primary AD server account:

```text
lmiller@integribilt.local
```

Known UID baseline:

```text
461801104
```

Use the fully qualified domain username for SVR02 SSH, especially with background agents and key-based access, so StrictModes validates `authorized_keys` correctly:

```bash
ssh -i <key> lmiller@integribilt.local@svr02.integribilt.local
```

## Critical Service Guardrails

### Domain Controllers, DNS, and DHCP: SVR07 and SVR17

- Treat SVR07 and SVR17 as network-critical.
- Avoid restarts, DNS changes, DHCP scope changes, domain policy changes, or certificate changes without explicit confirmation.
- Before any change, identify which server is primary for the service being touched and confirm replication/backup status.

### SVR12: SQL and Primary MiTek

- Treat SVR12 as business-critical.
- Confirm SQL instance, MiTek service dependencies, backup state, and maintenance window before changes.
- Do not apply generic SQL commands without confirming database name, instance, credentials, and rollback.

### FC01 and FC02 Front Counter Endpoints

- Treat FC01 and FC02 as sales-critical.
- Cash drawers and credit card machines may be attached. Verify peripheral impact before rebooting, changing drivers, changing network settings, or stopping POS-related software.
- Avoid downtime during business hours unless the user explicitly authorizes it.

### LT01 and OFC02

- Treat LT01 as Lester's laptop and OFC02 as an office desktop.
- Verify hostname, logged-in user, and active applications before remote changes.
