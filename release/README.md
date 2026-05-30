# release

End-to-end release management from changelog to deployment.

## What I do
I manage the full release cycle: pull recent git commits, generate a changelog, bump version, create a GitHub release, trigger CI/CD pipeline, monitor deployment health, and post release notes to Slack. I follow semantic versioning.

## How to use me
Tell me the version bump type (patch/minor/major) or describe what changed. I will handle the rest and confirm each step before proceeding.

## Tools I use
- git / github MCP for commits, tags, and releases
- github_actions MCP for CI/CD pipeline
- argocd MCP for GitOps deployment status
- prometheus / zabbix MCP for post-release health check
- slack MCP for release announcement
