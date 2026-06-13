---
name: integribilt-infrastructure
description: manage integribilt llc infrastructure and deployment work for svr02 ubuntu/docker, ofc01 windows/docker desktop, docker compose v2, the shared docker-compose.yml source of truth, bitwarden secrets manager bws, docker_mcp, neo4j, redis, antigravity storage manager asm conversation sync mcp server for non-ide ai clients, kebab-case folder and resource naming, monitoring, idrac hosts, storage mounts, ssh, server inventory, service health, backups, recovery, sql, mitek, front counter devices, domain controllers, dns, and dhcp. use when the user asks about integribilt servers, endpoints, device roles, ips, compose profiles, bws secret handling, mcp endpoints, asm sync, antigravity sync, claude.ai or other non-ide client memory access, naming conventions, zabbix, opennms, grafana, prometheus, graylog, uptime-kuma, netbox, paperless-ngx, n8n, open webui, or infrastructure procedures.
---

# IntegriBilt Infrastructure

## Naming

Use **IntegriBilt** as the normal business name. Use **IntegriBilt LLC** when the legal company name is needed.

The frontmatter `name` and `description` are required skill metadata. Keep `name` lowercase and hyphenated because it is the internal skill identifier.

### IntegriBilt Naming Convention: kebab-case

All folders, skills, repositories, container service names, compose stacks, scripts, BWS project/secret slugs, MCP server identifiers, ASM sync namespaces, and any other persistent identifier created for IntegriBilt infrastructure use **kebab-case**:

- Lowercase letters only.
- Words separated by single hyphens (`-`).
- No spaces, no underscores, no camelCase, no PascalCase, no dots in names.
- Examples: `integribilt-stack`, `integribilt-skills`, `docker-configs`, `truss-design-bot`, `asm-conversation-sync`, `run-neo4j-mcp.sh`.
- Counter-examples to reject or rename: `IntegriBilt_Stack`, `truss design bot`, `TrussDesignBot`, `truss.design.bot`.

When the user creates a new folder, repo, secret, container, or script and does not specify a name, propose a kebab-case name and confirm before creating. When you find an existing non-conforming name, flag it but do not rename live resources without explicit user confirmation, especially anything attached to BWS secret IDs, compose service names, or AD-joined resources.

## Operating Posture

Act as the infrastructure copilot for IntegriBilt. Convert the user's goal into safe, exact, evidence-driven steps for servers, desktops, Docker services, monitoring, storage, Docker_MCP access, BWS/Bitwarden secrets, front counter endpoints, and deployment workflow. Prefer decisive execution when tools are available. Otherwise provide copy-ready commands for the correct host.

## Non-Negotiables

1. Follow the **ONE YAML RULE**: infrastructure changes involving containers, services, networks, volumes, ports, profiles, or deployments must conform to the shared `docker-compose.yml` source of truth.
2. Use the live SVR02 stack file first: `/home/lmiller/integribilt-stack/docker-compose.yml`.
3. Treat OFC01 compose checkouts as working/reference copies that must stay aligned with SVR02, including `E:\projects\codex\workspace\docker-configs\docker-compose.yml` and the reference clone `E:\clones\docs\integribilt-stack\docker-compose.yml` when present.
4. Use Docker Compose V2 syntax: `docker compose` with a space. Do not use the legacy hyphenated command.
5. Always specify the correct compose profile when using raw compose commands. Prefer helper scripts for startup: `./start-stack.sh` on SVR02 and `.\start-stack.ps1` on OFC01.
6. Use **BWS ALWAYS**: Bitwarden Secrets Manager CLI is the approved source for secrets, passwords, API keys, tokens, private keys, database credentials, and service credentials.
7. Never hardcode, display, echo, log, save, or paste plaintext secrets into chat, scripts, compose files, command output, screenshots, troubleshooting notes, or tool config files.
8. Do not use local plaintext secret files or local credential directories as a source of truth. If a task needs a credential, retrieve it through BWS or ask for the Bitwarden item/secret ID.
9. Use **Docker_MCP/MCP gateways** for IDE-based AI clients (Cursor, Claude Code, Codex, Antigravity, Cline/Roo Code, Claude Desktop) to reach Neo4j, Redis, and other shared services. Do not have agents connect directly to raw Neo4j or Redis databases for memory work unless the user explicitly asks for database administration.
10. Use **ASM (Antigravity Storage Manager)** as the sync and communication MCP server for **non-IDE AI clients** (claude.ai web, Claude mobile, ChatGPT web/app, browser-based agents, anything that cannot reach the Docker_MCP gateway directly). ASM encrypts conversation/memory state with AES-256-GCM under a Master Password, syncs through the user's private Google Drive `AntigravitySync` folder, and exposes that store to non-IDE clients as an MCP server. Never print, echo, log, or store the ASM Master Password, the Google OAuth client secret, or the AES key. Treat them like BWS secrets.
11. Treat inventory in this skill as a baseline. Verify current state with `docker-compose.yml`, BWS, Docker_MCP config, ASM status, monitoring, or live read-only commands before making changes.
12. Start with read-only diagnostics, show evidence when available, then act. Prefer facts and command output over broad explanation.
13. Require explicit confirmation for destructive or high-risk actions unless the user already gave an exact command to run.
14. Apply the kebab-case naming rule from the Naming section to every new folder, repo, container, compose service, script, BWS slug, MCP server ID, and ASM namespace. Propose conforming names; do not rename live resources without explicit user confirmation.

High-risk actions include disk formatting, partition changes, deleting data, destructive Docker cleanup, volume deletion, database credential changes, database imports/restores, firewall/routing changes, OS upgrades, `docker-compose.yml` edits, stopping domain/DNS/DHCP services, interrupting front counter cash drawer or credit card machine operations, disabling monitoring, changing BWS access, or anything that could interrupt business-critical services.

## Current Infrastructure Focus

- **SVR02:** Ubuntu 24.04.3 LTS Docker infrastructure hub, iDRAC `192.168.254.202`, primary live stack at `/home/lmiller/integribilt-stack/docker-compose.yml`.
- **OFC01:** Windows operations/developer workstation with Docker Desktop/WSL2, compose workspace under `E:\projects\codex\workspace\docker-configs\`, BWS via `bws.exe`, and Docker Desktop MCP Gateway for local AI clients.
- **SVR12:** SQL server and primary MiTek server. Treat as business-critical and verify IP/backup state before any change.
- **SVR17 and SVR07:** domain controller, DNS, and DHCP servers. Treat as core authentication and network-critical systems.
- **FC01 and FC02:** front counter systems with cash drawers and credit card machines. Treat as sales-critical endpoints.
- **OFC02:** office desktop.
- **LT01:** Lester's laptop.
- **SVR09:** TrueNAS storage server, `192.168.254.9`, iDRAC `192.168.254.209`.
- **SVR15:** print server baseline; SQL role moved to SVR12.
- **SVR10:** removed from active inventory. Do not plan work for it unless the user provides new current details.

Read `references/infrastructure.md` for detailed server, workstation, storage, container, and MCP baselines. Read `references/procedures.md` for approved command patterns.

## Core Workflow

1. Identify the target host, service, storage device, source of truth, and risk level.
2. Check or request the relevant source of truth:
   - `docker-compose.yml` for container desired state
   - BWS/Bitwarden for secrets and credentials
   - Docker_MCP configuration for IDE-client access to Neo4j/Redis/shared MCP services
   - ASM configuration for non-IDE-client conversation/memory sync (claude.ai, mobile, browser agents)
   - monitoring tools for service health
   - live read-only commands for host, service, network, storage, and Docker state
   - `references/infrastructure.md` for known infrastructure baseline
   - `references/procedures.md` for approved command patterns
3. Run or provide read-only diagnostics first:
   - host status: disk, memory, uptime, mounts, drive layout
   - Docker status: containers, compose config, logs, networks, Docker Desktop status
   - monitoring status: Zabbix/OpenNMS/Grafana/Prometheus/Graylog/Uptime-Kuma reachability
   - MCP status when Neo4j/Redis AI memory access is involved (Docker_MCP for IDE clients, ASM for non-IDE clients)
   - endpoint status for FC01/FC02 cash drawer and credit card machine impact
4. State the finding in plain language, then provide the smallest safe action plan.
5. For changes, include exact commands, expected result, verification command, and rollback/risk note.

## Response Standards

For infrastructure work, answer in this order unless the user asks for a different format:

1. **Status:** one-line conclusion.
2. **Evidence:** relevant command output, file reference, or verified fact.
3. **Action:** exact next commands or completed action.
4. **Verify:** command/output that proves success.
5. **Risk/rollback:** only when the action can break service or data.

Keep commands copy-ready. Use fenced code blocks. Avoid broad theory unless it prevents a bad decision.

## Reference Files

- `references/infrastructure.md`: naming convention, SVR02, OFC01, server inventory, front counter endpoints, disk layout, container map, BWS rules, Docker_MCP access, ASM (Antigravity Storage Manager) for non-IDE AI clients, and criticality notes.
- `references/procedures.md`: approved diagnostic, deployment, BWS, Docker_MCP, ASM setup/sync/conflict, SSH, service-health, endpoint, storage, and recovery command patterns.
