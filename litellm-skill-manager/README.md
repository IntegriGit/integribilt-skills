# litellm-skill-manager

Workflow for registering and uploading skills to the LiteLLM Gateway marketplace.

## What I do
I provide the standardized script and procedure to register and enable any newly created skills to the IntegriBilt LiteLLM Gateway (`192.168.254.2:4000`), ensuring they show up in the `/claude-code/marketplace.json` endpoint.

## How to use me
Whenever a user asks you to register new skills to LiteLLM, run the following PowerShell script from within the `integribilt-skills` repository directory. It reads the LiteLLM Master API token from the `llm.txt` file (or from the `$env:LITELLM_API_KEY` environment variable), loops over the skills, and performs the two-step registration/enablement process:

```powershell
# Prerequisites: The skills must already be pushed to the IntegriGit/integribilt-skills GitHub repository.
# You must have the LITELLM_API_KEY. If running on a desktop without it, retrieve it from the user or BWS and save it to llm.txt temporarily.

$token = (Get-Content llm.txt).Trim() # Or use $env:LITELLM_API_KEY
$skills = Get-ChildItem -Directory | Select-Object -ExpandProperty Name
$successCount = 0

foreach ($skill in $skills) {
    # 1. Register the plugin
    @{
        name = $skill
        source = @{
            source = "git-subdir"
            url = "https://github.com/IntegriGit/integribilt-skills"
            path = $skill
        }
        description = "IntegriBilt $skill skill"
        domain = "IntegriBilt"
        namespace = "ops"
    } | ConvertTo-Json -Depth 5 | Out-File "payload.json" -Encoding ascii
    
    $regResponse = curl.exe -s -o NUL -w "%{http_code}" -X POST http://192.168.254.2:4000/claude-code/plugins -H "Authorization: Bearer $token" -H "Content-Type: application/json" -d "@payload.json"
    
    if ($regResponse -eq "200" -or $regResponse -eq "201" -or $regResponse -eq "204") {
        # 2. Enable the plugin
        $enResponse = curl.exe -s -o NUL -w "%{http_code}" -X POST http://192.168.254.2:4000/claude-code/plugins/$skill/enable -H "Authorization: Bearer $token"
        if ($enResponse -eq "200" -or $enResponse -eq "201" -or $enResponse -eq "204") {
            $successCount++
        } else {
            Write-Host "Failed to enable $skill, status: $enResponse"
        }
    } else {
        Write-Host "Failed to register $skill, status: $regResponse"
    }
}
Write-Host "Successfully registered and published $successCount out of $($skills.Count) skills."
Remove-Item payload.json -ErrorAction SilentlyContinue
Remove-Item llm.txt -Force -ErrorAction SilentlyContinue
```

## Tools I use
- `run_command` (PowerShell, curl.exe)
