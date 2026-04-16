# Local LLM Setup — Apple Silicon

A local AI coding assistant that runs entirely on your machine. No API key, no cost, no rate limits. Used as a fallback when Claude API limits are hit, or anytime you want fast, private code assistance.

Tested on M4 Pro (48GB) and designed for M4 Max (Mac Studio). Requires Apple Silicon and macOS Sequoia+.

## Install

```zsh
git clone https://github.com/saldistefano/local-llm.git
cd local-llm
./install.sh
source ~/.zshrc
```

The script installs Ollama, pulls both models (~14GB total), creates tuned model variants, configures the background service, and adds shell aliases. Takes 5–15 minutes depending on download speed.

---

---

## How it works

```
Your terminal / VS Code
        │
        ▼
   Ollama server          ← runs as a background service, auto-starts at login
   localhost:11434        ← exposes both Anthropic and OpenAI compatible APIs
        │
        ▼
  Apple Metal GPU         ← 100% of inference runs on the M4 Pro GPU
  (via MLX framework)     ← Apple's own ML framework, fastest on Apple Silicon
        │
        ▼
  Qwen2.5-Coder model     ← open-source code model loaded into unified memory
  (14B or 7B parameters)
```

**Why it's fast**: Apple's M4 Pro has 48GB of unified memory shared between CPU and GPU, and 273 GB/s of memory bandwidth. Unlike a PC with a discrete GPU, there's no slow PCIe transfer — the model lives in the same memory pool the GPU reads directly. Ollama uses Apple's MLX framework under the hood, which is specifically optimized for this architecture.

**Why Qwen2.5-Coder**: As of early 2026 it scores higher than GPT-4 on standard code benchmarks (88% HumanEval). It supports 92 programming languages and has a 32k token context window, which is enough for most code files.

---

## What's installed

| Component | Version | Purpose |
|-----------|---------|---------|
| Ollama | 0.20.7 | Model server — manages models, serves API |
| MLX | 0.31.1 | Apple Silicon inference backend (installed as Ollama dependency) |
| qwen-coder-14b | 9 GB | Primary model — best quality, ~25–30 tok/s |
| qwen-coder-7b | 4.7 GB | Fast model — quick questions, ~50–60 tok/s |
| nomic-embed-text | 274 MB | Embeddings — used by Continue.dev for codebase search |

### Performance tuning applied

Three environment variables are set in the Ollama launchd service (`~/Library/LaunchAgents/homebrew.mxcl.ollama.plist`):

| Variable | Value | Effect |
|----------|-------|--------|
| `OLLAMA_FLASH_ATTENTION` | `1` | Faster attention computation, especially on long prompts |
| `OLLAMA_KV_CACHE_TYPE` | `q8_0` | Quantized key-value cache — saves ~40% memory with negligible quality loss |
| `OLLAMA_NUM_PARALLEL` | `1` | Dedicate all resources to one request at a time (you're the only user) |

The models themselves are tuned via Modelfiles (`~/.ollama/modelfiles/`):
- All layers offloaded to GPU (`num_gpu 99`)
- Low temperature (`0.1`) for deterministic, consistent code output
- 32k context for 14B, 16k for 7B

---

## Daily usage

### Option 1 — Terminal chat

After opening a new terminal (or running `source ~/.zshrc`):

```zsh
qc          # start chatting with the 14B model (primary)
qcf         # start chatting with the 7B model (faster)
```

Type your question, press Enter. Type `/bye` or Ctrl+D to exit.

Example:
```
$ qc
>>> Explain what this Go error means: "assignment to entry in nil map"
```

### Option 2 — Claude Code CLI (local mode)

When you've hit your Claude API limits and want to keep using the `claude` command:

```zsh
llm local      # switch to local Ollama
claude         # now runs against your local model

# when you're done / limits reset:
llm cloud      # switch back to Anthropic API
claude         # back to full Claude
```

**What works in local mode:**
- Code questions and explanations
- Generating new code
- Reviewing code you paste in
- Debugging help

**What doesn't work in local mode:**
- File editing (the agent can't read/write your files)
- Running bash commands
- Multi-step agentic tasks

This is because those tools require Anthropic's authentication to authorize. Local mode is essentially a smart chatbot, not a full coding agent.

### Option 3 — VS Code with Continue.dev

Install the **Continue** extension from the VS Code marketplace (search "Continue" by continue.dev).

Once installed it reads `~/.continue/config.json` automatically. You get:

- **Chat panel** (Cmd+L) — ask questions about code, paste snippets, get explanations
- **Inline edit** (Cmd+I) — select code, describe a change, model edits it in place
- **Autocomplete** — the 7B model suggests completions as you type (faster than 14B)
- **@codebase** — indexes your project with embeddings so you can ask "where is X handled?"

Everything runs locally. No data leaves your machine.

---

## Checking status

```zsh
llm status          # shows current backend (local vs cloud) + models available

ollama ps           # shows which model is loaded and GPU usage
                    # e.g.: qwen-coder-7b ... 5.8 GB    100% GPU

ollama list         # shows all downloaded models and sizes
```

---

## Switching between local and cloud

The `llm` function in your shell sets environment variables that Claude Code reads:

```zsh
llm local
# sets: ANTHROPIC_BASE_URL=http://localhost:11434
#       ANTHROPIC_API_KEY=ollama
# effect: claude CLI talks to Ollama instead of Anthropic

llm cloud
# unsets: ANTHROPIC_BASE_URL, ANTHROPIC_API_KEY
# effect: claude CLI goes back to normal Anthropic API
```

These changes apply to your current terminal session only. Opening a new terminal tab always starts in cloud mode (default).

If you want a one-off without affecting the session:
```zsh
claude-local        # runs claude against local Ollama, doesn't change env vars
```

---

## Managing Ollama

Ollama runs as a background service that starts automatically at login.

```zsh
# Start / stop / restart
brew services start ollama
brew services stop ollama
brew services restart ollama

# View logs (useful if something isn't working)
tail -f /opt/homebrew/var/log/ollama.log

# Pull a new model
ollama pull <model-name>

# Remove a model (free disk space)
ollama rm <model-name>

# Run a quick one-off query without entering interactive mode
ollama run qwen-coder-14b "What does this regex do: ^(?=.*[A-Z])(?=.*\d).{8,}$"
```

---

## Files created by this setup

| File | Purpose |
|------|---------|
| `~/Library/LaunchAgents/homebrew.mxcl.ollama.plist` | Ollama background service with performance env vars |
| `~/.ollama/modelfiles/Modelfile.qwen14b` | Source config for the tuned 14B model |
| `~/.ollama/modelfiles/Modelfile.qwen7b` | Source config for the tuned 7B model |
| `~/.continue/config.json` | Continue.dev VS Code extension config |
| `~/bin/llm-switch` | Script that prints export commands for llm local/cloud |
| `~/.zshrc` (appended) | `llm()`, `qc`, `qcf`, `claude-local` aliases |

---

## Troubleshooting

**Model is slow or not using GPU**
```zsh
ollama ps   # check PROCESSOR column — should say "100% GPU"
```
If it shows CPU, try restarting Ollama: `brew services restart ollama`

**Ollama isn't running**
```zsh
brew services start ollama
# wait a few seconds, then:
ollama list   # should respond without error
```

**`llm` command not found after opening a new terminal**
```zsh
source ~/.zshrc
```
This only needs to be done once per terminal session, or just open a new tab.

**Model loaded but responses are very slow**
Check if something else is using a lot of memory. The 14B model needs ~10GB free GPU memory. Check Activity Monitor → Memory tab.

**Want to update Ollama**
```zsh
brew upgrade ollama
brew services restart ollama
```

---

## Adding models later

Browse available models at [ollama.com/library](https://ollama.com/library). Good ones to try for code:

| Model | Size | Notes |
|-------|------|-------|
| `qwen2.5-coder:32b` | ~20GB | Higher quality, ~12 tok/s — try if 14B feels limiting |
| `deepseek-coder-v2` | varies | Strong alternative to Qwen for code |
| `codellama:13b` | ~8GB | Meta's dedicated code model |
| `mistral:7b` | ~4.1GB | Good general model, very fast |

To add one:
```zsh
ollama pull qwen2.5-coder:32b
# then add it to ~/.continue/config.json if you want it in VS Code
```
