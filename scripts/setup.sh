#!/bin/bash
set -euo pipefail

echo "=== llm-router setup ==="

# Check for Ollama
if command -v ollama &> /dev/null; then
    echo "✓ Ollama already installed ($(ollama --version))"
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
    echo "✓ Ollama installed"
fi

# Start Ollama if not running
if ! curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
    echo "Starting Ollama..."
    ollama serve &
    sleep 3
fi

# Pull default model
echo "Pulling llama3.1:8b (4.7GB)..."
ollama pull llama3.1:8b

echo ""
echo "Optional: pull the 70B model for higher quality (requires 40GB+ RAM):"
echo "  ollama pull llama3.1:70b"
echo ""

# Check for Go
if command -v go &> /dev/null; then
    echo "✓ Go $(go version | awk '{print $3}')"
else
    echo "✗ Go not found. Install: https://go.dev/dl/"
    exit 1
fi

# Copy config if needed
if [ ! -f config.yaml ]; then
    cp config.example.yaml config.yaml
    echo "✓ Created config.yaml from template — edit with your Claude API key"
else
    echo "✓ config.yaml already exists"
fi

echo ""
echo "=== Setup complete ==="
echo "Next steps:"
echo "  1. Set ANTHROPIC_API_KEY in your environment or config.yaml"
echo "  2. Run: go run ./cmd/router/ route --task summarise --input 'test'"
