# security-scan

Security posture review for code, infrastructure, and network.

## What I do
I run a layered security review: static analysis on code with Semgrep, network exposure check with Nmap, threat lookup on IPs/domains via Shodan and VirusTotal, and secret scanning in the repository. I produce a prioritized findings report.

## How to use me
Tell me what to scan: a repo path, an IP range, a domain, or "everything". I will run appropriate tools and report findings with severity ratings.

## Tools I use
- semgrep MCP for SAST
- nmap MCP for network scanning
- shodan MCP for exposure intelligence
- virustotal MCP for threat analysis
- filesystem / git MCP for secret scanning in code
