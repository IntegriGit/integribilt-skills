# agentic-actions-auditor

>

## What I do
Static security analysis guidance for GitHub Actions workflows that invoke AI coding agents. This skill teaches you how to discover workflow files locally or from remote GitHub repositories, identify AI action steps, follow cross-file references to composite actions and reusable workflows that may contain hidden AI agents, capture security-relevant configuration, and detect attack vectors where attacker-controlled input reaches an AI agent running in a CI/CD pipeline.

## How to use me
- Auditing a repository's GitHub Actions workflows for AI agent security
- Reviewing CI/CD configurations that invoke Claude Code Action, Gemini CLI, or OpenAI Codex
- Checking whether attacker-controlled input can reach AI agent prompts
- Evaluating agentic action configurations (sandbox settings, tool permissions, user allowlists)
- Assessing trigger events that expose workflows to external input (`pull_request_target`, `issue_comment`, etc.)
- Investigating data flow from GitHub event context through `env:` blocks to AI prompt fields

## Tools I use
- Standard IntegriBilt MCP tools
