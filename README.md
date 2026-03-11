# Helios + Pi Team Installer

> One-command setup for the full Helios AI orchestrator stack on top of Pi CLI.

## Quick Start

```bash
curl -fsSL https://raw.githubusercontent.com/sweetcheeks72/helios-team-installer/main/bootstrap.sh | bash
```

Same command to update — it detects existing installs and skips the interactive prompts (provider, API keys). Just pulls latest code, updates extensions, refreshes deps and infrastructure.

```bash
# Or locally:
bash ~/helios-team-installer/install.sh          # update (non-interactive)
bash ~/helios-team-installer/install.sh --fresh   # re-run full setup
```

📖 **First time?** Read the [full team setup guide](TEAM-SETUP.md) — explains everything from scratch.

---

## What This Installs

| Component | Description |
|-----------|-------------|
| **Pi CLI** | The terminal AI coding harness (`@mariozechner/pi-coding-agent`) |
| **Helios Agent** | Orchestrator identity, 50+ agents, 13 skills, extensions (~/.pi/agent/) |
| **20 Git Packages** | Extensions for subagents, coordination, design deck, web access, etc. |
| **5 Local Extensions** | Governance, codebase-index, subagent-mesh, MCP startup, inline-enforce |
| **Memgraph** | Knowledge graph — Docker container, schema, 12GB memory cap |
| **Ollama** | Local embeddings — granite-embedding + qwen3-embedding models |
| **MCP Servers** | Memgraph (via uvx), GitHub, Figma (via npx) |
| **HEMA** | Episodic memory — neo4j-driver, ingest-episodes.js, memory-recall.js |
| **Provider Config** | settings.json wired to Anthropic, Bedrock, or OpenAI |
| **API Keys** | Guided .env setup with interactive prompts |
| **Familiar Skills** | Gmail, Calendar, Drive, transcription skills (optional) |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Your Terminal                             │
│                       helios "task"                              │
└────────────────────────────┬────────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────────┐
│                      Pi CLI  (npm -g)                            │
│            @mariozechner/pi-coding-agent                         │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                  ~/.pi/agent/                             │   │
│  │                                                           │   │
│  │  ┌────────────┐  ┌───────────┐  ┌───────────────────┐   │   │
│  │  │  agents/   │  │  skills/  │  │   extensions/     │   │   │
│  │  │  40+ .md   │  │  13+ SKILL│  │   5 local ext.    │   │   │
│  │  │  files     │  │  .md files│  │   (governance,    │   │   │
│  │  └────────────┘  └───────────┘  │   subagent-mesh,  │   │   │
│  │                                  │   skills-hook...) │   │   │
│  │  ┌────────────┐  ┌───────────┐  └───────────────────┘   │   │
│  │  │ settings.  │  │   .env    │                           │   │
│  │  │   json     │  │  API keys │                           │   │
│  │  └────────────┘  └───────────┘                           │   │
│  │                                  ┌───────────────────┐   │   │
│  │                                  │  bin/helios       │   │   │
│  │                                  │  (CLI wrapper)    │   │   │
│  │                                  └───────────────────┘   │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                 Git Packages (20)                         │   │
│  │  pi-subagents • pi-messenger • pi-coordination           │   │
│  │  pi-model-switch • pi-design-deck • pi-review-loop       │   │
│  │  pi-web-access • pi-interactive-shell • surf-cli  ...    │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────┬───────────────────────────────────────┘
                          │
    ┌─────────────────────┼─────────────────────┬────────────────┐
    │                     │                     │                │
┌───▼────────────┐ ┌──────▼──────┐  ┌──────────▼──┐  ┌─────────▼─────┐
│  AI Provider   │ │  MCP Servers│  │  Memgraph   │  │   Ollama      │
│                │ │             │  │  (Docker)   │  │               │
│  Anthropic     │ │  memgraph   │  │  Bolt :7687 │  │  granite-emb  │
│  Bedrock       │ │  GitHub     │  │  Lab  :7444 │  │  qwen3-emb    │
│  OpenAI        │ │  Figma      │  │  12GB cap   │  │  :11434       │
└────────────────┘ └─────────────┘  └─────────────┘  └───────────────┘
```

---

## Prerequisites

| Requirement | Version | Install |
|-------------|---------|---------|
| Node.js | 18+ | [nodejs.org](https://nodejs.org) or `brew install node` |
| npm | Any | Bundled with Node |
| git | Any | `brew install git` or `apt install git` |
| python3 | Any | `xcode-select --install` (macOS) or `brew install python3` |

---

## What Each Component Does

### Pi CLI
The minimal terminal coding harness. Provides the `pi` command, loads extensions, skills, and agents from `~/.pi/agent/`. Think of it as a shell that orchestrates AI agents.

### Helios Orchestrator
The AI personality loaded into Pi. Helios plans, delegates, coordinates, and verifies. It uses:
- **7 Feynman agents**: scout (Arline), planner (Wheeler), worker (Dyson), reviewer (Murray), verifier (Hans), auditor (Dirac), researcher (Tukey)
- **GSD execution standard**: scores task complexity and routes to the right lane
- **Governance extension**: enforces quality gates (bash streak limits, scope confirmation, etc.)

### 20 Git Packages

| Package | Purpose |
|---------|---------|
| `pi-mcp-adapter` | MCP server connections (GitHub, Figma, Memgraph) |
| `pi-subagents` | Feynman multi-agent delegation framework |
| `pi-messenger` | Crew coordination & multi-agent messaging |
| `pi-coordination` | Parallel task coordination with plan/coordinate tools |
| `pi-model-switch` | Runtime model switching between providers |
| `pi-powerline-footer` | Status bar with branch, model, session info |
| `pi-prompt-template-model` | Prompt templates system |
| `pi-review-loop` | Automated code review loop |
| `pi-rewind-hook` | Session rewind/checkpoint |
| `pi-web-access` | Web search via Perplexity/Gemini, content fetching |
| `pi-interactive-shell` | Overlay CLI for delegating to other agents |
| `pi-design-deck` | Visual option comparison decks |
| `visual-explainer` | HTML diagram and explanation generator |
| `surf-cli` | Chrome DevTools automation |
| `pi-foreground-chains` | Multi-agent chains with visible overlay |
| `skills-hook` | Dynamic skill loading system |
| `pi-interview-tool` | Structured interactive forms |
| `pi-annotate` | Visual annotation mode in Chrome |
| `pi-skill-palette` | Skill browser and palette |
| `pi-boomerang` | Context collapse for long tasks |

### Extensions (5 local, in ~/.pi/agent/extensions/)
- **helios-governance** — Quality gates, bash streak limits, scope confirmation enforcement
- **helios-subagent-mesh** — Worker coordination mesh (file reservations, DMs, activity feed)
- **helios-focus** — Session context orientation
- *(+ additional extensions in the repo)*

### Familiar Skills (optional)
Skills for Google Workspace and productivity integrations:
- `gmcli` — Gmail (search, read, send)
- `gccli` — Google Calendar
- `gdcli` — Google Drive
- `transcribe` — Audio → text (Groq Whisper)
- `vscode` — VS Code diff integration
- `youtube-transcript` — YouTube transcript extraction

---

## Provider Options

### 1. Anthropic Direct (Recommended for getting started)
- **Key**: `ANTHROPIC_API_KEY` from [console.anthropic.com/api-keys](https://console.anthropic.com/api-keys)
- **Default model**: `claude-sonnet-4-5-20250514`
- **Available**: claude-opus-4, claude-sonnet-4-5, claude-haiku-4-5

### 2. Amazon Bedrock (Enterprise / AWS)
- **Keys**: `AWS_ACCESS_KEY_ID` + `AWS_SECRET_ACCESS_KEY` or IAM role
- **Default model**: `us.anthropic.claude-opus-4-6-v1`
- **Requires**: AWS account with Bedrock access enabled in your region
- **Setup**: `aws configure` or set keys in `.env`

### 3. OpenAI
- **Key**: `OPENAI_API_KEY` from [platform.openai.com/api-keys](https://platform.openai.com/api-keys)
- **Default model**: `gpt-5.2`
- **Available**: gpt-5.2, gpt-4o, gpt-4o-mini

---

## Idempotent Design

The installer is safe to run multiple times:
- Existing `~/.pi/agent/` → pulls latest (git pull --rebase)
- Existing `.env` → only fills in empty keys
- Existing `settings.json` → overwritten with selected provider config
- Existing Pi CLI → skipped (version shown)

---

## Manual Setup (Fallback)

If the installer fails, here are the manual steps:

```bash
# 1. Install Pi
npm install -g @mariozechner/pi-coding-agent

# 2. Clone Helios agent
git clone https://github.com/sweetcheeks72/helios-agent.git ~/.pi/agent

# 3. Configure provider
cp ~/helios-team-installer/provider-configs/anthropic.json ~/.pi/agent/settings.json

# 4. Set up API keys
cp ~/helios-team-installer/.env.template ~/.pi/agent/.env
# Edit ~/.pi/agent/.env and fill in your ANTHROPIC_API_KEY

# 5. Install packages
pi update

# 6. (Optional) Familiar skills
git clone https://github.com/sweetcheeks72/familiar.git ~/.familiar
# NOTE: Verify the Familiar repo URL before running

# 7. Verify
bash ~/helios-team-installer/verify.sh
```

---

## Troubleshooting

### `pi: command not found` after install
```bash
# Reload your shell
source ~/.zshrc  # or ~/.bashrc

# Or find npm global bin
npm config get prefix
# Add <prefix>/bin to your PATH
```

### `Error: Cannot find module` when running pi
```bash
# Reinstall Pi
npm uninstall -g @mariozechner/pi-coding-agent
npm install -g @mariozechner/pi-coding-agent
```

### Packages not installed / agents missing
```bash
# Re-run package installation
pi update
# Then verify
bash ~/helios-team-installer/verify.sh
```

### AWS Bedrock `AccessDeniedException`
1. Ensure Bedrock model access is enabled: AWS Console → Bedrock → Model access
2. Check your IAM user/role has `bedrock:InvokeModel` permission
3. Verify region matches where you enabled access

### `.env` not being loaded
Pi loads `.env` from `~/.pi/agent/.env` automatically. Verify:
```bash
ls -la ~/.pi/agent/.env
cat ~/.pi/agent/.env | grep -v '^#' | grep -v '^$'
```

### `pi update` fails
This requires Pi to be able to reach GitHub. Check:
```bash
# Test GitHub access
curl -I https://github.com

# If behind corporate proxy, configure git proxy
git config --global http.proxy http://your-proxy:port
```

---

## Post-Install Verification

```bash
bash ~/helios-team-installer/verify.sh
```

Expected output (healthy system):
```
  ✓ pi binary: 1.x.x (/usr/local/bin/pi)
  ✓ node: v22.x.x
  ✓ Agents: 42 (✓ expect 40+)
  ✓ Skills: 18 (✓ expect 13+)
  ✓ settings.json: provider=anthropic, model=claude-sonnet-4-5
  ✓ .env: ANTHROPIC_API_KEY set
  ✓ System healthy — ready to use Pi + Helios!
```

---

## Files in This Repo

```
helios-team-installer/
├── install.sh                    # Main installer (run this)
├── verify.sh                     # Post-install health check
├── uninstall.sh                  # Clean uninstall
├── .env.template                 # API key template
├── provider-configs/
│   ├── anthropic.json            # settings.json for Anthropic
│   ├── bedrock.json              # settings.json for AWS Bedrock
│   └── openai.json               # settings.json for OpenAI
└── README.md                     # This file
```

---

## Updating

```bash
# Update the installer repo
git -C ~/helios-team-installer pull

# Re-run to get latest packages/agents
bash ~/helios-team-installer/install.sh
```

---

## Notes

- **Familiar repo URL**: The installer assumes `github.com/sweetcheeks72/familiar`. Verify this URL is correct for your team before running.
- **Autoresearch / helios-research**: These are intentionally excluded from this installer (experimental features).
- **API key security**: Keys are written to `~/.pi/agent/.env` which is gitignored by default. Never commit `.env` to version control.

---

## License

Internal tooling — for team use only.
