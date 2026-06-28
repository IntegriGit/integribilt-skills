param(
    [Parameter(Mandatory=$true, Position=0)]
    [string[]]$Skills,
    [string]$GatewayUrl = "http://192.168.254.2:4000",
    [string]$RepoUrl = "https://github.com/IntegriGit/integribilt-skills"
)

$ErrorActionPreference = "Stop"

if (-not $env:LITELLM_API_KEY) {
    throw "LITELLM_API_KEY is not set. Load it from BWS into this shell; do not write it to disk."
}

foreach ($skill in $Skills) {
    $skillFile = Join-Path $skill "SKILL.md"
    if (-not (Test-Path $skillFile)) {
        Write-Warning "${skill}: missing $skillFile; skipping"
        continue
    }

    $payload = @{
        name = $skill
        source = @{
            source = "git-subdir"
            url = $RepoUrl
            path = $skill
        }
        description = "IntegriBilt $skill skill"
        domain = "IntegriBilt"
        namespace = "ops"
    } | ConvertTo-Json -Depth 8 -Compress

    $headers = @{ Authorization = "Bearer $env:LITELLM_API_KEY"; "Content-Type" = "application/json" }

    try {
        $reg = Invoke-WebRequest -Method Post -Uri "$GatewayUrl/claude-code/plugins" -Headers $headers -Body $payload -UseBasicParsing
        $regCode = [int]$reg.StatusCode
    } catch {
        $regCode = [int]$_.Exception.Response.StatusCode
        if ($regCode -ne 409) { throw "$skill register failed HTTP $regCode" }
    }

    if (($regCode -ge 200 -and $regCode -le 204) -or $regCode -eq 409) {
        $enableHeaders = @{ Authorization = "Bearer $env:LITELLM_API_KEY" }
        $en = Invoke-WebRequest -Method Post -Uri "$GatewayUrl/claude-code/plugins/$skill/enable" -Headers $enableHeaders -UseBasicParsing
        Write-Host "${skill}: register=$regCode enable=$([int]$en.StatusCode)"
    }
}

(Invoke-RestMethod -Uri "$GatewayUrl/claude-code/marketplace.json").plugins.name | Sort-Object
