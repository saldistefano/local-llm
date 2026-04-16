# ── Local LLM (Ollama) ─────────────────────────────────────────────────────────
# Run Claude Code CLI against local Ollama instead of Anthropic API.
# Useful when Claude API limits are hit. Tool use (file edits, bash) won't work
# in local mode — this is for code chat / generation only.
alias claude-local='ANTHROPIC_BASE_URL=http://localhost:11434 ANTHROPIC_API_KEY=ollama claude'

# Quick model chat without the full Claude Code wrapper
alias qc='ollama run qwen-coder-14b'   # primary: ~25-30 tok/s
alias qcf='ollama run qwen-coder-7b'   # fast:    ~50-60 tok/s

# Add ~/bin to PATH for llm-switch and other local scripts
export PATH="$HOME/bin:$PATH"

# Shell wrapper so eval works: llm local / llm cloud / llm status
llm() { eval "$(llm-switch ${1:-help})"; }
# ──────────────────────────────────────────────────────────────────────────────
