#!/usr/bin/env bash
# setup-ao.sh — Install and configure Agent Orchestrator (ao) for this project.
#
# Detects the current environment and acts accordingly:
#   - Git Bash (Windows): re-launches itself inside WSL automatically
#   - WSL: installs tmux, Node.js, pnpm, gh, Claude Code, jq, and ao
#
# This script is idempotent — safe to run multiple times.
#
# Usage:
#   ./scripts/setup-ao.sh              # From Git Bash or WSL
#
# Requirements:
#   - Windows: WSL installed (wsl --install if not)
#   - Internet connection for package installation

set -euo pipefail

# ─── Colors ───────────────────────────────────────────
if [ -t 1 ]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; NC=''
fi

log()  { echo -e "[setup-ao] $1"; }
pass() { echo -e "  ${GREEN}PASS${NC}  $1"; }
warn() { echo -e "  ${YELLOW}WARN${NC}  $1"; }
fail() { echo -e "  ${RED}FAIL${NC}  $1"; }
step() { echo -e "\n${BLUE}── $1 ──${NC}"; }

ERRORS=0

# ─── Platform detection ──────────────────────────────
detect_platform() {
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) echo "windows-gitbash" ;;
    Linux)
      if grep -qi microsoft /proc/version 2>/dev/null; then
        echo "wsl"
      else
        echo "linux"
      fi ;;
    Darwin) echo "macos" ;;
    *) echo "unknown" ;;
  esac
}

PLATFORM=$(detect_platform)

# ─── Git Bash → WSL relay ────────────────────────────
if [ "$PLATFORM" = "windows-gitbash" ]; then
  log "Detected Git Bash on Windows. Relaying to WSL..."

  # Check WSL is available
  if ! command -v wsl &>/dev/null; then
    fail "WSL not found. Install it: wsl --install"
    exit 1
  fi

  # Convert current path to WSL format
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

  # MSYS paths like /c/Users/... → /mnt/c/Users/...
  REPO_WSL=$(echo "$REPO_ROOT" | sed 's|^/\([a-zA-Z]\)/|/mnt/\L\1/|')

  log "Repo path in WSL: ${REPO_WSL}"
  log "Launching setup inside WSL...\n"

  wsl bash -c "cd \"$REPO_WSL\" && bash scripts/setup-ao.sh"
  exit $?
fi

# ─── From here on, we're running inside WSL/Linux/macOS ──

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

step "Step 1: System packages"

# tmux
if command -v tmux &>/dev/null; then
  pass "tmux $(tmux -V 2>/dev/null || echo '')"
else
  log "Installing tmux..."
  if command -v apt-get &>/dev/null; then
    sudo apt-get update -qq && sudo apt-get install -y -qq tmux
  elif command -v brew &>/dev/null; then
    brew install tmux
  else
    fail "Cannot install tmux — no apt-get or brew found"
    ERRORS=$((ERRORS + 1))
  fi
  if command -v tmux &>/dev/null; then
    pass "tmux installed: $(tmux -V)"
  fi
fi

# jq
if command -v jq &>/dev/null; then
  pass "jq $(jq --version 2>/dev/null || echo '')"
else
  log "Installing jq..."
  if command -v apt-get &>/dev/null; then
    sudo apt-get install -y -qq jq
  elif command -v brew &>/dev/null; then
    brew install jq
  fi
  if command -v jq &>/dev/null; then
    pass "jq installed"
  else
    fail "Could not install jq"
    ERRORS=$((ERRORS + 1))
  fi
fi

# git
if command -v git &>/dev/null; then
  pass "git $(git --version | awk '{print $3}')"
else
  fail "git not found"
  ERRORS=$((ERRORS + 1))
fi

step "Step 2: Node.js 20+"

install_nvm_and_node() {
  log "Installing nvm + Node.js 20..."
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash

  # Load nvm into current shell
  export NVM_DIR="$HOME/.nvm"
  # shellcheck disable=SC1091
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

  nvm install 20
  nvm use 20
  nvm alias default 20
}

if command -v node &>/dev/null; then
  NODE_VERSION=$(node --version | sed 's/^v//')
  NODE_MAJOR=$(echo "$NODE_VERSION" | cut -d. -f1)
  if [ "$NODE_MAJOR" -ge 20 ]; then
    pass "Node.js v${NODE_VERSION}"
  else
    warn "Node.js v${NODE_VERSION} found but v20+ required"
    install_nvm_and_node
  fi
else
  install_nvm_and_node
fi

# Verify node is available now
if command -v node &>/dev/null; then
  NODE_MAJOR=$(node --version | sed 's/^v//' | cut -d. -f1)
  if [ "$NODE_MAJOR" -ge 20 ]; then
    pass "Node.js $(node --version) ready"
  else
    fail "Node.js 20+ required, got $(node --version)"
    ERRORS=$((ERRORS + 1))
  fi
else
  fail "Node.js not available after install attempt"
  ERRORS=$((ERRORS + 1))
fi

step "Step 3: pnpm"

if command -v pnpm &>/dev/null; then
  pass "pnpm $(pnpm --version)"
else
  log "Installing pnpm..."
  npm install -g pnpm
  if command -v pnpm &>/dev/null; then
    pass "pnpm $(pnpm --version) installed"
  else
    fail "Could not install pnpm"
    ERRORS=$((ERRORS + 1))
  fi
fi

step "Step 4: GitHub CLI (gh)"

if command -v gh &>/dev/null; then
  pass "gh $(gh --version | head -1 | awk '{print $3}')"
else
  log "Installing gh CLI..."
  if command -v apt-get &>/dev/null; then
    # GitHub's official apt repository
    (type -p wget >/dev/null || sudo apt-get install -y -qq wget) \
      && sudo mkdir -p -m 755 /etc/apt/keyrings \
      && wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
      && sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
      && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
      && sudo apt-get update -qq \
      && sudo apt-get install -y -qq gh
  elif command -v brew &>/dev/null; then
    brew install gh
  fi

  if command -v gh &>/dev/null; then
    pass "gh CLI installed"
  else
    fail "Could not install gh CLI"
    ERRORS=$((ERRORS + 1))
  fi
fi

# Check gh auth
if gh auth status --hostname github.com &>/dev/null 2>&1; then
  pass "gh authenticated"
else
  warn "gh not authenticated. Run: gh auth login"
  log "  ao needs gh to read issues and create PRs."
fi

step "Step 5: Claude Code CLI"

if command -v claude &>/dev/null; then
  pass "Claude Code CLI found"
else
  log "Installing Claude Code CLI..."
  npm install -g @anthropic-ai/claude-code
  if command -v claude &>/dev/null; then
    pass "Claude Code CLI installed"
  else
    fail "Could not install Claude Code CLI"
    ERRORS=$((ERRORS + 1))
  fi
fi

step "Step 6: Agent Orchestrator (ao)"

AO_DIR="$HOME/.agent-orchestrator"

if command -v ao &>/dev/null; then
  pass "ao $(ao --version 2>/dev/null || echo 'installed')"
else
  log "ao not found. Installing..."

  if [ -d "$AO_DIR" ]; then
    log "Directory exists at $AO_DIR — updating..."
    cd "$AO_DIR" && git pull
  else
    log "Cloning agent-orchestrator..."
    if command -v gh &>/dev/null; then
      gh repo clone ComposioHQ/agent-orchestrator "$AO_DIR"
    else
      git clone https://github.com/ComposioHQ/agent-orchestrator.git "$AO_DIR"
    fi
  fi

  cd "$AO_DIR"
  log "Installing dependencies..."
  pnpm install

  log "Building..."
  pnpm build

  log "Linking CLI globally..."
  npm link -g packages/cli 2>/dev/null || pnpm link --global packages/cli 2>/dev/null || {
    fail "Could not link ao CLI globally. Try: cd $AO_DIR && npm link -g packages/cli"
    ERRORS=$((ERRORS + 1))
  }

  cd "$REPO_ROOT"

  if command -v ao &>/dev/null; then
    pass "ao installed: $(ao --version 2>/dev/null || echo 'ok')"
  else
    fail "ao not found after install. Check $AO_DIR"
    ERRORS=$((ERRORS + 1))
  fi
fi

step "Step 7: Configuration"

CONFIG_FILE="$REPO_ROOT/agent-orchestrator.yaml"

if [ -f "$CONFIG_FILE" ]; then
  pass "agent-orchestrator.yaml exists"

  # Check path format
  CURRENT_PATH=$(grep 'path:' "$CONFIG_FILE" | head -1 | sed 's/.*path: *//; s/^"//; s/"$//')
  if echo "$CURRENT_PATH" | grep -q '^/mnt/'; then
    pass "Path uses WSL format: ${CURRENT_PATH}"
  elif echo "$CURRENT_PATH" | grep -q '^/[a-zA-Z]/'; then
    warn "Path uses Git Bash format — should be /mnt/c/... for WSL"
    log "  Current: ${CURRENT_PATH}"
    WSL_PATH=$(echo "$CURRENT_PATH" | sed 's|^/\([a-zA-Z]\)/|/mnt/\L\1/|')
    log "  Suggested: ${WSL_PATH}"
  else
    pass "Path: ${CURRENT_PATH}"
  fi
else
  fail "agent-orchestrator.yaml not found at $CONFIG_FILE"
  ERRORS=$((ERRORS + 1))
fi

step "Step 8: ao doctor"

if command -v ao &>/dev/null; then
  cd "$REPO_ROOT"
  log "Running ao doctor..."
  ao doctor 2>&1 || true
fi

# ─── Summary ─────────────────────────────────────────
echo ""
if [ "$ERRORS" -eq 0 ]; then
  log "${GREEN}Setup complete — ao is ready!${NC}"
  log ""
  log "Next steps:"
  log "  1. Authenticate gh if needed:  gh auth login"
  log "  2. Start ao:                   ao start"
  log "  3. Start auto-dispatch:        ./scripts/poll-and-spawn.sh <project-name> &"
  log "  Or use the convenience script: ./scripts/ao-start.sh"
else
  log "${RED}Setup completed with ${ERRORS} error(s).${NC} Fix the FAIL items above and re-run."
fi

exit "$ERRORS"
