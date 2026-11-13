# Facilitator setup and weekly routine

Org: **`Tech4Youth-GIZ-Abuja`** (https://github.com/Tech4Youth-GIZ-Abuja) · Repo: **`tech4youth-training-cohort-2`** (public for now, private later)
All names live in [`scripts/config.sh`](scripts/config.sh).

---

## A. One-time setup

### 1. Organization plan: the repo is PUBLIC for now
The org is on the **Free** plan. Rulesets on a **private** repo need **GitHub Team**,
so the repo is **public** until the GitHub for Nonprofits Team plan is approved
(https://github.com/solutions/industry/nonprofits).

**While the repo is public, anyone on the internet can read it:**
- Folders use **first name + last initial** only. Never put full names in the roster.
- Students must not upload photos of themselves, phone numbers, addresses or other personal details.
- `roster.csv` shows GitHub usernames publicly. Their GitHub profiles are public anyway.

**When Team is active, switch to private:**
1. Settings → General → Danger Zone → **Change visibility** → Private
2. `bash scripts/setup-github.sh` (re-applies the ruleset; safe to run again)
3. Check https://github.com/Tech4Youth-GIZ-Abuja/tech4youth-training-cohort-2/settings/rules shows `protect-main` as **Active**

> ⚠️ If you switch to private **before** Team is active, the ruleset stops working and students could push straight to `main`.

### 2. Give the GitHub CLI org permissions
```bash
gh auth refresh -h github.com -s admin:org,workflow
```

### 3. Create the repo and push this folder
```bash
cd tech4youth-training-cohort-2
git init -b main
git add .
git commit -m "Set up cohort 2 student work repo"
gh repo create Tech4Youth-GIZ-Abuja/tech4youth-training-cohort-2 --private --source . --push
```

### 4. Apply settings, labels and the ruleset protecting main
```bash
bash scripts/setup-github.sh
```
This does the following:
- Squash merge only, and branches are deleted automatically after merge.
- Labels: `week-01`…`week-08`, `lab`, `homework`, `needs-changes`, `approved`, `late`.
- Ruleset `protect-main`: PR required, 1 Code Owner approval, `folder-guard` check must pass, no force-push or delete. Repo admins (you) can bypass.

### 5. Add TAs (optional)
- Add their usernames to [`.github/instructors.txt`](.github/instructors.txt) (one per line) and [`.github/CODEOWNERS`](.github/CODEOWNERS).
- Invite them with **Maintain** access.

---

## B. Adding students

### 1. Fill in the roster (names and IDs now, usernames later)
Edit [`roster.csv`](roster.csv). Leave `folder` empty and the script fills it in:
```csv
student_id,first_name,last_initial,github_username,folder
T4Y-C2-001,Amina,B,,
T4Y-C2-002,David,O,,
```
Then create the folders and push:
```bash
bash scripts/scaffold-students.sh
git add . && git commit -m "Add student folders" && git push
```
> As an admin you bypass the ruleset, so you can push to main directly.
> Once you've scaffolded, **never rename a folder**: students' work lives there.

### 2. When you collect GitHub usernames
1. Put each one in the `github_username` column, commit and push to `main`.
2. Run:
```bash
bash scripts/invite-students.sh
```
3. In class, students accept the invite at https://github.com/Tech4Youth-GIZ-Abuja/tech4youth-training-cohort-2/invitations
   - **Invites expire after 7 days.** If one expires, run the script again.
   - folder-guard rejects any student whose username is missing from `roster.csv`, with a clear message.

---

## C. Dry run (before inviting students)

1. Create a second GitHub account, e.g. `t4y-test`. Add `T4Y-C2-099,Test,X,t4y-test,` to the roster. Scaffold, push and invite it.
2. Logged in as `t4y-test`, open these 3 PRs:

| Test | Expected |
|---|---|
| Upload a file to `students/T4Y-C2-099-test-x/week-01/lab/` | ✅ folder-guard passes, labels `week-01` + `lab` |
| Edit a file in another student's folder | ❌ fails and names the file |
| Edit `.github/workflows/folder-guard.yml` to skip the check | ❌ still fails, because the copy on main runs |

3. Confirm the test account **cannot** merge its own PR or push to `main`.
4. Remove the test row and folder afterwards, or keep them for demos.

---

## D. Weekly routine

**Students:** follow [README.md](README.md): branch `week-0X/ID` → PR.

**You:**
1. Filter PRs by label: https://github.com/Tech4Youth-GIZ-Abuja/tech4youth-training-cohort-2/pulls?q=is%3Apr+label%3Aweek-01
2. On-time check: compare the time the PR was **opened** with the deadline. Add the `late` label if needed.
3. Review on the **Files changed** tab:
   - Changes needed → **Request changes** + `needs-changes` label
   - Good → **Approve** → **Squash and merge**
4. Record grades in your **private** sheet, not in the repo, because all students can read it.
5. End of week: save a snapshot.
   ```bash
   bash scripts/tag-week.sh 01
   ```
   Later you can browse everyone's work as of that deadline at `.../tree/week-01-final`.

---

## E. Troubleshooting

| Problem | Fix |
|---|---|
| folder-guard says "not in roster.csv" | Add or fix their username in `roster.csv` on `main`. Then on the PR, close and reopen it (or have the student push again) to re-run the check |
| Student used the wrong branch name | Doesn't matter. folder-guard checks files, not branch names. Labels come from file paths too |
| Student uploaded to the wrong week folder | Ask them to delete it and upload again in the right folder, on the same branch |
| Student pushed a password or API key | Ask them to revoke the key **immediately**. Deleting the file does not remove it from history |
| PR shows "Review required" even after my approval | You must be listed in `CODEOWNERS` |
| Many old branches | They're deleted automatically on merge. Delete abandoned ones from the **Branches** page |
