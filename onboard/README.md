# onboard

New team member or new service onboarding guide.

## What I do
I walk through IntegriBilt onboarding steps: setting up access (Bitwarden, GitHub, Slack), explaining the stack (LiteLLM gateway, Portainer, services on 192.168.254.2), and providing the Claude Code configuration needed to connect to the skills marketplace and MCP servers.

## How to use me
Say who or what is being onboarded. For a person: I provide access checklist and environment setup. For a new service: I walk through Docker deployment, Portainer stack registration, Zabbix monitoring setup, and MCP server registration.

## Claude Code setup I provide
```json
{
  "extraKnownMarketplaces": {
    "integribilt": {
      "source": "url",
      "url": "http://192.168.254.2:4000/claude-code/marketplace.json"
    }
  }
}
```
Point your API base URL to: `http://192.168.254.2:4000`
