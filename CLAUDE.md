# llm-router

Go CLI that routes LLM tasks to the cheapest model that can handle them well. Claude for complex work, Ollama (local) for bulk operations.

## Structure
- `cmd/router/` — CLI entrypoint
- `internal/router/` — task classification and routing
- `internal/benchmark/` — benchmark storage and analysis
- `internal/ollama/` — Ollama API client
- `internal/claude/` — Claude API client
- `internal/config/` — config loading
- `benchmarks/` — benchmark results (JSONL, gitignored)
- `scripts/` — setup scripts

## Standards
- Go backend following `standards/code-standards.md` from agent-startup
- Tests required for all packages
- Trunk-based development, PRs to main
