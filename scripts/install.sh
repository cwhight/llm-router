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

# Pull model
if ! ollama list 2>/dev/null | grep -q "llama3.1:8b"; then
    echo "Pulling llama3.1:8b (4.7GB)..."
    ollama pull llama3.1:8b
else
    echo "✓ llama3.1:8b available"
fi

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
    echo "Installing to /usr/local/bin/llm-router..."
    sudo cp llm-router /usr/local/bin/llm-router
    sudo chmod +x /usr/local/bin/llm-router
else
    echo "Installing to ~/bin/llm-router (no sudo)..."
    mkdir -p "$HOME/bin"
    cp llm-router "$HOME/bin/llm-router"
    chmod +x "$HOME/bin/llm-router"
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

LLM_ROUTER_INSTRUCTIONS='# LLM Router

`llm-router` is installed locally and routes simple tasks to Ollama (free, local) instead of using Claude tokens. Use it for bulk, low-complexity work.

**Use llm-router for:**
- Summarising files or text: `llm-router ask "summarise this" < file.md`
- Extracting structured data: `llm-router route --task extract --input "text" --format json`
- Formatting or reformatting: `llm-router route --task format --input "text"`
- Classification: `llm-router route --task classify --input "text"`
- Simple explanations: `llm-router ask "explain what this does" < snippet.go`
- Simple code generation: `llm-router route --task simple-code --input "write a function that..."`
- Writing prose from context — PR descriptions, commit messages, ADR drafts, Slack replies

**Decomposition pattern — Claude plans, Ollama executes:**

For complex tasks, Claude should read the codebase, make architectural decisions, and plan the changes. Then decompose the implementation into self-contained steps and route each one to Ollama. Claude handles tool calls (file edits, git, gh) with the results.

Example — multi-file code change:
1. Claude reads codebase, decides what needs changing and where
2. For each file, Claude writes a precise prompt with full context and routes to Ollama:
   `llm-router ask "Given this Go handler pattern: [paste existing handler], write a new handler called GetUser that calls svc.GetUser and returns the proto response"`
3. Claude takes the output, applies it via Edit tool, moves to next file

Example — PR description:
1. Claude determines the key changes and structure
2. Routes: `llm-router ask "Write a PR description in markdown. Changes: X, Y, Z. Format: Description, What changed, Why, Testing sections"`
3. Claude uses output in `gh pr edit --body`

**The rule:** if the task can be fully specified in a single prompt without needing to read files or make decisions, Ollama handles it. If it requires exploring the codebase, making judgment calls, or coordinating across files, Claude does it — then hands off the self-contained steps.

**Do NOT use llm-router for:**
- Reading/exploring the codebase — stay on Claude
- Architecture and design decisions — stay on Claude
- Complex reasoning and trade-offs — stay on Claude
- Deciding WHAT to change and WHERE — stay on Claude
- Tool calls (file edits, git, gh commands) — stay on Claude

**Transparency rule:** Before calling llm-router, always state in your response that you are routing the task to Ollama. This lets the user see when local models are being used instead of Claude.'

if [ "$SCOPE" = "global" ]; then
    SETTINGS_FILE="$HOME/.claude/settings.json"
    CLAUDE_MD="$HOME/.claude/CLAUDE.md"
    mkdir -p "$HOME/.claude"
else
    SETTINGS_FILE=".claude/settings.json"
    CLAUDE_MD="CLAUDE.md"
    mkdir -p ".claude"
fi

# Add permissions if not present
if [ -f "$SETTINGS_FILE" ]; then
    if ! grep -q "llm-router" "$SETTINGS_FILE"; then
        # Use python to safely add to the allow array
        python3 -c "
import json
with open('$SETTINGS_FILE') as f:
    data = json.load(f)
perms = data.setdefault('permissions', {}).setdefault('allow', [])
for p in ['Bash(llm-router:*)', 'Bash(ollama:*)']:
    if p not in perms:
        perms.append(p)
with open('$SETTINGS_FILE', 'w') as f:
    json.dump(data, f, indent=2)
"
        echo "✓ Added llm-router permissions to $SETTINGS_FILE"
    else
        echo "✓ Permissions already present in $SETTINGS_FILE"
    fi
else
    cat > "$SETTINGS_FILE" <<'SETTINGS'
{
  "permissions": {
    "allow": [
      "Bash(llm-router:*)",
      "Bash(ollama:*)"
    ]
  }
}
SETTINGS
    echo "✓ Created $SETTINGS_FILE with llm-router permissions"
fi

# Add instructions to CLAUDE.md
if [ -f "$CLAUDE_MD" ]; then
    if ! grep -q "llm-router" "$CLAUDE_MD"; then
        echo "" >> "$CLAUDE_MD"
        echo "$LLM_ROUTER_INSTRUCTIONS" >> "$CLAUDE_MD"
        echo "✓ Added llm-router instructions to $CLAUDE_MD"
    else
        echo "✓ Instructions already present in $CLAUDE_MD"
    fi
else
    echo "$LLM_ROUTER_INSTRUCTIONS" > "$CLAUDE_MD"
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
echo "  Binary:      /usr/local/bin/llm-router"
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
echo "Optional: pull the 70B model for better quality (needs 40GB+ RAM):"
echo "  ollama pull llama3.1:70b"
