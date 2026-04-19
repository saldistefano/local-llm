#!/usr/bin/env zsh
# install.sh — Local LLM setup for Apple Silicon Mac
#
# Tested on: M4 Pro (48GB), M4 Max (Mac Studio)
# Requirements: macOS Sequoia+, Homebrew, ~15GB free disk space
#
# Usage:
#   git clone https://github.com/saldistefano/local-llm.git
#   cd local-llm
#   ./install.sh

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo "${BLUE}▶${NC} $1"; }
success() { echo "${GREEN}✓${NC} $1"; }
warn()    { echo "${YELLOW}⚠${NC}  $1"; }
error()   { echo "${RED}✗${NC} $1"; exit 1; }

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

echo ""
echo "  Local LLM Setup — Apple Silicon"
echo "  ================================"
echo ""

# ── 1. Check prerequisites ────────────────────────────────────────────────────
info "Checking prerequisites..."

if [[ "$(uname -m)" != "arm64" ]]; then
  error "This setup requires Apple Silicon (arm64). Detected: $(uname -m)"
fi

if ! command -v brew &>/dev/null; then
  error "Homebrew not found. Install it first: https://brew.sh"
fi

success "Apple Silicon confirmed, Homebrew found"

# ── 2. Install Ollama ─────────────────────────────────────────────────────────
info "Installing Ollama (includes MLX for Apple Silicon)..."

if command -v ollama &>/dev/null; then
  CURRENT=$(ollama --version 2>/dev/null | awk '{print $NF}' || echo "unknown")
  warn "Ollama already installed (version: $CURRENT). Skipping brew install."
  warn "To upgrade: brew upgrade ollama"
else
  brew install ollama
  success "Ollama installed"
fi

# ── 3. Install launchd service ────────────────────────────────────────────────
info "Installing Ollama background service with performance tuning..."

PLIST_SRC="$REPO_DIR/launchd/homebrew.mxcl.ollama.plist"
PLIST_DEST="$HOME/Library/LaunchAgents/homebrew.mxcl.ollama.plist"

# Unload existing service if present
if launchctl list | grep -q "homebrew.mxcl.ollama" 2>/dev/null; then
  warn "Existing Ollama service found — unloading to replace..."
  launchctl unload "$PLIST_DEST" 2>/dev/null || true
fi

cp "$PLIST_SRC" "$PLIST_DEST"
launchctl load "$PLIST_DEST"

# Wait for Ollama to be ready
info "Waiting for Ollama to start..."
for i in $(seq 1 15); do
  if ollama list &>/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if ! ollama list &>/dev/null 2>&1; then
  error "Ollama failed to start. Check logs: tail -f /opt/homebrew/var/log/ollama.log"
fi

success "Ollama service running with performance tuning"

# ── 4. Pull models ────────────────────────────────────────────────────────────
info "Pulling Qwen3.6 35B-A3B Q4_K_M (~24 GB) — MoE: 35B quality at 3B compute cost..."
ollama pull qwen3.6:35b-a3b-q4_K_M
success "qwen3.6:35b-a3b-q4_K_M downloaded"

info "Pulling Qwen2.5-Coder 7B (~4.7 GB) — fast model for quick queries..."
ollama pull qwen2.5-coder:7b
success "qwen2.5-coder:7b downloaded"

info "Pulling nomic-embed-text for codebase embeddings (~274 MB)..."
ollama pull nomic-embed-text
success "nomic-embed-text downloaded"

# ── 5. Create tuned modelfiles ────────────────────────────────────────────────
info "Creating tuned model variants (qwen-coder-35b, qwen-coder-7b)..."

mkdir -p "$HOME/.ollama/modelfiles"
cp "$REPO_DIR/modelfiles/Modelfile.qwen36" "$HOME/.ollama/modelfiles/"
cp "$REPO_DIR/modelfiles/Modelfile.qwen7b" "$HOME/.ollama/modelfiles/"

ollama create qwen-coder-35b -f "$HOME/.ollama/modelfiles/Modelfile.qwen36"
ollama create qwen-coder-7b  -f "$HOME/.ollama/modelfiles/Modelfile.qwen7b"

success "Tuned models created"

# ── 6. Set up Continue.dev config ────────────────────────────────────────────
info "Installing Continue.dev config (~/.continue/config.json)..."

mkdir -p "$HOME/.continue"

if [[ -f "$HOME/.continue/config.json" ]]; then
  BACKUP="$HOME/.continue/config.json.bak.$(date +%Y%m%d%H%M%S)"
  warn "Existing config.json found — backed up to $BACKUP"
  cp "$HOME/.continue/config.json" "$BACKUP"
fi

cp "$REPO_DIR/continue/config.json" "$HOME/.continue/config.json"
success "Continue.dev config installed"

# ── 7. Install llm-switch script ─────────────────────────────────────────────
info "Installing llm-switch to ~/bin/..."

mkdir -p "$HOME/bin"
cp "$REPO_DIR/bin/llm-switch" "$HOME/bin/llm-switch"
chmod +x "$HOME/bin/llm-switch"
success "llm-switch installed"

# ── 8. Shell aliases ──────────────────────────────────────────────────────────
info "Adding shell aliases to ~/.zshrc..."

MARKER="# ── Local LLM (Ollama)"
if grep -q "$MARKER" "$HOME/.zshrc" 2>/dev/null; then
  warn "Local LLM aliases already present in ~/.zshrc — skipping."
else
  echo "" >> "$HOME/.zshrc"
  cat "$REPO_DIR/shell/zshrc-additions.sh" >> "$HOME/.zshrc"
  success "Aliases added to ~/.zshrc"
fi

# ── 9. Verify GPU usage ───────────────────────────────────────────────────────
info "Running a quick inference test to verify GPU is active..."

ollama run qwen-coder-7b "Say: setup complete" --nowordwrap 2>/dev/null | head -3 || true

GPU_STATUS=$(ollama ps 2>/dev/null | grep "qwen-coder-7b" | awk '{print $5, $6}')
if [[ "$GPU_STATUS" == *"GPU"* ]]; then
  success "GPU confirmed: $GPU_STATUS"
else
  warn "Could not confirm GPU status. Run 'ollama ps' after your first query."
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "  ${GREEN}Setup complete!${NC}"
echo ""
echo "  Reload your shell to activate aliases:"
echo "    source ~/.zshrc"
echo ""
echo "  Quick start:"
echo "    qc          → chat with 14B model (~25-30 tok/s)"
echo "    qcf         → chat with 7B model  (~50-60 tok/s)"
echo "    llm local   → switch Claude Code to local Ollama"
echo "    llm cloud   → switch back to Anthropic API"
echo "    llm status  → show current backend + models"
echo ""
echo "  VS Code: install the 'Continue' extension (by continue.dev)"
echo "  Config is already in place at ~/.continue/config.json"
echo ""
