#!/bin/bash
set -euo pipefail

SCOPE="prompt"

for arg in "$@"; do
    case $arg in
        --global) SCOPE="global" ;;
        --project) SCOPE="project" ;;
        --help|-h) usage; exit 0 ;;
    esac
done

usage() {
    cat <<'USAGE'
llm-router installer

Usage: ./scripts/install.sh [--global|--project]

Options:
  --global   Install llm-router and configure it for ALL Claude Code sessions
             (writes to ~/.claude/settings.json and ~/.claude/CLAUDE.md)

  --project  Install llm-router and configure it for THIS project only
             (writes to .claude/settings.json and CLAUDE.md in current repo)

  (no flag)  Prompts you to choose

What it does:
  1. Installs Ollama (if not present)
  2. Pulls llama3.1:8b model
  3. Builds and installs llm-router binary to /usr/local/bin
  4. Creates config at ~/.config/llm-router/config.yaml
  5. Adds llm-router permissions and instructions to Claude Code settings
USAGE
}

echo "=== llm-router install ==="
echo ""

# ── 1. Ask scope if not specified ────────────────────────────────
if [ "$SCOPE" = "prompt" ]; then
    echo "How do you want to configure Claude Code integration?"
    echo ""
    echo "  1) Global  — every Claude Code session uses llm-router automatically"
    echo "  2) Project — only this repo's Claude Code sessions use llm-router"
    echo ""
    read -p "Choose (1/2): " choice
    case $choice in
        1) SCOPE="global" ;;
        2) SCOPE="project" ;;
        *) echo "Invalid choice"; exit 1 ;;
    esac
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# ── 2. Install Ollama ────────────────────────────────────────────
echo ""
echo "Checking Ollama..."

if command -v ollama &> /dev/null; then
    echo "✓ Ollama installed"
else
    echo "Installing Ollama..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        brew install ollama
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        curl -fsSL https://ollama.com/install.sh | sh
    else
        echo "✗ Unsupported OS. Install Ollama manually: https://ollama.com/download"
        exit 1
    fi
fi

# Start Ollama if not running
if ! curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
    echo "Starting Ollama..."
    ollama serve &>/dev/null &
    sleep 3
fi

# Set Ollama to start at login (macOS)
if [[ "$OSTYPE" == "darwin"* ]] && command -v brew &>/dev/null; then
    if ! brew services list 2>/dev/null | grep -q "ollama.*started"; then
        echo "Configuring Ollama to start at login..."
        brew services start ollama 2>/dev/null || true
    else
        echo "✓ Ollama configured to start at login"
    fi
fi

# Pull cloud routing models (manifest-only, no local GPU needed)
# These are free-tier Ollama cloud models — requires OLLAMA_API_KEY
if [ -z "${OLLAMA_API_KEY:-}" ]; then
    echo "⚠ OLLAMA_API_KEY not set — cloud models will fail"
    echo "  Sign in at https://ollama.com and set OLLAMA_API_KEY in your environment"
fi

CLOUD_MODELS=("qwen3-coder-next:cloud" "devstral-2:123b-cloud" "gpt-oss:120b-cloud")
for model in "${CLOUD_MODELS[@]}"; do
    if ollama list 2>/dev/null | grep -q "$(echo "$model" | cut -d: -f1)"; then
        echo "✓ $model available"
    else
        echo "Pulling $model..."
        ollama pull "$model" 2>&1 || echo "  ✗ Failed — check OLLAMA_API_KEY"
    fi
done

# ── 3. Build and install binary ──────────────────────────────────
echo ""
echo "Building llm-router..."

if ! command -v go &> /dev/null; then
    echo "✗ Go not found. Install: https://go.dev/dl/"
    exit 1
fi

cd "$REPO_DIR"
go mod tidy
go build -o llm-router ./cmd/router/

if sudo -n true 2>/dev/null; then
    INSTALL_PATH="/usr/local/bin/llm-router"
    echo "Installing to $INSTALL_PATH..."
    sudo cp llm-router "$INSTALL_PATH"
    sudo chmod +x "$INSTALL_PATH"
else
    INSTALL_PATH="$HOME/bin/llm-router"
    echo "Installing to $INSTALL_PATH (no sudo)..."
    mkdir -p "$HOME/bin"
    cp llm-router "$INSTALL_PATH"
    chmod +x "$INSTALL_PATH"
    if ! echo "$PATH" | grep -q "$HOME/bin"; then
        echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.zshrc"
        echo "  Added ~/bin to PATH in ~/.zshrc"
    fi
fi
rm llm-router

# ── 4. Create config ─────────────────────────────────────────────
CONFIG_DIR="$HOME/.config/llm-router"
mkdir -p "$CONFIG_DIR/benchmarks"

if [ ! -f "$CONFIG_DIR/config.yaml" ]; then
    cp config.example.yaml "$CONFIG_DIR/config.yaml"
    echo "✓ Config created at $CONFIG_DIR/config.yaml"
else
    echo "✓ Config already exists at $CONFIG_DIR/config.yaml"
fi

# ── 5. Configure Claude Code ─────────────────────────────────────
echo ""
echo "Configuring Claude Code ($SCOPE)..."

LLM_ROUTER_INSTRUCTIONS='## Cost-Aware Model Routing

Route code generation to cheaper models when the generated code is longer than the prompt needed to specify it. If the prompt would be longer than the code, just write it directly.

**Rule of thumb:** <20 lines of code — write directly. 20+ lines of repetitive/mechanical code — route cheaper.

**Tiers (cheapest first):**
1. **Ollama** ($0) — prose, summaries, extraction → `LLM_ROUTER_BIN route --task simple-code --input "..."`
2. **Haiku subagent** — mechanical code gen with a precise spec (20+ lines) → `Agent({ model: "haiku", ... })`
3. **Sonnet subagent** — code gen needing context reasoning (20+ lines) → `Agent({ model: "sonnet", ... })`
4. **Opus (direct)** — architecture, investigation, short edits, anything where the prompt would be longer than the code

**After every subagent or Ollama call**, record the result:
```bash
LLM_ROUTER_BIN record --category simple-code --model claude:haiku --quality 9 --latency 3.5
```

**Hooks are watching.** Every Edit/Write and Agent call is logged to ~/.claude/model-discipline.log.'

if [ "$SCOPE" = "global" ]; then
    SETTINGS_FILE="$HOME/.claude/settings.json"
    CLAUDE_MD="$HOME/.claude/CLAUDE.md"
    mkdir -p "$HOME/.claude"
else
    SETTINGS_FILE=".claude/settings.json"
    CLAUDE_MD="CLAUDE.md"
    mkdir -p ".claude"
fi

# Add permissions and hooks
python3 -c "
import json, os

path = '$SETTINGS_FILE'
if os.path.exists(path):
    with open(path) as f:
        data = json.load(f)
else:
    data = {}

# Permissions
perms = data.setdefault('permissions', {}).setdefault('allow', [])
for p in ['Bash(llm-router:*)', 'Bash(ollama:*)']:
    if p not in perms:
        perms.append(p)

# Hooks
hooks = data.setdefault('hooks', {})
post = hooks.setdefault('PostToolUse', [])

# Check if our hooks already exist
has_edit_hook = any(h.get('matcher') == 'Write|Edit' for h in post)
has_agent_hook = any(h.get('matcher') == 'Agent' for h in post)

if not has_edit_hook:
    post.append({
        'matcher': 'Write|Edit',
        'hooks': [{
            'type': 'command',
            'command': 'jq -r \'\"[\" + (now | todate) + \"] DIRECT_WRITE \" + (.tool_input.file_path // \"unknown\")\' >> ~/.claude/model-discipline.log',
            'async': True
        }]
    })

if not has_agent_hook:
    post.append({
        'matcher': 'Agent',
        'hooks': [
            {
                'type': 'command',
                'command': 'jq -r \'\"[\" + (now | todate) + \"] SUBAGENT model=\" + (.tool_input.model // \"opus-default\") + \" desc=\" + (.tool_input.description // \"unknown\")\' >> ~/.claude/model-discipline.log',
                'async': True
            },
            {
                'type': 'command',
                'command': 'jq -r \'\"claude:\" + (.tool_input.model // \"opus-default\") + \" \" + (((.tool_response.duration_ms // 0) / 1000) | tostring)\' | { read -r model latency; $INSTALL_PATH record --category simple-code --model \"\\\$model\" --quality 8 --latency \"\\\$latency\"; } 2>/dev/null || true',
                'async': True
            }
        ]
    })

with open(path, 'w') as f:
    json.dump(data, f, indent=2)
"
echo "✓ Added permissions and hooks to $SETTINGS_FILE"

INSTRUCTIONS_RESOLVED="${LLM_ROUTER_INSTRUCTIONS//LLM_ROUTER_BIN/$INSTALL_PATH}"

if [ -f "$CLAUDE_MD" ]; then
    if ! grep -q "Cost-Aware Model Routing" "$CLAUDE_MD"; then
        echo "" >> "$CLAUDE_MD"
        echo "$INSTRUCTIONS_RESOLVED" >> "$CLAUDE_MD"
        echo "✓ Added llm-router instructions to $CLAUDE_MD"
    else
        echo "✓ Instructions already present in $CLAUDE_MD"
    fi
else
    echo "$INSTRUCTIONS_RESOLVED" > "$CLAUDE_MD"
    echo "✓ Created $CLAUDE_MD with llm-router instructions"
fi

# ── 6. Verify ─────────────────────────────────────────────────────
echo ""
echo "Verifying installation..."

if llm-router health 2>/dev/null; then
    echo "✓ llm-router healthy"
else
    echo "⚠ Ollama not reachable — llm-router will fall back to Claude"
fi

echo ""
echo "=== Installed ($SCOPE) ==="
echo ""
echo "  Binary:      $INSTALL_PATH"
echo "  Config:      $CONFIG_DIR/config.yaml"
echo "  Benchmarks:  $CONFIG_DIR/benchmarks/"
echo "  Claude Code: $SETTINGS_FILE"
echo "  Instructions: $CLAUDE_MD"
echo ""
echo "Usage:"
echo "  llm-router ask 'summarise this README' < README.md"
echo "  llm-router route --task extract --input 'text' --format json"
echo "  llm-router stats"
echo ""
echo "Routing tiers (all free via Ollama cloud — no local GPU needed):"
echo "  ollama:small   qwen3-coder-next:cloud (80B)   — simple-code, format"
echo "  ollama:large   devstral-2:123b-cloud  (123B)  — complex-code"
echo "  ollama:general gpt-oss:120b-cloud     (117B)  — prose, summarise, rewrite"
