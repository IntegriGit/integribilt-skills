# litellm-skill-manager

Hermes skill and helper scripts for publishing IntegriBilt skills to the self-hosted LiteLLM Gateway marketplace.

Read `SKILL.md` first. It is the source of truth.

## Safe usage

1. Validate/edit the skill locally.
2. Commit and push to `https://github.com/IntegriGit/integribilt-skills`.
3. Load `LITELLM_API_KEY` from BWS into the local shell. Do **not** use `llm.txt` or any plaintext token file.
4. Run one of:

```bash
scripts/register-skills.sh <skill-name> [skill-name ...]
```

```powershell
.\scripts\register-skills.ps1 <skill-name> [skill-name ...]
```

5. Verify:

```bash
curl -sS http://192.168.254.2:4000/claude-code/marketplace.json | jq -r '.plugins[].name' | sort
```
