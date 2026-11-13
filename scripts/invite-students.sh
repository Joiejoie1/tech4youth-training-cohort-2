#!/usr/bin/env bash
# Invites every student in roster.csv who has a GitHub username, with Write access.
# Write lets them push their own branches. The ruleset still protects main.
# Safe to run again: people already invited are skipped.
#
# Usage:  bash scripts/invite-students.sh
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/config.sh
R="$ORG/$REPO"

tail -n +2 roster.csv | tr -d '\r' | while IFS=, read -r id first last gh folder; do
  if [ -z "$id" ] || [ "${id#\#}" != "$id" ]; then continue; fi
  gh=$(echo "$gh" | tr -d ' ')
  if [ -z "$gh" ]; then echo "… $id $first: no GitHub username yet, skipped"; continue; fi
  if gh api "repos/$R/collaborators/$gh" >/dev/null 2>&1; then
    echo "✔ $id $first (@$gh) already has access"; continue
  fi
  if gh api -X PUT "repos/$R/collaborators/$gh" -f permission=push >/dev/null; then
    echo "✉ $id $first (@$gh) invited"
  else
    echo "✖ $id $first (@$gh) FAILED: check the username is spelled correctly"
  fi
done
echo "Students must accept within 7 days: https://github.com/$R/invitations"
