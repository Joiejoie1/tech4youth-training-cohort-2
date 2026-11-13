#!/usr/bin/env bash
# One-time GitHub setup for the repo: settings, labels and the ruleset protecting main.
# Run AFTER the repo has been created and pushed (see INSTRUCTOR-SETUP.md).
#
# Usage:  bash scripts/setup-github.sh
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/config.sh
R="$ORG/$REPO"

echo "→ Repo settings: squash merge only, delete branches after merge"
gh api -X PATCH "repos/$R" \
  -F allow_squash_merge=true -F allow_merge_commit=false -F allow_rebase_merge=false \
  -F delete_branch_on_merge=true -F allow_auto_merge=false >/dev/null

echo "→ Labels"
for w in $(seq -f "%02g" 1 "$WEEKS"); do
  gh label create "week-$w" --repo "$R" --color FFE17C --description "Week $w submission" --force
done
gh label create lab           --repo "$R" --color 1D76DB --description "Lab work"            --force
gh label create homework      --repo "$R" --color 5319E7 --description "Homework"            --force
gh label create needs-changes --repo "$R" --color D93F0B --description "Please fix and push again" --force
gh label create approved      --repo "$R" --color 0E8A16 --description "Reviewed and approved" --force
gh label create late          --repo "$R" --color 272727 --description "Opened after the deadline" --force

echo "→ Ruleset protecting main"
# Delete an older copy so the script can be run again safely
old=$(gh api "repos/$R/rulesets" --jq '.[] | select(.name=="protect-main") | .id' || true)
[ -n "$old" ] && gh api -X DELETE "repos/$R/rulesets/$old" >/dev/null

gh api -X POST "repos/$R/rulesets" --input - >/dev/null <<JSON
{
  "name": "protect-main",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
  "bypass_actors": [
    { "actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "always" }
  ],
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    { "type": "pull_request", "parameters": {
        "required_approving_review_count": 1,
        "require_code_owner_review": true,
        "dismiss_stale_reviews_on_push": true,
        "require_last_push_approval": false,
        "required_review_thread_resolution": false,
        "allowed_merge_methods": ["squash"]
    } },
    { "type": "required_status_checks", "parameters": {
        "strict_required_status_checks_policy": false,
        "required_status_checks": [ { "context": "folder-guard" } ]
    } }
  ]
}
JSON

echo "✅ Done. Check: https://github.com/$R/settings/rules"
