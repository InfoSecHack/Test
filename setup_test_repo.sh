#!/usr/bin/env bash
#
# setup_test_repo.sh
#
# Configures a GitHub repo to trigger all 15 GhostGates rules.
# Requires: GITHUB_TOKEN env var, gh CLI or curl.
#
# Usage:
#   export GITHUB_TOKEN=ghp_xxx
#   bash setup_test_repo.sh <org>/<repo>
#
# Example:
#   bash setup_test_repo.sh infosechack-labs/ghostgates-testbed

set -euo pipefail

REPO="${1:?Usage: $0 <org/repo>}"
ORG="${REPO%%/*}"
REPO_NAME="${REPO##*/}"

API="https://api.github.com"
AUTH="Authorization: Bearer ${GITHUB_TOKEN:?Set GITHUB_TOKEN}"
ACCEPT="Accept: application/vnd.github+json"
VERSION="X-GitHub-Api-Version: 2022-11-28"

call() {
    local method="$1" path="$2"
    shift 2
    curl -s -X "$method" "$API$path" -H "$AUTH" -H "$ACCEPT" -H "$VERSION" "$@"
}

echo "═══════════════════════════════════════════════════"
echo "  GhostGates Test Repo Setup"
echo "  Target: $REPO"
echo "═══════════════════════════════════════════════════"
echo ""

# ──────────────────────────────────────────────────
# 1. Make repo public (needed for WF-004)
# ──────────────────────────────────────────────────
echo "[1/7] Setting repo to public..."
call PATCH "/repos/$REPO" \
    -d '{"visibility": "public"}' > /dev/null 2>&1 || echo "  (may need org owner perms — set manually if this fails)"

# ──────────────────────────────────────────────────
# 2. Branch protection on main (BP-001, BP-002, BP-003)
#    - 1 required review
#    - enforce_admins: OFF  → BP-001
#    - dismiss_stale: OFF   → BP-002
#    - codeowners: OFF      → BP-003
# ──────────────────────────────────────────────────
echo "[2/7] Setting branch protection on main..."
call PUT "/repos/$REPO/branches/main/protection" \
    -d '{
        "required_status_checks": null,
        "enforce_admins": false,
        "required_pull_request_reviews": {
            "required_approving_review_count": 1,
            "dismiss_stale_reviews": false,
            "require_code_owner_reviews": false
        },
        "restrictions": null,
        "allow_force_pushes": false,
        "allow_deletions": false
    }' > /dev/null
echo "  ✓ Branch protection set (enforce_admins=OFF, dismiss_stale=OFF, codeowners=OFF)"

# ──────────────────────────────────────────────────
# 3. Create environments (ENV-001, ENV-002, ENV-003)
# ──────────────────────────────────────────────────
echo "[3/7] Creating environments..."

# Get your user ID for reviewer
USER_ID=$(call GET "/user" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")

# production: reviewer + all branches → ENV-002
call PUT "/repos/$REPO/environments/production" \
    -d "{
        \"wait_timer\": 0,
        \"reviewers\": [{\"type\": \"User\", \"id\": $USER_ID}],
        \"deployment_branch_policy\": null
    }" > /dev/null
echo "  ✓ production: reviewer=$USER_ID, all branches (triggers ENV-002)"

# staging: wait timer only, no reviewers → ENV-003
call PUT "/repos/$REPO/environments/staging" \
    -d '{
        "wait_timer": 15,
        "reviewers": [],
        "deployment_branch_policy": null
    }' > /dev/null
echo "  ✓ staging: wait_timer=15min, no reviewers (triggers ENV-001 + ENV-003)"

# dev: no protections (shouldn't trigger anything)
call PUT "/repos/$REPO/environments/dev" \
    -d '{"wait_timer": 0, "reviewers": []}' > /dev/null
echo "  ✓ dev: no protections (should not trigger)"

# ──────────────────────────────────────────────────
# 4. Actions permissions — allow workflow PR approval (BP-005)
# ──────────────────────────────────────────────────
echo "[4/7] Enabling workflow PR approval..."
call PUT "/repos/$REPO/actions/permissions" \
    -d '{"enabled": true, "allowed_actions": "all"}' > /dev/null 2>&1 || true
call PUT "/repos/$REPO/actions/permissions/workflow" \
    -d '{
        "default_workflow_permissions": "write",
        "can_approve_pull_request_reviews": true
    }' > /dev/null
echo "  ✓ can_approve_pull_request_reviews=true, default_permissions=write"

# ──────────────────────────────────────────────────
# 5. Create a ruleset in evaluate mode (BP-006)
# ──────────────────────────────────────────────────
echo "[5/7] Creating ruleset in evaluate mode..."
call POST "/repos/$REPO/rulesets" \
    -d '{
        "name": "main-audit-only",
        "target": "branch",
        "enforcement": "evaluate",
        "conditions": {
            "ref_name": {
                "include": ["~DEFAULT_BRANCH"],
                "exclude": []
            }
        },
        "rules": [
            {"type": "pull_request", "parameters": {"required_approving_review_count": 2}},
            {"type": "required_status_checks", "parameters": {"required_status_checks": [{"context": "ci"}]}}
        ],
        "bypass_actors": []
    }' > /dev/null
echo "  ✓ Ruleset 'main-audit-only' in evaluate mode (triggers BP-006)"

# ──────────────────────────────────────────────────
# 6. Create placeholder branches (BP-004 detect targets)
# ──────────────────────────────────────────────────
echo "[6/7] Creating deployment branches..."
MAIN_SHA=$(call GET "/repos/$REPO/git/ref/heads/main" | python3 -c "import sys,json; print(json.load(sys.stdin)['object']['sha'])")

for branch in staging production release; do
    call POST "/repos/$REPO/git/refs" \
        -d "{\"ref\": \"refs/heads/$branch\", \"sha\": \"$MAIN_SHA\"}" > /dev/null 2>&1 || true
    echo "  ✓ Branch '$branch' created (unprotected → triggers BP-004)"
done

# ──────────────────────────────────────────────────
# 7. Summary
# ──────────────────────────────────────────────────
echo ""
echo "[7/7] Setup complete!"
echo ""
echo "Expected GhostGates findings:"
echo "  GHOST-BP-001  Admin bypass of required reviews      (enforce_admins=OFF)"
echo "  GHOST-BP-002  Stale review approval persistence     (dismiss_stale=OFF)"
echo "  GHOST-BP-003  No CODEOWNERS enforcement             (codeowners=OFF)"
echo "  GHOST-BP-004  Deployment branches unprotected       (staging/production/release)"
echo "  GHOST-BP-005  Workflows can approve own PRs         (can_approve=ON)"
echo "  GHOST-BP-006  Ruleset in evaluate mode              (main-audit-only)"
echo "  GHOST-ENV-001 Environment no reviewers              (staging)"
echo "  GHOST-ENV-002 Environment allows any branch deploy  (production)"
echo "  GHOST-ENV-003 Wait timer only protection            (staging)"
echo "  GHOST-WF-001  pull_request_target + checkout HEAD   (pr_target_unsafe.yml) [CRITICAL]"
echo "  GHOST-WF-002  Workflow with write-all               (pr_target_unsafe.yml, deploy_unsafe.yml)"
echo "  GHOST-WF-003  secrets: inherit to external workflow  (deploy_unsafe.yml)"
echo "  GHOST-WF-004  Fork PR secrets via workflow_run      (post_ci_deploy.yml) [needs public repo]"
echo "  GHOST-OIDC-001 Default OIDC subject claim           (oidc_deploy.yml)"
echo "  GHOST-OIDC-002 OIDC without environment gate        (oidc_deploy.yml)"
echo ""
echo "Run scan:"
echo "  ghostgates scan --org $ORG -v"
