---
name: litellm-skill-manager
description: "Use when registering, enabling, updating, auditing, or troubleshooting IntegriBilt skills in the self-hosted LiteLLM Gateway marketplace at 192.168.254.2:4000, including /claude-code/marketplace.json visibility for Claude Code and other marketplace clients."
version: 1.1.0
author: IntegriBilt + Hermes Agent
license: Proprietary
metadata:
  hermes:
    tags: [integribilt, litellm, marketplace, skills, claude-code, gateway]
    related_skills: [hermes-agent-skill-authoring, integribilt-infrastructure]
---

# LiteLLM Skill Manager

## Overview

This skill publishes IntegriBilt skills to the self-hosted LiteLLM Gateway plugin marketplace so Claude Code and marketplace-aware clients can discover them from:

```text
http://192.168.254.2:4000/claude-code/marketplace.json
```

The gateway reads skills from GitHub by `git-subdir`. It does **not** read the local checkout directly. The workflow is: validate skill locally → commit/push to `IntegriGit/integribilt-skills` → register plugin → enable plugin → verify marketplace JSON.

## When to Use

Use this skill when the user asks to:

- publish a new skill to LiteLLM / Claude Code marketplace;
- refresh an existing skill after editing it;
- register or enable one or more `integribilt-skills/<skill>/SKILL.md` directories;
- check whether a skill appears in `/claude-code/marketplace.json`;
- troubleshoot missing marketplace entries, 401/403/404 responses, bad source paths, or invalid skill frontmatter.

Do not use this skill to author skill content from scratch; use `hermes-agent-skill-authoring` for the SKILL.md structure, then return here for marketplace publication.

## Marketplace Architecture

```text
integribilt-skills/<skill>/SKILL.md
       │ commit + push
       ▼
github.com/IntegriGit/integribilt-skills
       │ POST /claude-code/plugins
       │ POST /claude-code/plugins/<skill>/enable
       ▼
LiteLLM Gateway on SVR02: http://192.168.254.2:4000
       │
       ▼
GET /claude-code/marketplace.json  -> { "plugins": [...] }
```

Verified read-only shape on 2026-06-28: marketplace JSON has top-level keys `name`, `owner`, and `plugins`; plugin entries use `.plugins[].name`.

## Prerequisites

1. The skill exists as `integribilt-skills/<skill>/SKILL.md`.
2. The skill frontmatter validates: starts at byte 0 with `---`, has `name` and `description`, and has a non-empty body.
3. The skill is committed and pushed to `https://github.com/IntegriGit/integribilt-skills` on the branch the gateway tracks, normally `main`.
4. `curl`, `jq`, `git`, and BWS are available on the host running registration.
5. The LiteLLM master key is retrieved from BWS into the local shell only. Never use `llm.txt`, never write the key to disk, and never print it.

Safe secret pattern:

```bash
# Set LITELLM_MASTER_KEY_SECRET_ID in the local shell or ask the user for the BWS secret ID.
export LITELLM_API_KEY="$(bws secret get "$LITELLM_MASTER_KEY_SECRET_ID" -t "$BWS_ACCESS_TOKEN" | jq -r '.value')"
[ -n "$LITELLM_API_KEY" ] && echo "LiteLLM key loaded from BWS"
```

## Publish / Refresh One Skill

Run from the repository root containing the skill directory.

```bash
GW='http://192.168.254.2:4000'
REPO='https://github.com/IntegriGit/integribilt-skills'
skill='<skill-name>'

# read-only validation
[ -f "$skill/SKILL.md" ] || { echo "missing $skill/SKILL.md"; exit 1; }
git status --short "$skill"
git ls-remote --exit-code "$REPO" >/dev/null

body=$(jq -n \
  --arg n "$skill" \
  --arg url "$REPO" \
  --arg p "$skill" \
  '{name:$n, source:{source:"git-subdir", url:$url, path:$p}, description:("IntegriBilt " + $n + " skill"), domain:"IntegriBilt", namespace:"ops"}')

reg=$(curl -sS -o /tmp/litellm-register.json -w '%{http_code}' \
  -X POST "$GW/claude-code/plugins" \
  -H "Authorization: Bearer $LITELLM_API_KEY" \
  -H 'Content-Type: application/json' \
  -d "$body")

if [[ "$reg" =~ ^20[0-4]$ || "$reg" == "409" ]]; then
  en=$(curl -sS -o /tmp/litellm-enable.json -w '%{http_code}' \
    -X POST "$GW/claude-code/plugins/$skill/enable" \
    -H "Authorization: Bearer $LITELLM_API_KEY")
  echo "$skill register=$reg enable=$en"
else
  echo "$skill register failed: HTTP $reg"
  sed 's/[A-Za-z0-9_=-]\{24,\}/[REDACTED]/g' /tmp/litellm-register.json
  exit 1
fi
```

Completion criterion: registration returns 2xx or an already-registered 409, enable returns 2xx, and the skill appears in marketplace JSON.

## Publish / Refresh Multiple Skills

Preferred: use the helper script if present:

```bash
scripts/register-skills.sh integribilt-infrastructure litellm-skill-manager spruce-accounting tailscale-admin tailscale-daily
```

Manual loop:

```bash
for skill in "$@"; do
  [ -f "$skill/SKILL.md" ] || { echo "skip missing $skill/SKILL.md"; continue; }
  # run the one-skill publish block for each skill
  :
done
```

Do not blindly publish every directory if the repo contains scratch, archive, nested duplicate, or incomplete skill folders. List the target names explicitly.

## Verify Marketplace

```bash
curl -sS http://192.168.254.2:4000/claude-code/marketplace.json \
  | jq -r '.plugins[].name' \
  | sort
```

Verify specific skills:

```bash
for skill in integribilt-infrastructure litellm-skill-manager spruce-accounting tailscale-admin tailscale-daily; do
  curl -sS http://192.168.254.2:4000/claude-code/marketplace.json \
    | jq -e --arg n "$skill" '.plugins[] | select(.name == $n)' >/dev/null \
    && echo "$skill: present" || echo "$skill: missing"
done
```

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `401` / `403` | Wrong or expired master key | Re-pull `LITELLM_API_KEY` from BWS; confirm it is the gateway master key |
| `404` on `/claude-code/plugins` | Gateway image lacks route or route changed | Check gateway version/routes before retrying; marketplace read endpoint may still work |
| Register succeeds but marketplace missing | Plugin not enabled | Run `POST /claude-code/plugins/<skill>/enable` and verify 2xx |
| Marketplace entry points to old content | Skill was not pushed, wrong branch, or gateway cache | Push to tracked branch, then re-register/enable |
| Gateway cannot fetch skill | Bad repo URL/path or private repo auth problem | Confirm `source.url`, `source.path`, and gateway GitHub access |
| Skill loads empty or ignored | Invalid SKILL.md | Validate frontmatter and body before publishing |
| Duplicate/conflicting skill | Nested duplicate directory or repeated `name` | Publish only one canonical directory; archive duplicates after user approval |

## Safety Rules

- Never create or read `llm.txt` for the master key.
- Never put the master key in command output, JSON payload files, screenshots, notes, or committed scripts.
- Use `Authorization: Bearer $LITELLM_API_KEY` only inside local commands.
- Delete temporary response files after troubleshooting if they may contain sensitive gateway detail.
- Registration is mutating but low business-risk; policy is still validate → register → enable → verify.
