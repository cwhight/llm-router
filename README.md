# llm-router

Intelligent LLM task router. Routes bulk prose and code tasks to a fast cloud model via Ollama, reserving Claude for planning, reasoning, and architecture. Self-benchmarking — learns which model performs best per task type.

## Concept

```
Claude Code (planning, reasoning, architecture)
    │
    ├─ Needs multi-file context or architecture reasoning → stays on Claude
    │
    └─ Self-contained task → routed via Ollama (cloud model)
        │
        ├─ summarise this file          → ollama:small
        ├─ extract JSON from text       → ollama:small
        ├─ write a Go function          → ollama:small
        ├─ write a React component      → ollama:small
        ├─ write a ticket description   → ollama:small
        └─ rewrite this copy            → ollama:small
```

## Why

Claude is expensive for bulk operations. With `gpt-oss:120b-cloud` routed through a local Ollama proxy, you get a capable 120B model at near-zero cost for self-contained tasks. The router benchmarks each model per category and promotes/demotes based on observed quality. Everything except open-ended reasoning and agent orchestration defaults to the cloud model.

## Task Classification

| Category | Default Route | Benchmarked Quality | Examples |
|---|---|---|---|
| `summarise` | `ollama:small` | 9.0 | Summarise a file, condense notes |
| `extract` | `ollama:small` | 9.0 | Pull JSON from text, parse structured data |
| `classify` | `ollama:small` | 9.0 | Sentiment analysis, categorisation |
| `format` | `ollama:small` | 9.0 | Reformat code, convert to snake_case |
| `rewrite` | `ollama:small` | 9.0 | Rewrite text, improve copy |
| `explain` | `ollama:small` | 9.0 | Explain a concept, document code |
| `simple-code` | `ollama:small` | 8.0 | Single function, simple script |
| `complex-code` | `ollama:small` | 8.0 | Multi-step handlers, middleware, transactions |
| `reason` | `claude:opus` | — | Architecture, planning, trade-offs |
| `agent` | `claude:default` | — | Multi-step tool use, decisions |

## Self-Improving Benchmarks

Every routed task is scored:
1. **Quality** — did the output meet the requirement? (0-10, scored by Claude on a sample)
2. **Cost** — tokens used × rate
3. **Latency** — time to completion

Results are logged to `benchmarks/results.jsonl`. The router periodically analyses this data and adjusts routing thresholds. If Ollama 8B is consistently scoring 8+ on `explain` tasks, it gets promoted. If it's scoring 4 on `simple-code`, that category gets bumped to 70B or Claude.

## Install

```bash
git clone https://github.com/cwhight/llm-router.git
cd llm-router

# Global — every Claude Code session on your machine uses llm-router
./scripts/install.sh --global

# Project — only the current repo's Claude Code sessions use llm-router
./scripts/install.sh --project
```

The installer builds and installs the `llm-router` binary, creates config at `~/.config/llm-router/config.yaml`, and wires up Claude Code settings.

Set your Ollama cloud API key:
```bash
export OLLAMA_API_KEY="your-key-here"
```

Or add to `~/.config/llm-router/config.yaml`:
```yaml
ollama:
  host: "http://localhost:11434"
  api_key: "${OLLAMA_API_KEY}"
  models:
    small: "gpt-oss:120b-cloud"
    large: "gpt-oss:120b-cloud"
```

## Usage

### CLI
```bash
# Route a task — always use explicit --task, not llm-router ask
llm-router route --task summarise --input "$(cat long-file.md)"
llm-router route --task simple-code --input "Write a Go handler that..."
llm-router route --task rewrite --input "Improve this copy: ..."
llm-router route --task complex-code --input "Write a pgx transaction that..."

# Override the model
llm-router route --task simple-code --model ollama:small --input "..."

# View routing stats (sorted by call count)
llm-router stats

# Check health
llm-router health
```

**Do not use `llm-router ask`** — it auto-classifies unreliably and stats will be miscategorised. Always name the task explicitly with `--task`.

### From Claude Code agents
```bash
export PATH="$HOME/bin:$PATH"
llm-router route --task rewrite --input "Write a ticket description for: [scope]"
llm-router record --category rewrite --model ollama:small --quality 8 --latency 4.2
```

## Routing Enforcement Hook

`hooks/enforce-routing.py` is a Claude Code PostToolUse hook that warns when substantial code or prose (>20 lines of `.go/.ts/.tsx/.md/.sql`) is written without a recent llm-router call.

Add to `~/.claude/settings.json`:
```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "python3 /path/to/hooks/enforce-routing.py"
          }
        ]
      }
    ]
  }
}
```

Output:
- `✓ handler.go (42 lines) — routed 8s ago via ollama`
- `⚠ handler.go (42 lines) — last llm-router call was 180s ago. Route this through llm-router before writing.`

## Architecture

```
cmd/router/          → CLI entrypoint
internal/
  router/            → Task classification and routing logic
  benchmark/         → Benchmark runner and analysis
  ollama/            → Ollama API client (supports api_key for cloud models)
  claude/            → Claude API client
  config/            → Configuration loading
hooks/
  enforce-routing.py → Claude Code PostToolUse enforcement hook
benchmarks/          → Benchmark results (JSONL)
scripts/             → Setup and utility scripts
config.example.yaml  → Example configuration
```
