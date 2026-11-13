#!/usr/bin/env bash
# Saves a permanent snapshot of main at the end of a week.
# Usage:  bash scripts/tag-week.sh 01
set -euo pipefail
cd "$(dirname "$0")/.."
w="${1:?Give the week number, e.g. 01}"
git checkout main && git pull --ff-only
git tag -a "week-$w-final" -m "End of week $w snapshot"
git push origin "week-$w-final"
echo "✅ Tagged week-$w-final"
