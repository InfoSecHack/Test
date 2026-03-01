# ghostgates-testbed

Intentionally misconfigured repo for testing [GhostGates](https://github.com/infosechack-labs/ghostgates) — a CI/CD gate bypass analysis engine.

**⚠️ This repo is deliberately insecure. Do not use these configurations in production.**

## Quick Start

```bash
# 1. Create a new repo on GitHub: infosechack-labs/ghostgates-testbed
# 2. Push this code
git init
git add .
git commit -m "Initial commit: GhostGates testbed"
git branch -M main
git remote add origin git@github.com:infosechack-labs/ghostgates-testbed.git
git push -u origin main

# 3. Run the setup script to configure GitHub settings via API
export GITHUB_TOKEN=your_token_here
bash setup_test_repo.sh infosechack-labs/ghostgates-testbed

# 4. Scan with GhostGates
ghostgates scan --org infosechack-labs --repos ghostgates-testbed -v
```

## What the Setup Script Configures

The script uses the GitHub API to create the exact misconfigurations that trigger all 15 rules:

| Setting | Config | Rules Triggered |
|---------|--------|-----------------|
| Branch protection on `main` | 1 review, enforce_admins=OFF, dismiss_stale=OFF, codeowners=OFF | BP-001, BP-002, BP-003 |
| No protection on `staging`, `production`, `release` | Branches created but unprotected | BP-004 |
| Actions permissions | can_approve_pull_request_reviews=true, default=write | BP-005, WF-002 (inherited) |
| Ruleset `main-audit-only` | enforcement=evaluate | BP-006 |
| Environment `production` | 1 reviewer, all branches allowed | ENV-002 |
| Environment `staging` | wait_timer=15min, no reviewers | ENV-001, ENV-003 |
| Repo visibility | Public | WF-004 |

## Workflow Files (already in repo)

| File | Purpose | Rules Triggered |
|------|---------|-----------------|
| `pr_target_unsafe.yml` | `pull_request_target` + checkout PR head + `npm install` | **WF-001 (CRITICAL)**, WF-002 |
| `deploy_unsafe.yml` | `write-all` perms + `secrets: inherit` to external workflow | WF-002, WF-003 |
| `post_ci_deploy.yml` | `workflow_run` trigger in public repo | WF-004 |
| `oidc_deploy.yml` | `id-token: write` without environment gate | OIDC-001, OIDC-002 |
| `ci.yml` | Clean baseline CI (should NOT trigger findings) | — |
| `deploy_prod.yml` | References `production` environment | — |

## Expected Scan Results (all 15 rules)

```
CRITICAL  GHOST-WF-001   pull_request_target with PR head checkout
HIGH      GHOST-BP-001   Admin bypass of required reviews
HIGH      GHOST-BP-005   Workflows can approve their own PRs
HIGH      GHOST-BP-006   Ruleset in evaluate mode (not enforced)
HIGH      GHOST-ENV-001  Environment with no required reviewers (staging)
HIGH      GHOST-WF-002   Workflow with write-all permissions
HIGH      GHOST-WF-003   Reusable workflow with secrets: inherit
HIGH      GHOST-WF-004   Workflow exposes secrets to fork PRs
HIGH      GHOST-OIDC-001 Default OIDC subject claim
HIGH      GHOST-OIDC-002 OIDC token without environment gate
MEDIUM    GHOST-BP-002   Stale review approval persistence
MEDIUM    GHOST-BP-004   Deployment branches lack protection
MEDIUM    GHOST-ENV-002  Environment allows deployment from any branch
MEDIUM    GHOST-ENV-003  Wait timer as only protection (staging)
LOW       GHOST-BP-003   Required reviews without CODEOWNERS enforcement
```

## Token Permissions Needed

The setup script needs a token with:
- `repo` (full control) — or fine-grained: Repository Administration: Write
- `admin:org` — for org-level Actions permissions (optional, those will gracefully 403)

The GhostGates scan needs:
- `repo` (read) — or fine-grained: Repository: Read + Organization: Read

## Manual Setup (if script fails)

If the API script has issues, configure these manually:

1. **Settings → Branches → Add rule for `main`**: Require 1 review, leave all three checkboxes OFF (enforce admins, dismiss stale, codeowners)
2. **Settings → Environments**: Create `production` (add yourself as reviewer, leave branches as "All"), `staging` (set 15min timer, no reviewers), `dev` (no protections)
3. **Settings → Actions → General**: Enable "Allow GitHub Actions to create and approve pull requests", set default permissions to "Read and write"
4. **Settings → Rules → Rulesets**: Create `main-audit-only` targeting default branch, enforcement = Evaluate, add "Require pull requests" rule
5. **Settings → General**: Make repo Public (for WF-004)
6. **Create branches**: `staging`, `production`, `release` from main (don't add protection)

## Cleanup

To tear down after testing:

```bash
# Delete the repo
gh repo delete infosechack-labs/ghostgates-testbed --yes

# Or just delete local artifacts
rm ghostgates.db
```
