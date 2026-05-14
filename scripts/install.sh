#!/bin/bash
set -euo pipefail

echo "=== llm-router install ==="

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# 1. Install Ollama if not present
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

# 2. Start Ollama if not running
if ! curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
    echo "Starting Ollama..."
    ollama serve &>/dev/null &
    sleep 3
fi

# 3. Pull default model
echo "Pulling llama3.1:8b..."
ollama pull llama3.1:8b

# 4. Build the Go binary
echo "Building llm-router..."
cd "$REPO_DIR"
go build -o llm-router ./cmd/router/

# 5. Install to /usr/local/bin
echo "Installing to /usr/local/bin/llm-router..."
sudo cp llm-router /usr/local/bin/llm-router
sudo chmod +x /usr/local/bin/llm-router

# 6. Create config if not exists
CONFIG_DIR="$HOME/.config/llm-router"
mkdir -p "$CONFIG_DIR"
if [ ! -f "$CONFIG_DIR/config.yaml" ]; then
    cp config.example.yaml "$CONFIG_DIR/config.yaml"
    echo "✓ Config created at $CONFIG_DIR/config.yaml"
    echo "  → Set ANTHROPIC_API_KEY in your environment"
else
    echo "✓ Config already exists at $CONFIG_DIR/config.yaml"
fi

# 7. Create benchmarks dir
mkdir -p "$CONFIG_DIR/benchmarks"

echo ""
echo "=== Installed ==="
echo "  Binary:     /usr/local/bin/llm-router"
echo "  Config:     $CONFIG_DIR/config.yaml"
echo "  Benchmarks: $CONFIG_DIR/benchmarks/"
echo ""
echo "Usage:"
echo "  llm-router route --task summarise --input 'text here'"
echo "  llm-router stats"
echo "  llm-router health"
