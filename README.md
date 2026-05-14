# llm-router

Intelligent LLM task router. Claude for planning and heavy thinking, Ollama for bulk work. Self-benchmarking — learns over time which model is best for which task type.

## Concept

```
Claude Code (planning, reasoning, architecture)
    │
    ├─ Complex task → stays on Claude
    │
    └─ Simple task → routed to Ollama (local, free)
        │
        ├─ summarise this file
        ├─ extract JSON from this text
        ├─ format this code
        ├─ classify this input
        └─ generate a simple function
```

## Why

Claude is excellent at complex reasoning but expensive for bulk operations. Local models (Llama 3.1 8B/70B via Ollama) handle simple tasks well at zero marginal cost. The router automatically directs each task to the cheapest model that can do it well.

## Task Classification

| Category | Complexity | Default Route | Examples |
|---|---|---|---|
| `summarise` | Low | Ollama 8B | Summarise a file, condense notes |
| `extract` | Low | Ollama 8B | Pull JSON from text, parse structured data |
| `classify` | Low | Ollama 8B | Sentiment analysis, categorisation |
| `format` | Low | Ollama 8B | Reformat code, convert markdown |
| `simple-code` | Medium | Ollama 70B | Single function, simple script |
| `rewrite` | Medium | Ollama 70B | Rewrite text, change tone |
| `explain` | Medium | Ollama 70B | Explain a concept, document code |
| `complex-code` | High | Claude Sonnet | Multi-file changes, refactoring |
| `reason` | High | Claude Opus | Architecture, planning, trade-offs |
| `agent` | High | Claude Opus | Multi-step tool use, decisions |

## Self-Improving Benchmarks

Every routed task is scored:
1. **Quality** — did the output meet the requirement? (0-10, scored by Claude on a sample)
2. **Cost** — tokens used × rate
3. **Latency** — time to completion

Results are logged to `benchmarks/results.jsonl`. The router periodically analyses this data and adjusts routing thresholds. If Ollama 8B is consistently scoring 8+ on `explain` tasks, it gets promoted. If it's scoring 4 on `simple-code`, that category gets bumped to 70B or Claude.

## Setup

```bash
# Install Ollama
./scripts/setup.sh

# Pull default models
ollama pull llama3.1:8b
ollama pull llama3.1:70b  # optional, needs 40GB+ RAM

# Configure
cp config.example.yaml config.yaml
# Edit config.yaml with your Claude API key

# Run
go run ./cmd/router/
```

## Usage

### CLI
```bash
# Route a task
llm-router route --task "summarise" --input "$(cat long-file.md)"

# Route with explicit model override
llm-router route --task "summarise" --model ollama:llama3.1:8b --input "..."

# Run benchmarks
llm-router benchmark --category summarise

# View routing stats
llm-router stats
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

### From Claude Code
Claude Code agents can shell out to the router for bulk tasks:
```bash
llm-router route --task "extract" --input "$DATA" --format json
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
