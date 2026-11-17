#!/usr/bin/env bash
# Facilitator review tool. One command, one PR at a time, friendly replies built in.
#
#   bash scripts/review.sh          Show the queue, then review the ready PRs one by one
#   bash scripts/review.sh list     Only show the queue
#   bash scripts/review.sh 12       Review PR #12
#
# Every decision is appended to the review log (REVIEW_LOG in config.sh), which
# lives OUTSIDE this repo because the repo is public. Use it for grading.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/config.sh
R="$ORG/$REPO"
LOG="${REVIEW_LOG:-../review-log.csv}"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

bold=$'\e[1m'; dim=$'\e[2m'; grn=$'\e[32m'; red=$'\e[31m'; yel=$'\e[33m'; off=$'\e[0m'

# ---------------------------------------------------------------- queue
load_queue() {
  gh pr list -R "$R" --state open --limit 40 \
    --json number,title,author,createdAt,labels,statusCheckRollup,reviews,commits > "$TMP/prs.json"
  python3 - "$TMP/prs.json" roster.csv > "$TMP/queue.txt" <<'PY'
import csv, json, sys
prs = json.load(open(sys.argv[1]))
roster = {r["github_username"].strip().lower(): r for r in csv.DictReader(open(sys.argv[2])) if r.get("github_username")}

def guard(p):
    runs = [c for c in p["statusCheckRollup"] if c.get("name") == "folder-guard"]
    if not runs: return "none"
    last = max(runs, key=lambda c: c.get("startedAt") or "")
    if last.get("status") != "COMPLETED": return "checking"
    return last.get("conclusion", "").lower()

by_author = {}
for p in prs: by_author.setdefault(p["author"]["login"].lower(), []).append(p["number"])

for p in sorted(prs, key=lambda p: p["createdAt"]):
    login = p["author"]["login"]
    r = roster.get(login.lower())
    who = f'{r["student_id"]} {r["first_name"]} {r["last_initial"]}' if r else f"? {login}"
    labels = {l["name"] for l in p["labels"]}
    weeks = ",".join(sorted(l for l in labels if l.startswith("week-"))) or "-"
    g = guard(p)
    last_commit = max((c["committedDate"] for c in p["commits"]), default="")
    asked = [rv["submittedAt"] for rv in p["reviews"] if rv["state"] == "CHANGES_REQUESTED"]
    if g in ("failure", "error"):
        bucket = "BLOCKED"
    elif g in ("checking", "none"):
        bucket = "CHECKING"
    elif asked and max(asked) > last_commit:
        bucket = "WAITING"
    else:
        bucket = "READY"
    updated = " (updated after your feedback)" if asked and bucket == "READY" else ""
    dup = [n for n in by_author[login.lower()] if n != p["number"]]
    note = (f" ⚠ also open: " + ", ".join(f"#{n}" for n in dup)) if dup else ""
    print("\t".join([bucket, str(p["number"]), who, weeks, p["title"][:50] + updated + note]))
PY
}

show_queue() {
  local b label colour
  for b in READY WAITING BLOCKED CHECKING; do
    case $b in
      READY)    label="Ready for you";                         colour=$grn ;;
      WAITING)  label="Waiting on student (you asked for changes)"; colour=$yel ;;
      BLOCKED)  label="Blocked by folder-guard (bot has told them how to fix)"; colour=$red ;;
      CHECKING) label="Robot still checking";                  colour=$dim ;;
    esac
    local rows; rows=$(grep "^$b	" "$TMP/queue.txt" || true)
    [ -z "$rows" ] && continue
    echo; echo "${colour}${bold}$label ($(echo "$rows" | wc -l | tr -d ' '))${off}"
    echo "$rows" | awk -F'\t' '{ printf "  #%-4s %-24s %-9s %s\n", $2, $3, $4, $5 }'
  done
  [ -s "$TMP/queue.txt" ] || echo "${grn}No open pull requests. All caught up! 🎉${off}"
  echo
}

# ---------------------------------------------------------------- helpers
roster_field() { # roster_field <login> <column-number>
  awk -F, -v u="$(echo "$1" | tr '[:upper:]' '[:lower:]')" -v c="$2" \
    'NR>1 { g=tolower($4); gsub(/[ \r]/,"",g); if (g==u) { v=$c; gsub(/\r/,"",v); print v; exit } }' roster.csv
}

log() { # log <pr> <id> <name> <week> <decision> <note>
  [ -f "$LOG" ] || echo "date,pr,student_id,name,week,decision,note" > "$LOG"
  local note="${6//,/;}"; note="${note//$'\n'/ }"
  echo "$(date '+%Y-%m-%d %H:%M'),$1,$2,$3,$4,$5,$note" >> "$LOG"
}

ask() { local a; read -r -p "$1" a </dev/tty; echo "$a"; }

# ---------------------------------------------------------------- review one PR
review_pr() {
  local n=$1
  gh pr view "$n" -R "$R" --json number,title,author,body,files,headRefName,url,labels,state > "$TMP/pr.json"
  local state login branch url title
  state=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["state"])' "$TMP/pr.json")
  [ "$state" = "OPEN" ] || { echo "PR #$n is $state, skipping."; return; }
  read -r login branch url < <(python3 -c 'import json,sys;p=json.load(open(sys.argv[1]));print(p["author"]["login"],p["headRefName"],p["url"])' "$TMP/pr.json")
  title=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["title"])' "$TMP/pr.json")

  local sid first folder week
  sid=$(roster_field "$login" 1); first=$(roster_field "$login" 2); folder=$(roster_field "$login" 5)
  [ -n "$first" ] || first="$login"
  week=$(python3 -c 'import json,sys;p=json.load(open(sys.argv[1]));print(",".join(sorted(l["name"] for l in p["labels"] if l["name"].startswith("week-"))) or "-")' "$TMP/pr.json")

  clear 2>/dev/null || true
  echo "${bold}PR #$n  ·  $sid $first  ·  $week${off}"
  echo "${dim}$title  ·  branch $branch${off}"
  echo "${dim}$url${off}"
  echo
  echo "${bold}Their notes${off}"
  python3 - "$TMP/pr.json" <<'PY'
import json, re, sys
body = json.load(open(sys.argv[1]))["body"] or ""
body = re.sub(r"<!--.*?-->", "", body, flags=re.S)
lines = [l for l in body.splitlines() if l.strip() and not l.startswith("## My submission")]
print("\n".join("  " + l for l in lines[:14]) or "  (empty)")
PY
  echo
  echo "${bold}Files${off}"
  python3 -c '
import json,sys
for f in json.load(open(sys.argv[1]))["files"]:
    print(f"  +{f[\"additions\"]:<4} -{f[\"deletions\"]:<4} {f[\"path\"]}")' "$TMP/pr.json"
  echo
  # Text changes inline; binary files (docx, sb3, images) need the browser.
  gh pr diff "$n" -R "$R" --color=never 2>/dev/null \
    | grep -vE '^(diff --git|index |--- |\+\+\+ |new file mode|Binary files)' \
    | awk -v g="$grn" -v r="$red" -v d="$dim" -v o="$off" \
        '/^\+/{print g $0 o; next} /^-/{print r $0 o; next} /^@@/{print d $0 o; next} {print}' \
    | head -60 || true
  if python3 -c 'import json,sys;sys.exit(0 if any(not f["path"].endswith((".md",".txt",".py",".js",".html",".css",".json",".csv")) for f in json.load(open(sys.argv[1]))["files"]) else 1)' "$TMP/pr.json"; then
    echo; echo "${yel}This PR has files that can't be shown here (e.g. .docx, .sb3, images). Press o to open it in the browser.${off}"
  fi

  while true; do
    echo
    echo "${bold}[a]${off} approve + merge   ${bold}[c]${off} ask for changes   ${bold}[d]${off} close as duplicate   ${bold}[o]${off} open in browser   ${bold}[s]${off} skip   ${bold}[q]${off} quit"
    case "$(ask '> ')" in
      a|A)
        local note; note=$(ask "Personal note for $first (Enter to skip): ")
        gh pr review "$n" -R "$R" --approve --body "✅ Accepted. Great work, $first! ${note}

Your work is now saved in \`main\`. 🎉" >/dev/null
        gh pr edit "$n" -R "$R" --remove-label needs-changes >/dev/null 2>&1 || true
        if gh pr merge "$n" -R "$R" --squash >/dev/null; then
          echo "${grn}✔ Approved and merged #$n${off}"; log "$n" "$sid" "$first" "$week" approved "$note"
        else
          echo "${red}Approved, but the merge failed (is folder-guard green?). Check: $url${off}"
          log "$n" "$sid" "$first" "$week" approved-not-merged "$note"
        fi
        return ;;
      c|C)
        echo "What needs fixing? (type one or more numbers, e.g. 1 3)"
        echo "  1  Their text is hidden inside <!-- --> marks"
        echo "  2  A file is outside their folder / in the wrong place"
        echo "  3  File must go inside week-0X/lab or week-0X/homework"
        echo "  4  The pull request description is empty"
        echo "  5  Something else (you type it)"
        local picks items="" own=""; picks=$(ask '> ')
        for p in $picks; do case $p in
          1) items+="- Your sentences are inside \`<!--\` and \`-->\` marks, so they are **hidden** on the page. Delete the \`<!--\` and \`-->\` around your sentences and keep the words."$'\n' ;;
          2) items+="- Your files must be inside your own folder: \`students/$folder/\`. Please move the file there."$'\n' ;;
          3) items+="- Please put your file inside the right week folder: \`students/$folder/week-0X/lab/\` or \`.../homework/\`."$'\n' ;;
          4) items+="- Please fill in the boxes in the description at the top of this pull request (click **⋯ → Edit**)."$'\n' ;;
          5) own=$(ask "Your message: "); items+="- $own"$'\n' ;;
        esac; done
        [ -n "$items" ] || { echo "Nothing chosen."; continue; }
        gh pr review "$n" -R "$R" --request-changes --body "Almost there, $first! 👍 Please fix this:

$items
**How to fix:** on the main page, switch the branch dropdown from \`main\` to \`$branch\`, make the change, and choose **Commit directly to the \`$branch\` branch**.
This pull request updates by itself. **No need to open a new one.**" >/dev/null
        gh pr edit "$n" -R "$R" --add-label needs-changes >/dev/null 2>&1 || true
        echo "${yel}✔ Asked $first for changes on #$n${off}"
        log "$n" "$sid" "$first" "$week" changes-requested "$picks $own"
        return ;;
      d|D)
        local others keep
        others=$(gh pr list -R "$R" --state open --author "$login" --json number --jq ".[] | select(.number != $n) | .number" | tr '\n' ' ')
        keep=$(ask "Which PR should $first keep? [${others%% *}]: "); keep=${keep:-${others%% *}}; keep=${keep#\#}
        [ -n "$keep" ] || { echo "No other open PR found for $first."; continue; }
        gh pr close "$n" -R "$R" --comment "Hi $first, you have another pull request (#$keep) for the same work, so I'm closing this one. Keep working in #$keep. 👍" >/dev/null
        echo "${dim}✔ Closed #$n (keeping #$keep)${off}"
        log "$n" "$sid" "$first" "$week" closed-duplicate "kept #$keep"
        return ;;
      o|O) gh pr view "$n" -R "$R" --web >/dev/null 2>&1 || open "$url" ;;
      s|S|"") echo "Skipped #$n"; return ;;
      q|Q) exit 0 ;;
    esac
  done
}

# ---------------------------------------------------------------- main
case "${1:-}" in
  list)
    load_queue; show_queue ;;
  ''|all)
    load_queue; show_queue
    ready=$(awk -F'\t' '$1=="READY"{print $2}' "$TMP/queue.txt")
    [ -n "$ready" ] || exit 0
    [ "$(ask "Review the $(echo "$ready" | wc -l | tr -d ' ') ready PR(s) now, oldest first? [Y/n] ")" = n ] && exit 0
    for n in $ready; do review_pr "$n"; done
    echo; echo "${grn}${bold}Done.${off} Decisions saved to $LOG"
    load_queue; show_queue ;;
  *)
    review_pr "${1#\#}" ;;
esac
