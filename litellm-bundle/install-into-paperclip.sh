#!/usr/bin/env bash
# Install the IntegriBilt litellm-bundle into Paperclip's company library,
# then (optionally) assign it to the dedicated employee agent(s).
#
# Usage:
#   export PAPERCLIP_API_URL="http://localhost:3100"
#   export PAPERCLIP_COMPANY_ID="<company-id>"
#   export PAPERCLIP_API_KEY="<operator/board token>"        # never hardcode; pull from BWS if scripted
#   export PAPERCLIP_AGENT_IDS="<agent-id-1> [<agent-id-2>]" # optional: assign on install
#   export IMPORT_MODE="repo"   # "repo" (default, preferred) or "local"
#   bash install-into-paperclip.sh
set -euo pipefail

: "${PAPERCLIP_API_URL:?set e.g. http://localhost:3100}"
: "${PAPERCLIP_COMPANY_ID:?your Paperclip company id}"
: "${PAPERCLIP_API_KEY:?operator/board token}"
IMPORT_MODE="${IMPORT_MODE:-repo}"
SKILLS_ROOT="${SKILLS_ROOT:-E:/agent-toolbox/agent/skills/integribilt-skills}"
REPO="IntegriGit/integribilt-skills"

SKILLS=(langfuse langsmith langtrace langgraph langchain litellm-skill-manager)
AUTH=(-H "Authorization: Bearer $PAPERCLIP_API_KEY" -H "Content-Type: application/json")

echo "== importing ${#SKILLS[@]} skills into company $PAPERCLIP_COMPANY_ID (mode=$IMPORT_MODE) =="
for s in "${SKILLS[@]}"; do
  if [ "$IMPORT_MODE" = "local" ]; then
    src="$SKILLS_ROOT/$s"                # dev/testing only
  else
    src="$REPO/$s"                       # preferred: org/repo/skill (must be pushed to GitHub first)
  fi
  code=$(curl -sS -o /tmp/pc-import.json -w '%{http_code}' \
    -X POST "$PAPERCLIP_API_URL/api/companies/$PAPERCLIP_COMPANY_ID/skills/import" \
    "${AUTH[@]}" -d "$(jq -n --arg src "$src" '{source:$src}')")
  key=$(jq -r '.key // .skill.key // .name // empty' /tmp/pc-import.json 2>/dev/null)
  echo "  $s -> HTTP $code ${key:+(key=$key)}"
  [[ "$code" =~ ^20[0-9]$ ]] || { echo "    FAILED:"; sed 's/[A-Za-z0-9_=-]\{24,\}/[REDACTED]/g' /tmp/pc-import.json; }
done

echo "== company skills now containing lang/litellm =="
curl -sS "$PAPERCLIP_API_URL/api/companies/$PAPERCLIP_COMPANY_ID/skills" "${AUTH[@]}" \
  | jq -r '.[]?.key // .skills[]?.key' 2>/dev/null | grep -iE "lang|litellm" || echo "  (none matched — check import output)"

if [ -n "${PAPERCLIP_AGENT_IDS:-}" ]; then
  desired=$(printf '%s\n' "${SKILLS[@]}" | jq -R . | jq -s .)
  for a in $PAPERCLIP_AGENT_IDS; do
    echo "== assigning bundle to agent $a =="
    curl -sS -X POST "$PAPERCLIP_API_URL/api/agents/$a/skills/sync" "${AUTH[@]}" \
      -d "$(jq -n --argjson d "$desired" '{desiredSkills:$d}')" \
      | jq -r '.assigned // .desiredSkills // "synced"' 2>/dev/null || true
  done
else
  echo "== PAPERCLIP_AGENT_IDS not set — skipping agent assignment (assign your 1-2 employees later) =="
fi

rm -f /tmp/pc-import.json 2>/dev/null || true
echo "== done =="
