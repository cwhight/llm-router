# llm-router

Intelligent LLM task router. Claude for planning and heavy thinking, Ollama cloud models for bulk work. Self-benchmarking — learns over time which model is best for which task type.

## Concept

```
Claude Code (planning, reasoning, architecture)
    │
    ├─ Complex task → stays on Claude
    │
    └─ Simple task → routed to Ollama cloud (free, no local GPU)
        │
        ├─ summarise this file
        ├─ extract JSON from this text
        ├─ format this code
        ├─ classify this input
        └─ generate a simple function
```

## Why

Claude is excellent at complex reasoning but expensive for bulk operations. Ollama cloud models handle simple tasks well at zero marginal cost — no local GPU needed, models run on Ollama's servers. The router automatically directs each task to the cheapest model that can do it well.

## Models

All Ollama tiers use cloud-hosted models (free tier). No local GPU required.

| Tier | Model | Params | Latency | Best for |
|---|---|---|---|---|
| `ollama:small` | `qwen3-coder-next:cloud` | 80B | ~7s | Quick code, formatting |
| `ollama:large` | `devstral-2:123b-cloud` | 123B | ~8s | Complex code (Mistral specialist) |
| `ollama:general` | `gpt-oss:120b-cloud` | 117B | ~13s | Prose, reasoning (has thinking) |

## Task Classification

| Category | Default Route | Examples |
|---|---|---|
| `summarise` | ollama:general | Summarise a file, condense notes |
| `extract` | ollama:general | Pull JSON from text, parse structured data |
| `classify` | ollama:general | Sentiment analysis, categorisation |
| `format` | ollama:small | Reformat code, convert markdown |
| `simple-code` | ollama:small | Single function, simple script |
| `rewrite` | ollama:general | Rewrite text, change tone |
| `explain` | ollama:general | Explain a concept, document code |
| `complex-code` | ollama:large | Multi-file changes, refactoring |
| `wireframe-prose` | ollama:general | Design specs, technical writing |
| `reason` | claude:opus | Architecture, planning, trade-offs |
| `agent` | claude:default | Multi-step tool use, decisions |

## Self-Improving Benchmarks

Every routed task is scored:
1. **Quality** — did the output meet the requirement? (0-10, scored by Claude on a sample)
2. **Cost** — tokens used × rate
3. **Latency** — time to completion

Results are logged to `benchmarks/results.jsonl`. The router periodically analyses this data and adjusts routing thresholds.

## Install

```bash
git clone https://github.com/muzzapp/llm-router.git
cd llm-router

# Global — every Claude Code session on your machine uses llm-router
./scripts/install.sh --global

# Project — only the current repo's Claude Code sessions use llm-router
./scripts/install.sh --project

# Interactive — prompts you to choose
./scripts/install.sh
```

The installer:
1. Installs Ollama (if not present) and configures it to start at login
2. Pulls the three cloud routing models (manifest-only, ~0 bytes local)
3. Builds and installs `llm-router` binary to `~/bin` or `/usr/local/bin`
4. Creates config at `~/.config/llm-router/config.yaml`
5. Adds permissions and instructions to Claude Code settings (global or project)

**Prerequisite:** Sign in at [ollama.com](https://ollama.com) and set your API key:
```bash
export OLLAMA_API_KEY="your-key-here"
```

**Global install** writes to `~/.claude/settings.json` and `~/.claude/CLAUDE.md` — every Claude Code instance on your machine sees it.

**Project install** writes to `.claude/settings.json` and `CLAUDE.md` in the current repo — only that project's sessions see it.

## Usage

### CLI
```bash
# Route a task (auto-selects best model for category)
llm-router route --task summarise --input "$(cat long-file.md)"
llm-router route --task simple-code --input "Write a Go function that..."
llm-router route --task complex-code --input "Refactor this service to..."

# Override the model
llm-router route --task simple-code --model ollama:large --input "..."

# Natural language (auto-classifies category)
llm-router ask "summarise this README" < README.md

# Check routing health
llm-router health

# View routing stats and benchmark data
llm-router stats
```

### From Claude Code agents
```bash
# Check Ollama is up before routing (add to session start)
llm-router health 2>&1 | grep -q "healthy" || (ollama serve &>/dev/null & sleep 3)

# Route a task
llm-router route --task simple-code --input "..."

# Record quality after the call
llm-router record --category simple-code --model ollama:small --quality 8 --latency 7.0
```

### As a library (Go)
```go
r := router.New(config)
result, err := r.Route(ctx, router.Task{
    Category: "summarise",
    Input:    fileContents,
})
// result.Output, result.Model, result.Tokens, result.Latency
```

## Architecture

```
cmd/router/          → CLI entrypoint
internal/
  router/            → Task classification and routing logic
  benchmark/         → Benchmark runner and analysis
  ollama/            → Ollama API client
  claude/            → Claude API client
  config/            → Configuration loading
benchmarks/          → Benchmark results (JSONL)
scripts/             → Setup and utility scripts
config.example.yaml  → Example configuration
```
