---
name: setup
description: "Onboard a new Build-Pipe project. Run the interactive setup wizard that configures your tech stack, pipeline mode, GitHub labels, CODEOWNERS, and Agent Orchestrator. Use this skill whenever the user says /setup, 'set up the pipeline', 'initialize Build-Pipe', 'configure my project', 'onboard', or any request to configure Build-Pipe for a new repository. Also trigger when the user has just copied the template and needs to personalize it."
---

# Build-Pipe Setup Wizard

You are running the interactive onboarding flow for Build-Pipe. Your job is to walk the user through configuring their project so the pipeline works end-to-end.

The setup has 8 phases. Complete them in order. After each phase, confirm what was done before moving on.

---

## Phase 1: Prerequisites Check

Before anything else, verify the user's environment is ready. Run these checks silently and report results:

```bash
# Check gh CLI
gh auth status --hostname github.com 2>&1

# Check jq
jq --version 2>&1

# Check ao (optional)
command -v ao 2>&1 || echo "ao not installed (optional — pipeline works without it)"
```

Report which prerequisites are met and which are missing. If `gh` is not authenticated, stop and help them run `gh auth login` first — nothing else works without it.

### 1a. jq Installation (if missing)

If `jq --version` fails, install it automatically based on the platform:

**macOS:**
```bash
brew install jq
```

**Linux (Debian/Ubuntu):**
```bash
sudo apt-get install -y jq
```

**Linux (Fedora/RHEL):**
```bash
sudo dnf install -y jq
```

**Windows:**
```bash
winget install jqlang.jq
```

On Windows, `winget` updates PATH but the current shell session won't see it. After install, find the binary and add it to PATH for the current session:
```bash
# Find where winget installed jq
JQ_PATH=$(find "$LOCALAPPDATA/Microsoft/WinGet" -name "jq.exe" 2>/dev/null | head -1)
if [ -n "$JQ_PATH" ]; then
  export PATH="$(dirname "$JQ_PATH"):$PATH"
fi
# Verify
jq --version
```

If automatic install fails, direct the user to https://jqlang.github.io/jq/download/.

### 1b. Agent Orchestrator (ao) — Optional Install

If `ao` is not found, ask the user ONE question:

> "Would you like to install the Agent Orchestrator (ao)? It enables fully autonomous pipeline execution — agents spawn automatically in isolated worktrees, failed CI retries happen without you, and PR review comments forward to agents. Without it, you'll process `pipeline:agent-task` issues manually with Claude Code. Install ao? (yes/no)"

**If no:** Note ao is optional and continue to Phase 2.

**If yes:** Run the full installation autonomously. The user should not need to do anything else.

#### Step 1: Check ao prerequisites

```bash
# Check Node.js 20+
node --version 2>&1 | grep -E '^v(2[0-9]|[3-9][0-9])' || echo "NEED_NODE"

# Check pnpm
command -v pnpm 2>&1 || echo "NEED_PNPM"

# Check tmux (Linux/macOS only — skip on Windows)
command -v tmux 2>&1 || echo "NEED_TMUX"
```

Install any missing prerequisites automatically:

- **Node.js missing/old:** Tell the user "Node.js 20+ is required for ao" and offer to install via `nvm install 20` (if nvm exists) or direct them to https://nodejs.org. If you cannot install it, skip ao and continue — note it can be installed later.
- **pnpm missing:** Run `npm install -g pnpm`
- **tmux missing (Linux/macOS):** Run `sudo apt-get install -y tmux` (Debian/Ubuntu) or `brew install tmux` (macOS). On Windows with WSL, note tmux runs inside WSL.

#### Step 2: Clone and build ao

```bash
# Clone into a predictable location
AO_DIR="$HOME/.agent-orchestrator"
if [ -d "$AO_DIR" ]; then
  echo "ao directory already exists at $AO_DIR — updating..."
  cd "$AO_DIR" && git pull
else
  gh repo clone ComposioHQ/agent-orchestrator "$AO_DIR"
fi

# Install and build
cd "$AO_DIR" && pnpm install && pnpm build

# Link CLI globally
npm link -g packages/cli
```

#### Step 3: Verify installation

```bash
ao --version 2>&1
```

If `ao --version` succeeds, report: "ao installed successfully." and continue.

If the build fails, don't block setup. Report the error and tell the user: "ao installation failed — you can retry later by running `cd ~/.agent-orchestrator && pnpm install && pnpm build && npm link -g packages/cli`. The pipeline works without ao." Then continue to Phase 2.

---

## Phase 2: Project Identity

Ask the user these questions. Auto-detect what you can to reduce friction.

### 2a. GitHub Repository

Try to detect automatically:
```bash
gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null
```

If detected, confirm with the user: "I see this repo is `org/repo-name` — is that correct?"
If not detected, ask: "What's your GitHub repository? (format: org/repo-name)"

### 2b. GitHub Username

Auto-detect:
```bash
gh api user -q '.login' 2>/dev/null
```

Confirm with user or ask if detection fails.

### 2c. Project Name

Ask: "What's the human-readable name for this project? (e.g., 'My SaaS App', 'Client Portal')"

This goes into `stack.yaml` as `project_name` and `agent-orchestrator.yaml` as the project key.

### 2d. Pipeline Mode

Ask the user to choose their pipeline mode. Explain each option briefly:

- **discovery** — "You're starting fresh. You'll collect customer signals (feedback, research, ideas) and the pipeline will synthesize them into a product vision and architecture."
- **execution** — "You have a build plan with tasks and dependencies. The pipeline reads task files as specs and executes them in dependency order."
- **steady-state** — "Your product is live. The pipeline processes incoming signals (bugs, features, feedback) one at a time through discovery → architecture → spec → code."

Default recommendation: If the user isn't sure, suggest `steady-state` — it's the most common starting point and works for any project that already has a codebase.

### 2e. Upstream Template Repo

Detect if this repo was forked from an upstream Build-Pipe template:

```bash
# Check if the repo has a parent (fork source)
gh repo view --json parent -q '.parent.nameWithOwner' 2>/dev/null
```

If a parent is found, confirm with the user: "This repo was forked from `org/AutoPipe`. I'll set that as `template.upstream_repo` in `pipeline.yaml` so agents can auto-report template bugs back to the upstream. OK?"

If no parent is detected (e.g., the template was copied rather than forked), ask: "Was this repo copied from a Build-Pipe template? If so, what's the upstream repo? (format: org/repo, or leave blank to skip)"

Store the value for Phase 4b.

---

## Phase 3: Tech Stack

Walk the user through `stack.yaml` configuration. For each field, give 2-3 common examples and let them pick or type their own. Accept empty values — not every project needs every field.

Fields to configure (in order):

1. **UI Framework** — e.g., shadcn/ui, Material UI, Chakra UI, Tailwind (or blank)
2. **Frontend Runtime** — e.g., Next.js, Vite + React, SvelteKit, Nuxt (or blank)
3. **Backend Framework** — e.g., FastAPI, Express, Django, Rails, Go/Gin (or blank)
4. **Database** — e.g., Supabase, PostgreSQL, MongoDB, SQLite (or blank)
5. **Auth** — e.g., Supabase Auth, NextAuth, Clerk, Auth0 (or blank)
6. **LLM Orchestration** — e.g., LangGraph, CrewAI, none (or blank)
7. **Workflow Engine** — e.g., Inngest, Temporal, none (or blank)
8. **Testing Backend** — e.g., pytest, jest, go test (or blank)
9. **Testing Frontend** — e.g., vitest, jest, none (or blank)
10. **Testing E2E** — e.g., playwright, cypress, none (or blank)
11. **Hosting** — e.g., Vercel, Railway, AWS, fly.io (or blank)
12. **Notes** — any additional constraints (or blank)

Tip: Group related questions. Don't ask 12 separate questions — ask "Frontend stack?" (covers ui_framework + frontend_runtime), "Backend stack?" (covers backend + database + auth), "Testing?" (all three), etc.

---

## Phase 3a: Local Development Strategy

Walk the user through the `local_dev` section of `stack.yaml`. This determines how every feature will be developed and tested locally.

Ask the user:

1. **Strategy** — "How will developers run the project locally?"
   - `docker-compose` — All services defined in a compose file
   - `native` — Install everything directly on the host machine
   - `devcontainer` — VS Code Dev Container or GitHub Codespaces
   - `nix` — Nix flakes for reproducible environments
   - Other (let them type)

2. **Bootstrap command** — "What single command should take a developer from `git clone` to a running app? (e.g., `make dev`, `docker compose up`, `./scripts/bootstrap.sh`)"
   If they don't know yet, suggest: `make dev` as a convention they can wire up later.

3. **Prerequisites** — "What system-level tools does a developer need installed? (e.g., Docker, Node 20+, Python 3.11+)"

4. **Seed data** — "How will development/test data be loaded? (e.g., `make seed`, `scripts/seed.sh`, or none for now)"

5. **Env setup** — "How will environment variables be configured? (default: `cp .env.example .env`)"

Apply responses to `stack.yaml` under the `local_dev` section.

---

## Phase 3b: Project Foundation

These documents give agents context about your project — vision, brand, users, and constraints. Better context produces better discovery docs, architecture decisions, and specifications from day one.

The foundation docs live in `docs/00-foundation/`. Each file has template placeholders that need filling in.

### 3b-1. PROJECT.md (Required)

This is the minimum viable foundation doc. Ask the user:
- "In one or two sentences, what is this product and who is it for?"
- "What are 2-3 measurable outcomes that would mean this product is successful?"
- "What are you explicitly NOT building? (prevents scope creep)"

Fill in `docs/00-foundation/PROJECT.md` with their answers. Replace all placeholder text in brackets.

### 3b-2. BRAND.md (Recommended)

Ask the user:
- "How should the product communicate? (e.g., formal, casual, playful, professional)"
- "What are 2-3 design principles? (e.g., 'speed over features', 'simplicity first')"
- "Any specific design system, colors, or typography?"

If the user has an existing brand guide or design system doc, offer to read it and extract the relevant info into the template format.

If they want to skip, leave the placeholder text — agents will still work but produce more generic output for user-facing features.

### 3b-3. PERSONAS.md (Recommended)

Ask the user:
- "Who are the 2-3 main types of users?"
- For each: "What are they trying to do? What frustrates them?"

If the user has existing user research, persona docs, or a strategy document, offer to import from those.

### 3b-4. CONSTRAINTS.md (Optional)

Ask the user:
- "Any compliance requirements? (GDPR, SOC 2, HIPAA, etc.)"
- "Any performance budgets? (page load time, API latency targets)"
- "Any business rules agents should know about? (pricing tiers, rate limits, etc.)"

If they're not sure or it's a greenfield project, create the file with "None currently" in each section. Agents benefit from knowing there are no constraints rather than guessing.

### Import Mode

If you detect existing files in the repo that look like strategy docs, brand guides, or user research (e.g., `brand.md`, `strategy.md`, `personas.md`, `README.md` with a product description), offer to read them and populate the foundation docs automatically:

"I see you have a `brand.md` in the repo. Want me to extract the relevant info into `docs/00-foundation/BRAND.md`?"

---

## Phase 4: Apply Configuration

Now apply everything the user told you. Use the Edit tool to update each file.

### 4a. Update `stack.yaml`

Replace the placeholder values with the user's choices. Keep empty strings for fields they skipped.

### 4b. Update `pipeline.yaml`

Set line 13 (`mode:`) to the user's chosen mode. If the user provided an upstream template repo in Phase 2e, set `template.upstream_repo` to that value.

### 4c. Update `.github/CODEOWNERS`

Replace every instance of `@your-github-username` with `@{actual-username}`.

### 4d. Update `agent-orchestrator.yaml`

Under `projects:`, replace:
- `my-project:` → use a slug of the project name (lowercase, hyphens, no spaces)
- `repo: your-org/your-repo` → actual `org/repo`
- `path: ~/path/to/your-repo` → actual local path (use the current working directory)

### 4e. Create GitHub Labels

Run the setup script to create all pipeline labels:

```bash
./scripts/setup-labels.sh
```

This creates all pipeline labels. If any already exist, the script skips them gracefully.

### 4f. Create Project Board

Run the setup script with the project name from Phase 2:

```bash
./scripts/setup-project-board.sh "{project-name}"
```

This creates a GitHub Project with a "Pipeline Stage" field and 8 stages: Signal Received → Discovery → Synthesis → Architecture → Specification → Dispatched → Code → Complete. Show the user the project board URL from the script output.

### 4g. Set Up Branch Protection

Run the branch protection script:

```bash
./scripts/setup-branch-protection.sh
```

This configures `main` with: required PR reviews (1 approval), required status checks (`Validate Document Pipeline`, `Run Test Suite`), and required Code Owner reviews. If the repo is on a free plan with private visibility, the script will warn and print manual instructions — this is non-blocking.

### 4h. Make Scripts Executable

```bash
chmod +x scripts/ingest-signal.sh scripts/validate-docs.sh scripts/read-build-plan.sh scripts/poll-and-spawn.sh scripts/setup-labels.sh scripts/collect-metrics.sh scripts/nightly-cycle.sh scripts/setup-project-board.sh scripts/update-project-board.sh scripts/setup-branch-protection.sh
```

---

## Phase 5: Verification

Run these checks and report results:

### 5a. Config file validation
```bash
# Check YAML files are parseable
python3 -c "import yaml; yaml.safe_load(open('stack.yaml'))" 2>&1 || echo "stack.yaml: invalid YAML"
python3 -c "import yaml; yaml.safe_load(open('pipeline.yaml'))" 2>&1 || echo "pipeline.yaml: invalid YAML"
```

If python3/pyyaml isn't available, use a basic grep check:
```bash
grep '^mode:' pipeline.yaml
grep '^project_name:' stack.yaml
```

### 5b. CODEOWNERS check
```bash
# Should NOT contain the placeholder
grep -c 'your-github-username' .github/CODEOWNERS && echo "WARNING: CODEOWNERS still has placeholder" || echo "CODEOWNERS: OK"
```

### 5c. Labels check
```bash
gh label list --json name -q '.[].name' | grep 'pipeline:' | sort
```

### 5d. Git status
```bash
git status --short
```

Show the user what files were changed and suggest they commit:

```
git add -A
git commit -m "feat: initialize Build-Pipe pipeline"
```

---

## Phase 5b: Project Board Automation (Optional)

The project board was created in Phase 4f. For it to auto-update when workflows run, the user needs a Personal Access Token stored as a repository secret. This is optional — the board works for manual tracking without it.

Explain to the user: "Your project board is ready. For it to auto-update as signals flow through the pipeline, you need a Personal Access Token. This takes about 2 minutes. Want to set it up now?"

If yes, walk them through:

1. "Go to https://github.com/settings/tokens?type=beta"
2. "Click 'Generate new token'"
3. "Name it 'Build-Pipe Project Board'"
4. "Under 'Repository access', select your repo"
5. "Under 'Permissions', enable: Projects (read/write) and Contents (read/write)"
6. "Generate and copy the token"
7. Store it:
   ```bash
   gh secret set PROJECT_TOKEN
   ```
   (Paste the token when prompted)

If the user skips this, workflows will gracefully skip board updates.

---

## Phase 6: Next Steps Summary

After everything is configured, give the user a clear summary:

1. **What's set up:** List all config changes made (tech stack, pipeline mode, labels, CODEOWNERS, foundation docs, project board, branch protection)
2. **How to test it:** "Create a GitHub Issue with label `signal:feature` and watch the Actions tab — `signal-ingestion.yml` should fire and create a PR."
3. **Branch protection:** If setup succeeded, confirm it's active. If it failed (free plan + private repo), remind them to set it up manually when they upgrade or make the repo public.
4. **Project board:** Share the project board URL. Remind them about the PAT setup if they skipped Phase 5b.
5. **Foundation docs:** "Your project context is in `docs/00-foundation/`. Update these files as your product evolves — agents read them during discovery, architecture, and specification stages."
6. **Agent Orchestrator (if ao is installed):** "Start ao with `ao start`, then run `./scripts/poll-and-spawn.sh {project-slug} &` to enable auto-dispatch. Run `ao dashboard` to open the monitoring UI."
7. **Agent Orchestrator (if ao is NOT installed):** "Find pending work with `gh issue list --label 'pipeline:agent-task' --state open` and process them manually with `claude`. You can install ao later by running `/setup` again or manually: `gh repo clone ComposioHQ/agent-orchestrator ~/.agent-orchestrator && cd ~/.agent-orchestrator && pnpm install && pnpm build && npm link -g packages/cli`."

---

## Important Behaviors

- **Be conversational, not robotic.** Don't dump all questions at once. Group them naturally.
- **Auto-detect everything possible.** The user should only answer questions you can't figure out from their environment.
- **Validate inputs.** If they give a GitHub org/repo, verify it exists with `gh repo view`. If they give a username, verify with `gh api users/{name}`.
- **Idempotent.** If the user runs `/setup` again, don't break things. Check if labels already exist before creating. Check if CODEOWNERS already has a real username before replacing.
- **Don't touch files the user didn't configure.** If they skip a tech stack field, leave it as the empty string default.
