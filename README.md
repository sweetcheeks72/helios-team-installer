# Helios + Pi Team Installer

> One-command setup for the full Helios AI orchestrator stack on top of Pi CLI.

## Install (first time)

```bash
curl -fsSL https://raw.githubusercontent.com/helios-agi/helios-team-installer/main/bootstrap.sh | bash
```

This walks you through provider selection, API keys, and installs everything: Pi CLI, Helios agents, extensions, packages, Memgraph, Ollama, and MCP servers.

### Windows

One command in PowerShell:

```powershell
irm https://raw.githubusercontent.com/helios-agi/helios-team-installer/main/install.ps1 | iex
```

**Or from Command Prompt (no PowerShell needed):**
```cmd
curl -fsSL https://raw.githubusercontent.com/helios-agi/helios-team-installer/main/install.bat -o %TEMP%\install-helios.bat && %TEMP%\install-helios.bat
```

This automatically:
1. Installs WSL 2 + Ubuntu (if needed)
2. Runs the full Helios installer inside WSL
3. Creates `helios` and `pi` commands that work from PowerShell/CMD

> **Requires:** Windows 10 (21H2+) or Windows 11. First-time WSL install needs a restart.
> Docker Desktop with [WSL integration](https://docs.docker.com/desktop/wsl/) recommended for Memgraph.

**Manual WSL setup** (if you prefer):
1. `wsl --install` in admin PowerShell, restart
2. Open Ubuntu, then: `curl -fsSL https://raw.githubusercontent.com/helios-agi/helios-team-installer/main/bootstrap.sh | bash`

📖 **First time?** Read the [full team setup guide](TEAM-SETUP.md) — explains everything from scratch.

## Update (existing install)

```bash
cd ~/.pi/agent && git pull && pi update
```

That's it — pulls the latest agents, skills, extensions, and governance from the repo, then updates all packages.

**Alternative — full re-run** (also safe for updates):
```bash
# Same install command — auto-detects existing install, skips provider/key prompts
curl -fsSL https://raw.githubusercontent.com/helios-agi/helios-team-installer/main/bootstrap.sh | bash

# Or locally:
bash ~/helios-team-installer/install.sh          # update (non-interactive)
bash ~/helios-team-installer/install.sh --fresh   # re-run full setup (re-prompts provider/keys)
```

---

## What This Installs

| Component | Description |
|-----------|-------------|
| **Pi CLI** | The terminal AI coding harness (`@helios-agent/cli`) |
| **Helios Agent** | Orchestrator identity, 50+ agents, 13 skills, extensions (~/.pi/agent/) |
| **20 Git Packages** | Extensions for subagents, coordination, design deck, web access, etc. |
| **5 Local Extensions** | Governance, codebase-index, subagent-mesh, MCP startup, inline-enforce |
| **Memgraph** | Knowledge graph — Docker container, schema, 12GB memory cap |
| **Ollama** | Local embeddings — nomic-embed-text (primary, 768d) + granite-embedding (fallback) |
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
│            @helios-agent/cli                         │
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
│  Anthropic     │ │  memgraph   │  │  Bolt :7687 │  │  nomic-embed  │
│  Bedrock       │ │  GitHub     │  │  Lab  :7444 │  │  granite-emb  │
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
npm install -g @helios-agent/cli

# 2. Clone Helios agent
git clone https://github.com/helios-agi/helios-agent.git ~/.pi/agent

# 3. Configure provider
cp ~/helios-team-installer/provider-configs/anthropic.json ~/.pi/agent/settings.json

# 4. Set up API keys
cp ~/helios-team-installer/.env.template ~/.pi/agent/.env
# Edit ~/.pi/agent/.env and fill in your ANTHROPIC_API_KEY

# 5. Install packages
pi update

# 6. (Optional) Familiar skills
git clone https://github.com/helios-agi/familiar.git ~/.familiar
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
npm uninstall -g @helios-agent/cli
npm install -g @helios-agent/cli
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

- **Familiar repo URL**: The installer assumes `github.com/helios-agi/familiar`. Verify this URL is correct for your team before running.
- **Autoresearch / helios-research**: These are intentionally excluded from this installer (experimental features).
- **API key security**: Keys are written to `~/.pi/agent/.env` which is gitignored by default. Never commit `.env` to version control.

---

## Changelog

### v1.5.0 — Graph Brain × Neuroplasticity (Apr 2026)

- 🧠 **Graph Brain remediation** — 210K orphan nodes patched with memoryClass, 32% → 83% retrieval visibility
- 🔬 **Governance → Brain feedback loop** — H28 and all gate blocks now create GovernanceLesson nodes retrievable by BrainV2
- 🧪 **Kaizen learning fixed** — Consolidation stage creates CausalLesson nodes from recurring violations (was querying wrong event type)
- 🌿 **Physarum flow routing** — Bio-inspired conductivity on RoutingStrategy nodes (slime mold algorithm)
- 🐜 **Pheromone edge weights** — Code graph edges strengthen on successful sessions, decay over time
- 📊 **Pressure field** — Scout deposits complexity/risk/novelty signals on CodeFile nodes
- 🔄 **Hebbian co-activation** — Successful agent pipelines (scout→worker→reviewer) tracked as PipelineRoute nodes
- ⚖️ **Edge-of-chaos governance** — Adaptive strictness: loosens on stability, tightens on failures (±20%)
- 🎯 **Active bio routing** — Homeostatic scaling + neuromod signals now actively influence model tier selection
- 📡 **Dispatch telemetry** — USED_CHANNEL edges link every dispatch to its context channels
- 🛡️ **28 governance rules enriched** — GovernanceRule nodes seeded with descriptions, categories, severity

### v1.4.0 — Email Governance V2.1 (Apr 2026)

- 🛡️ Email Governance V2.1 — legal/financial/wire content blocked from wrong recipients
- 📧 Outreach governance gate on all send paths
- 🔒 Fail-closed: errors block sends, never allow through
- 📊 43 governance test cases, 4 critical bypasses fixed

---

## License

Internal tooling — for team use only.

---

## Installer Internals

### Build Pipeline

```
build-release.sh
├── Copies ~/.pi/agent/ → staging (excluding .git, sessions, user data)
├── Bundles 20 git packages from git/github.com/helios-agi/*
├── Runs npm install --production (self-contained node_modules)
├── Bundles runtime deps into .runtime/:
│   ├── .runtime/node22/       — Node 22 LTS binary for target platform
│   ├── .runtime/bun/          — Bun binary for target platform
│   └── cli/pi/pi              — CLI stub (Node script → pi-coding-agent)
├── Generates settings.json with local package paths (no git: URLs)
├── Keeps better-sqlite3 prebuilt binary (platform-specific)
├── Creates per-platform tarball: helios-agent-v{VER}-{os}-{arch}.tar.gz
└── Verifies: critical paths, ESM import, package count, node_modules

Output in dist/:
  helios-agent-latest-darwin-arm64.tar.gz   (~105 MB)
  helios-agent-latest-darwin-x64.tar.gz     (~107 MB)
  helios-agent-latest.tar.gz                (~100 MB, linux-x64)
```

### Tarball Contents

```
helios-agent-v{VERSION}/
├── .runtime/
│   ├── node22/bin/node        — Node 22 binary (no download needed at install)
│   ├── bun/bin/bun            — Bun binary (no download needed at install)
├── cli/pi/pi                  — CLI stub script (no helios-installer download)
├── node_modules/              — Pre-installed production deps (~100MB)
│   ├── @helios-agent/pi-coding-agent/  — Core CLI + agent runtime
│   ├── better-sqlite3/build/  — Prebuilt native binary for target Node 22
│   ├── neo4j-driver/          — Memgraph client
│   ├── awilix/                — DI container
│   └── ...
├── git/github.com/helios-agi/ — 20 bundled packages (local, no git fetch)
├── extensions/                — Governance, mesh, browse, etc.
├── agents/                    — 50+ agent definitions (.md)
├── skills/                    — 13+ skill definitions
├── settings.json              — Default provider config (local package paths)
├── package.json               — Root deps manifest
└── VERSION                    — Release version string
```

### Install Flow (install.sh)

```
install.sh --update
│
├── [1/7] Legacy Install Doctor
│   ├── Detects Node version (if >22: resolve from bundled .runtime/node22 first)
│   ├── Resolution priority: bundled → nvm → fnm → volta → mise → asdf → brew → apt → direct download
│   ├── Bun: bundled .runtime/bun first, then curl bun.sh fallback
│   └── All bundled = no network needed for prerequisites
│
├── [2/7] Helios CLI
│   ├── update_pi_cli(): checks if replacement available before acting
│   ├── Tries: LOCAL_PACKAGE/cli → bundled PI_AGENT_DIR/cli/pi/pi → existing binary → download
│   └── Private repo safe: won't delete working CLI if download would 404
│
├── [3/7] Agent Directory
│   ├── Extracts tarball → ~/.pi/agent/ (preserves user files: .env, settings.json, auth.json)
│   └── Uses HELIOS_PRESERVE_FILES array for merge-safe extraction
│
├── [4/7] Helios CLI (wrapper)
│   └── Creates ~/.pi/agent/bin/helios + ~/.local/bin/helios symlink
│
├── [5/7] Agent Root Deps
│   └── npm install (--prefer-offline, uses bundled node_modules as cache)
│
├── [6/7] Helios Packages
│   └── Installs git packages from local paths (no git clone of private repos)
│
└── [7/7] Skill Dependencies
    └── npm install for individual skill/extension package.json files
```

### Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| Per-platform tarballs | Native modules (better-sqlite3) are ABI-specific; universal tarballs can't ship prebuilts |
| Bundle Node 22 in tarball | Users on Node 24/25 hit ABI mismatch; downloading at runtime fails on firewalled networks |
| Bundle Bun in tarball | bun.sh/install fails in corporate/air-gapped environments |
| CLI is a stub, not a binary | pi-coding-agent is already in node_modules; no separate repo download needed |
| Don't strip better-sqlite3/build | Tarball is already platform-specific; stripping forces a prebuild download that may fail offline |
| Check replacement before deleting CLI | Private repos 404; deleting a working CLI then failing to replace it breaks the install |
| Local package paths in settings.json | Prevents `pi update` from git-fetching private repos users can't access |
| Filesystem lock with platform-aware stat | macOS uses `stat -f %m`, Linux uses `stat -c %Y`; combined one-liner breaks on Linux |

### Runtime Download Fallback Chain

When bundled runtime is missing (e.g., older tarball), the installer falls back to downloads:

```
Node 22: bundled → nvm → fnm → volta → mise → asdf → brew → apt/dnf → direct download → FAIL
Bun:     bundled → curl bun.sh → FAIL (non-fatal warning)
CLI:     bundled → LOCAL_PACKAGE → existing binary → GitHub download → FAIL
Agent:   LOCAL_PACKAGE → arch-specific URL → universal URL → gh CLI → FAIL
```

### File Locations (installed state)

```
~/.pi/agent/                    — Main agent directory (from tarball)
~/.pi/agent/.runtime/node22/    — Bundled Node 22 (source for ~/.local/node22/)
~/.pi/agent/.runtime/bun/       — Bundled Bun (source for ~/.bun/bin/)
~/.pi/agent/cli/pi/pi           — Bundled CLI stub (source for ~/.helios-cli/helios)
~/.pi/agent/bin/helios          — CLI wrapper script (product, never removed)
~/.local/node22/bin/node        — Active Node 22 sidecar (in PATH)
~/.local/bin/helios             — Symlink → ~/.pi/agent/bin/helios
~/.helios-cli/helios            — Real CLI entry point
~/.bun/bin/bun                  — Bun binary
~/.pi/.installer-lock/          — Filesystem mutex (cleaned on exit)
~/helios-team-installer/        — Installer repo (contains install.sh, build-release.sh, dist/)
```
