#!/usr/bin/env bash
# Creates a folder for every student in roster.csv.
# Fills in the "folder" column if it is empty: T4Y-C2-001-amina-b
# Safe to run again: existing folders and files are never overwritten.
#
# Usage (from the repo root):  bash scripts/scaffold-students.sh
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/config.sh

ROSTER=roster.csv
TMP=$(mktemp)
head -n1 "$ROSTER" > "$TMP"
count=0

tail -n +2 "$ROSTER" | tr -d '\r' | while IFS= read -r line; do
  IFS=, read -r id first last gh folder <<< "$line"
  # Keep blank lines and comment lines exactly as they are
  if [ -z "$id" ] || [ "${id#\#}" != "$id" ]; then echo "$line" >> "$TMP"; continue; fi

  if [ -z "$folder" ]; then
    slug=$(printf '%s-%s' "$first" "$last" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//; s/-$//')
    folder="$id-$slug"
  fi
  echo "$id,$first,$last,$gh,$folder" >> "$TMP"

  base="students/$folder"
  for w in $(seq -f "%02g" 1 "$WEEKS"); do
    for kind in lab homework; do
      mkdir -p "$base/week-$w/$kind"
      [ -e "$base/week-$w/$kind/.gitkeep" ] || touch "$base/week-$w/$kind/.gitkeep"
    done
  done

  if [ ! -e "$base/README.md" ]; then
    cat > "$base/README.md" <<MD
# $first $last. — $id

👋 Hi, I'm $first.

**Why I joined Tech4Youth:**
<!-- Write one sentence here -->

**What I want to build with AI:**
<!-- Write one sentence here -->

## My work
| Week | Lab | Homework |
|------|-----|----------|
$(for w in $(seq -f "%02g" 1 "$WEEKS"); do echo "| $w | [lab](week-$w/lab) | [homework](week-$w/homework) |"; done)
MD
  fi
  echo "✔ $base"
done

mv "$TMP" "$ROSTER"
echo "Done. Check roster.csv: the folder column is now filled in."
