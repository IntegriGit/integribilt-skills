#!/usr/bin/env bash
set -euo pipefail

GW="${LITELLM_GATEWAY_URL:-http://192.168.254.2:4000}"
REPO="${INTEGRIBILT_SKILLS_REPO:-https://github.com/IntegriGit/integribilt-skills}"

if [[ -z "${LITELLM_API_KEY:-}" ]]; then
  echo "LITELLM_API_KEY is not set. Load it from BWS into the local shell; do not write it to disk." >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 2
fi
if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required" >&2
  exit 2
fi

if [[ "$#" -lt 1 ]]; then
  echo "Usage: $0 <skill-name> [skill-name ...]" >&2
  exit 2
fi

for skill in "$@"; do
  if [[ ! -f "$skill/SKILL.md" ]]; then
    echo "$skill: missing $skill/SKILL.md; skipping" >&2
    continue
  fi

  body=$(jq -n \
    --arg n "$skill" \
    --arg url "$REPO" \
    --arg p "$skill" \
    '{name:$n, source:{source:"git-subdir", url:$url, path:$p}, description:("IntegriBilt " + $n + " skill"), domain:"IntegriBilt", namespace:"ops"}')

  reg_body="$(mktemp)"
  en_body="$(mktemp)"
  trap 'rm -f "$reg_body" "$en_body"' EXIT

  reg=$(curl -sS -o "$reg_body" -w '%{http_code}' \
    -X POST "$GW/claude-code/plugins" \
    -H "Authorization: Bearer $LITELLM_API_KEY" \
    -H 'Content-Type: application/json' \
    -d "$body")

  if [[ "$reg" =~ ^20[0-4]$ || "$reg" == "409" ]]; then
    en=$(curl -sS -o "$en_body" -w '%{http_code}' \
      -X POST "$GW/claude-code/plugins/$skill/enable" \
      -H "Authorization: Bearer $LITELLM_API_KEY")
    echo "$skill: register=$reg enable=$en"
    if [[ ! "$en" =~ ^20[0-4]$ ]]; then
      sed 's/[A-Za-z0-9_=-]\{24,\}/[REDACTED]/g' "$en_body" >&2
      exit 1
    fi
  else
    echo "$skill: register failed HTTP $reg" >&2
    sed 's/[A-Za-z0-9_=-]\{24,\}/[REDACTED]/g' "$reg_body" >&2
    exit 1
  fi

  rm -f "$reg_body" "$en_body"
done

curl -sS "$GW/claude-code/marketplace.json" | jq -r '.plugins[].name' | sort
