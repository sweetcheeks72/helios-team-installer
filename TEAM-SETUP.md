# Helios Setup Guide — For the Team

## The 30-Second Version

Run this one command. It handles everything:

```bash
curl -fsSL https://raw.githubusercontent.com/sweetcheeks72/helios-team-installer/main/bootstrap.sh | bash
```

The installer walks you through each step interactively. Total time: ~10 minutes.

> **No git clone needed** — the bootstrap downloads and sets everything up automatically.
>
> **Fallback (if curl isn't available):**
> ```bash
> git clone https://github.com/sweetcheeks72/helios-team-installer.git ~/helios-team-installer && bash ~/helios-team-installer/install.sh
> ```

When it's done, open any project and type `pi` — you now have an AI orchestrator that plans, delegates, reviews, and verifies code.

---

## What You're Actually Installing (and Why)

Think of this as three layers, like a cake:

```
┌─────────────────────────────────────────────┐
│  Layer 3: HELIOS (the brain)                │  ← Our custom AI orchestrator
│  Agents, skills, governance, coordination   │     that plans and delegates
├─────────────────────────────────────────────┤
│  Layer 2: PACKAGES (the arms)              │  ← 20 extensions that give
│  Subagents, web search, design deck,       │     Helios its capabilities
│  code review, browser tools, etc.          │
├─────────────────────────────────────────────┤
│  Layer 1: PI CLI (the body)                │  ← The terminal harness that
│  npm package that runs in your terminal    │     loads everything and talks
│                                             │     to AI providers
└─────────────────────────────────────────────┘
        ↕
   AI Provider (Anthropic / AWS Bedrock / OpenAI)
```

**Pi** is like VS Code — it's the shell that loads extensions.
**Packages** are like VS Code extensions — they add capabilities (web search, multi-agent coordination, etc.).
**Helios** is like a workspace configuration — it defines HOW those capabilities are used (which agents exist, what governance rules apply, how tasks get routed).

You need all three layers. The installer sets them all up.

---

## Before You Start

### You MUST have:

| What | Why | How to check | How to install |
|------|-----|-------------|----------------|
| **Node.js 18+** | Pi runs on Node | `node -v` → should show v18+ | `brew install node` or [nodejs.org](https://nodejs.org) |
| **npm** | Installs Pi and packages | `npm -v` → any version | Comes with Node |
| **git** | Clones repos | `git -v` → any version | `brew install git` |
| **GitHub access** | You've been invited to 3 repos | Check your email for invites | Accept all 3 invitations from GitHub |

### You SHOULD have:

| What | Why | How to install |
|------|-----|----------------|
| **Docker** | For Memgraph (AI memory database) | [docker.com](https://docker.com) |
| **An API key** | At least one AI provider | See "Choosing a Provider" below |

### Accept your GitHub invitations FIRST

You should have received 3 invitation emails from GitHub for:
1. `sweetcheeks72/helios-team-installer` — the installer (this repo)
2. `sweetcheeks72/helios-agent` — the Helios brain (agents, skills, config)
3. `sweetcheeks72/familiar` — productivity skills (Gmail, Calendar, Drive)

**Accept all 3 before running the installer.** Go to [github.com/notifications](https://github.com/notifications) or check your email.

---

## Choosing a Provider

The installer will ask you which AI provider to use. Here's what you need to know:

### Option 1: Anthropic Direct ← Start here if unsure

**What it is:** You pay Anthropic directly for API access to Claude models.
**What you need:** An API key from [console.anthropic.com](https://console.anthropic.com/api-keys)
**Cost:** Pay-per-use (a few dollars/day for normal development)
**Setup time:** 2 minutes (sign up, create key, paste it)

This is the fastest way to get started. You can always switch to Bedrock later.

### Option 2: Amazon Bedrock ← If you have AWS

**What it is:** Claude models accessed through your AWS account.
**What you need:** AWS access key + secret key with Bedrock permissions
**Why use it:** If your company already pays for AWS, this may be cheaper/preferred
**Setup time:** 10-30 minutes (enable model access in AWS Console, create IAM credentials)
**Gotcha:** You must explicitly enable Claude models in the Bedrock console for your region BEFORE using them.

### Option 3: OpenAI ← If you prefer GPT

**What it is:** GPT-5.2 and GPT-4o from OpenAI.
**What you need:** An API key from [platform.openai.com](https://platform.openai.com/api-keys)
**Note:** Some Helios features work best with Claude (Anthropic). OpenAI works but is less tested with our agent definitions.

---

## Running the Installer

### Step-by-step walkthrough

```bash
git clone https://github.com/sweetcheeks72/helios-team-installer.git ~/helios-team-installer
bash ~/helios-team-installer/install.sh
```

Here's what happens at each stage (the installer tells you, but so you're not surprised):

**1. Prerequisites check** — It verifies Node, npm, git are installed. If anything is missing, it tells you exactly what to install and stops.

**2. Pi CLI install** — If you don't have `pi` installed, it runs `npm install -g @mariozechner/pi-coding-agent`. If you already have it, it skips this.

**3. Helios agent clone** — Clones the `helios-agent` repo to `~/.pi/agent/`. This is where all the agent definitions, skills, and configuration live. If it already exists, it pulls the latest.

**4. Provider selection** — Interactive menu. Pick 1 (Anthropic), 2 (Bedrock), or 3 (OpenAI). This configures which AI models Pi talks to.

**5. Package installation** — Runs `pi update` which downloads 20 extension packages from GitHub. Takes 2-3 minutes. These add capabilities like web search, multi-agent coordination, and code review.

**6. API key setup** — Prompts you for your API key(s). Your input is hidden (like a password field). You can skip any key and add it later. Keys are saved to `~/.pi/agent/.env`.

**7. Shell wiring** — Adds a line to your `~/.zshrc` (or `~/.bashrc`) so your API keys are loaded every time you open a terminal. **This is critical** — without it, Pi can't see your keys.

**8. Familiar skills (optional)** — Asks if you want Gmail, Calendar, Drive integration. Say yes if you want those. Say no if you just want coding features.

**9. Memgraph (optional)** — Asks if you want the knowledge graph database (requires Docker). This gives Helios a memory across sessions. Nice to have, not required to start.

**10. Verification** — Counts your agents, skills, extensions and tells you if everything looks good.

### After the installer finishes:

```bash
# IMPORTANT: Reload your shell so API keys take effect
source ~/.zshrc   # or: source ~/.bashrc

# Verify everything works
bash ~/helios-team-installer/verify.sh
```

---

## Your First Session

```bash
# Go to any project
cd ~/your-project

# Start Helios
pi
```

That's it. You're now in a Helios session. Try these:

| What to type | What happens |
|-------------|-------------|
| `Review this codebase and summarize the architecture` | Helios scouts the codebase, dispatches agents, gives you a structured summary |
| `Find and fix bugs in src/` | Dispatches a scout for recon, then a worker to fix, then a reviewer to verify |
| `Create a PR for the auth feature` | Plans the work, implements it, runs tests, creates the PR |
| `What's the current state of this project?` | Loads the "focus" skill — shows git state, open PRs, recent changes |

### What you'll notice that's different from raw Claude/ChatGPT:

1. **It delegates** — Helios doesn't do everything itself. It dispatches specialist agents (scout for recon, worker for code, reviewer for review).
2. **It confirms scope** — Before big changes, it asks "Before I proceed, here's what I understand..." to make sure it's doing what you want.
3. **It has governance** — Quality gates prevent sloppy work (e.g., it can't run unlimited bash commands without delegating, it must scout before planning).
4. **It ends with a verdict** — Every task ends with ✅ DONE, ⚠️ BLOCKED, or ⏳ PARTIAL.

---

## Understanding the Agent System

Helios uses 7 specialist agents, each named after a physicist who worked with Feynman. Here's what they do:

| Agent | Codename | Role | Analogy |
|-------|----------|------|---------|
| **Scout** | Arline | Reads code, explores files, gathers context | A detective investigating before any action |
| **Planner** | Wheeler | Decomposes big tasks into steps | An architect drawing blueprints |
| **Worker** | Dyson | Writes and edits code | A builder constructing from the blueprint |
| **Reviewer** | Murray | Reviews code adversarially (finds bugs) | A building inspector looking for problems |
| **Verifier** | Hans | Checks invariants and data flow | A QA tester running edge cases |
| **Auditor** | Dirac | Verifies claims against evidence | A fact-checker making sure nothing was fabricated |
| **Researcher** | Tukey | Searches the web, reads docs | A librarian finding reference material |

**Only Worker (Dyson) can edit source code.** This is by design — it prevents the scout from accidentally changing things while investigating, or the reviewer from "fixing" things during review.

When you give Helios a task, it:
1. Scores the complexity (the "GSD preflight")
2. Routes to the right lane: **lite** (quick, one agent), **collaboration** (multiple agents), or **full** (formal plan → execute → verify)
3. Dispatches agents in the right order
4. Verifies the result before saying "done"

---

## File Locations (Where Things Live)

After install, here's your file structure:

```
~/.pi/
├── agent/                    ← THE MAIN CONFIG (git repo)
│   ├── agents/               ← 40+ agent definitions (.md files)
│   ├── skills/               ← 13 skill definitions (SKILL.md)
│   ├── extensions/           ← 5 TypeScript extensions
│   ├── scripts/              ← Automation scripts
│   ├── schemas/              ← JSON schemas for handoffs/recaps
│   ├── docs/                 ← Internal documentation
│   ├── governance/           ← Quality gate logs and config
│   ├── git/                  ← 20 installed packages (from pi update)
│   ├── settings.json         ← Provider, model, packages config
│   ├── .env                  ← YOUR API KEYS (never commit this)
│   ├── mcp.json              ← MCP server connections
│   ├── APPEND_SYSTEM.md      ← Helios runtime addendum
│   └── SYSTEM.md             ← Base system prompt
│
├── subagent-mesh/            ← Runtime agent coordination artifacts
├── deck-snapshots/           ← Design deck session data
└── session-memory/           ← Session state

~/.familiar/                  ← OPTIONAL: Productivity skills
├── skills/
│   ├── gmcli/                ← Gmail
│   ├── gccli/                ← Google Calendar
│   ├── gdcli/                ← Google Drive
│   ├── transcribe/           ← Audio transcription
│   └── ...

~/helios-team-installer/      ← THIS REPO (keep it for verify/update/uninstall)
```

**The only file you'll regularly edit is `~/.pi/agent/.env`** (to add/change API keys). Everything else is managed by git pull and `pi update`.

---

## Common Tasks

### Updating to the latest version
```bash
cd ~/.pi/agent && git pull
pi update
```

### Switching AI providers
```bash
# Re-run the installer — it's idempotent (safe to run again)
bash ~/helios-team-installer/install.sh
# Choose your new provider when prompted
```

### Adding a new API key
```bash
# Edit the .env file
nano ~/.pi/agent/.env
# Add your key, save, then reload:
source ~/.zshrc
```

### Running the health check
```bash
bash ~/helios-team-installer/verify.sh
```

### Starting Memgraph (if you skipped it during install)
```bash
docker compose -f ~/helios-team-installer/docker-compose.memgraph.yml up -d
```

### Uninstalling
```bash
bash ~/helios-team-installer/uninstall.sh
```

---

## Troubleshooting

### "pi: command not found"

**What happened:** npm installed Pi but your terminal doesn't know where to find it.

**Fix:**
```bash
# Reload your shell config
source ~/.zshrc   # or source ~/.bashrc

# If that doesn't work, find where npm puts global packages:
npm config get prefix
# Add that path + /bin to your PATH. Example:
export PATH="$(npm config get prefix)/bin:$PATH"
```

### "Error: No API key configured"

**What happened:** Pi can't find your API key in the environment.

**Fix:**
```bash
# Check if .env exists and has your key
cat ~/.pi/agent/.env | grep -v '^#' | grep -v '^$'

# Check if your shell is sourcing it
grep '.pi/agent/.env' ~/.zshrc   # or ~/.bashrc

# If not, add it manually:
echo '[ -f ~/.pi/agent/.env ] && set -a && source ~/.pi/agent/.env && set +a' >> ~/.zshrc
source ~/.zshrc
```

### "pi update" hangs or fails

**What happened:** Can't reach GitHub to download packages.

**Fix:**
```bash
# Test GitHub access
curl -I https://github.com

# If behind a firewall/VPN, you may need to configure git proxy:
git config --global http.proxy http://your-proxy:port

# Try updating a single package to isolate the issue:
pi update git:github.com/nicobailon/pi-subagents
```

### Agents count is low (< 40)

**What happened:** `pi update` didn't install all packages.

**Fix:**
```bash
# Check what's installed
ls ~/.pi/agent/git/github.com/ | wc -l

# Re-run package install
pi update

# Verify
bash ~/helios-team-installer/verify.sh
```

### AWS Bedrock "AccessDeniedException"

**What happened:** Your AWS account hasn't enabled Claude models in Bedrock.

**Fix:**
1. Go to AWS Console → Amazon Bedrock → Model access
2. Click "Manage model access"
3. Enable the Claude models (claude-opus-4, claude-sonnet-4-5, claude-haiku-4-5)
4. Wait ~5 minutes for access to propagate
5. Make sure your region in `.env` matches where you enabled access

### Google Workspace skills don't work (Gmail, Calendar, Drive)

**What happened:** These need OAuth tokens, which the installer doesn't set up automatically.

**Fix:**
```bash
# Read the setup instructions for each skill:
cat ~/.familiar/skills/gmcli/SKILL.md
```
Each skill has its own OAuth setup guide. You'll need to create a Google Cloud project and generate OAuth credentials.

---

## How This Stays Updated

When the team lead pushes changes to `helios-agent`, a GitHub Action automatically syncs the installer's package configs. To get the latest:

```bash
# Update the agent config
cd ~/.pi/agent && git pull

# Update packages
pi update

# Update the installer (if you want latest scripts)
cd ~/helios-team-installer && git pull
```

---

## Quick Reference Card

```
DAILY USE:
  pi                          Start a Helios session in current directory
  pi "fix the login bug"      Start with a specific task
  
MAINTENANCE:
  cd ~/.pi/agent && git pull  Get latest agent config
  pi update                   Update all 20 packages
  bash ~/helios-team-installer/verify.sh   Health check
  
KEY FILES:
  ~/.pi/agent/.env            API keys (edit this)
  ~/.pi/agent/settings.json   Provider config (managed by installer)
  
HELP:
  pi --help                   Pi CLI help
  /gov-status                 Governance compliance (inside a session)
  /focus                      Current project context (inside a session)
```

---

## Questions?

Ping the team lead or open an issue on `sweetcheeks72/helios-team-installer`.
