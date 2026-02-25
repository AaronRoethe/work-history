#!/usr/bin/env bash
# generate-work-history.sh
#
# Creates or incrementally updates a git repo with one backdated commit per PR.
# On every run it re-fetches the latest PR data from GitHub Enterprise, finds
# anything not yet committed, and appends it to the local repo + pushes.
#
# Usage:
#   ./generate-work-history.sh [output-repo-path] [--no-fetch]
#
#   --no-fetch   Skip the GitHub API refresh and use existing prs-raw.jsonl
#
# Default repo path: ~/repos/work-history
#
# Prerequisites: git, jq, gh (GitHub CLI authenticated to git.taservs.net)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JSONL="$SCRIPT_DIR/prs-raw.jsonl"
REPO_DIR="${HOME}/repos/work-history"
SKIP_FETCH=false

# ── Args ──────────────────────────────────────────────────────────────────────

for arg in "$@"; do
  case "$arg" in
    --no-fetch) SKIP_FETCH=true ;;
    --*)        echo "Unknown flag: $arg"; exit 1 ;;
    *)          REPO_DIR="$arg" ;;
  esac
done

# ── Validate ──────────────────────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
  echo "Error: jq is required (brew install jq)"
  exit 1
fi

if ! command -v gh &>/dev/null; then
  echo "Error: gh CLI is required (brew install gh)"
  exit 1
fi

AUTHOR_NAME="$(git config --global user.name 2>/dev/null || echo 'Unknown')"
AUTHOR_EMAIL="$(git config --global user.email 2>/dev/null || echo 'unknown@example.com')"

# ── Re-fetch latest PR data ───────────────────────────────────────────────────

if [[ "$SKIP_FETCH" == false ]]; then
  echo "→ Fetching latest PRs from git.taservs.net..."
  GH_HOST=git.taservs.net gh api graphql --paginate \
    --jq '.data.viewer.pullRequests.nodes[]' \
    -f query='
    query($endCursor: String) {
      viewer {
        pullRequests(first: 100, after: $endCursor, orderBy: {field: CREATED_AT, direction: DESC}) {
          pageInfo { hasNextPage endCursor }
          nodes {
            number title state url
            createdAt mergedAt closedAt
            additions deletions changedFiles
            baseRefName headRefName body
            commits { totalCount }
            comments { totalCount }
            reviews(first: 1) { totalCount }
            labels(first: 10) { nodes { name } }
            repository {
              nameWithOwner name
              owner { login }
            }
          }
        }
      }
    }' > "$JSONL"
  echo "  fetched $(jq -s 'length' "$JSONL") PRs"
  echo ""
fi

if [[ ! -f "$JSONL" ]]; then
  echo "Error: prs-raw.jsonl not found. Run without --no-fetch first."
  exit 1
fi

TOTAL=$(jq -s 'length' "$JSONL")

export GIT_AUTHOR_NAME="$AUTHOR_NAME"
export GIT_AUTHOR_EMAIL="$AUTHOR_EMAIL"
export GIT_COMMITTER_NAME="$AUTHOR_NAME"
export GIT_COMMITTER_EMAIL="$AUTHOR_EMAIL"

# ── Detect mode: init vs update ───────────────────────────────────────────────

MODE="init"
if [[ -d "$REPO_DIR/.git" ]]; then
  MODE="update"
fi

echo "┌─────────────────────────────────────────────────────┐"
echo "│  Work History Sync                                  │"
echo "├─────────────────────────────────────────────────────┤"
printf "│  Mode:    %-42s│\n" "$MODE"
printf "│  Repo:    %-42s│\n" "$REPO_DIR"
printf "│  Author:  %-42s│\n" "$AUTHOR_NAME <$AUTHOR_EMAIL>"
printf "│  Total:   %-42s│\n" "$TOTAL PRs in source"
echo "└─────────────────────────────────────────────────────┘"
echo ""

# ── Helper: process a list of PRs into commits ────────────────────────────────

commit_prs() {
  local tmpfile="$1"
  local count=0
  local total_new
  total_new=$(wc -l < "$tmpfile" | tr -d ' ')

  if [[ "$total_new" -eq 0 ]]; then
    echo "  Already up to date — no new PRs to commit."
    return 0
  fi

  echo "  Committing $total_new new PRs..."
  echo ""

  while IFS= read -r pr; do
    number=$(echo "$pr"    | jq -r '.number')
    title=$(echo "$pr"     | jq -r '.title')
    state=$(echo "$pr"     | jq -r '.state')
    url=$(echo "$pr"       | jq -r '.url')
    org=$(echo "$pr"       | jq -r '.repository.owner.login')
    repo=$(echo "$pr"      | jq -r '.repository.name')
    base=$(echo "$pr"      | jq -r '.baseRefName')
    head=$(echo "$pr"      | jq -r '.headRefName')
    additions=$(echo "$pr" | jq -r '.additions // 0')
    deletions=$(echo "$pr" | jq -r '.deletions // 0')
    changed=$(echo "$pr"   | jq -r '.changedFiles // 0')
    commits=$(echo "$pr"   | jq -r '.commits.totalCount // 0')
    comments=$(echo "$pr"  | jq -r '.comments.totalCount // 0')
    reviews=$(echo "$pr"   | jq -r '.reviews.totalCount // 0')
    labels=$(echo "$pr"    | jq -r '[.labels.nodes[].name] | join(", ")')
    effective_date=$(echo "$pr" | jq -r '.effectiveDate')
    year="${effective_date:0:4}"
    date_short="${effective_date:0:10}"

    activity_file="activity/${year}.md"

    if [[ ! -f "$activity_file" ]]; then
      echo "# ${year}" > "$activity_file"
      echo "" >> "$activity_file"
    fi

    {
      echo "## ${date_short} — [${org}/${repo}#${number}](${url})"
      echo ""
      echo "**${state}** · \`${head}\` → \`${base}\`"
      echo ""
      echo "${title}"
      echo ""
      printf "| Stat | Value |\n"
      printf "|---|---|\n"
      printf "| Lines | +%s -%s |\n" "$additions" "$deletions"
      printf "| Files changed | %s |\n" "$changed"
      printf "| Commits | %s |\n" "$commits"
      printf "| Comments | %s |\n" "$comments"
      printf "| Reviews | %s |\n" "$reviews"
      if [[ -n "$labels" ]]; then
        printf "| Labels | %s |\n" "$labels"
      fi
      echo ""
      echo "---"
      echo ""
    } >> "$activity_file"

    MSG_FILE=$(mktemp)
    cat > "$MSG_FILE" << MSGEOF
pr(${org}/${repo}#${number}): ${title}

state:    ${state}
org:      ${org}
repo:     ${repo}
branch:   ${head} -> ${base}
changes:  +${additions} -${deletions} across ${changed} files
activity: ${commits} commits, ${comments} comments, ${reviews} reviews
date:     ${date_short}
url:      ${url}
MSGEOF

    if [[ -n "$labels" ]]; then
      echo "labels:   ${labels}" >> "$MSG_FILE"
    fi

    git add "$activity_file"
    GIT_AUTHOR_DATE="$effective_date" GIT_COMMITTER_DATE="$effective_date" \
      git commit -q -F "$MSG_FILE"
    rm -f "$MSG_FILE"

    count=$((count + 1))
    if (( count % 50 == 0 )); then
      printf "  [%d/%d] last: %s/%s#%d (%s)\n" "$count" "$total_new" "$org" "$repo" "$number" "$date_short"
    fi

  done < "$tmpfile"

  echo ""
  echo "  ✓ $count commits written."
  return 0
}

# ── Sorted temp file (all PRs with effectiveDate) ─────────────────────────────

ALL_SORTED=$(mktemp)
jq -sc '[.[] | . + {
  effectiveDate: (if .mergedAt then .mergedAt elif .closedAt then .closedAt else .createdAt end)
}] | sort_by(.effectiveDate) | .[]' "$JSONL" > "$ALL_SORTED"

# ═══════════════════════════════════════════════════════════════════════════════
# INIT MODE — first run, build the repo from scratch
# ═══════════════════════════════════════════════════════════════════════════════

if [[ "$MODE" == "init" ]]; then

  mkdir -p "$REPO_DIR"
  cd "$REPO_DIR"
  git init -b main
  mkdir -p activity

  FIRST_DATE=$(jq -r '.effectiveDate' "$ALL_SORTED" | head -1)

  cat > README.md << 'READEOF'
# Work History

Chronological record of pull request activity across GitHub Enterprise (git.taservs.net).

Each commit represents one PR — merged, closed, or open — backdated to match
the real merge/close date. The commit message carries key metadata: repo, state,
lines changed, file count, commits, and review activity.

## Structure

```
activity/
  YYYY.md   — all PRs for that year, appended chronologically
README.md   — this file
```

## Refresh

Run `generate-work-history.sh` from codebase-context/github-activity/ to sync new PRs.
READEOF

  git add README.md
  GIT_AUTHOR_DATE="$FIRST_DATE" GIT_COMMITTER_DATE="$FIRST_DATE" \
    git commit -q -m "init: work history"

  commit_prs "$ALL_SORTED"

  echo ""
  echo "Next steps:"
  echo "  1. Create an empty repo on GitHub (no README, no .gitignore)"
  echo "  2. cd $REPO_DIR"
  echo "     git remote add origin <url>"
  echo "     git push -u origin main"
  echo ""
  echo "  Then future runs of this script will push automatically."

# ═══════════════════════════════════════════════════════════════════════════════
# UPDATE MODE — incremental sync, only commit PRs not already in history
# ═══════════════════════════════════════════════════════════════════════════════

else

  cd "$REPO_DIR"

  # Build set of already-committed PR URLs by reading git log bodies
  echo "→ Scanning existing commit history..."
  COMMITTED_URLS=$(git log --format="%B" | grep "^url:" | awk '{print $2}' | sort)
  COMMITTED_COUNT=$(echo "$COMMITTED_URLS" | grep -c "http" || true)
  echo "  found $COMMITTED_COUNT already-committed PRs"
  echo ""

  # Write committed URLs to temp file for filtering
  COMMITTED_TMP=$(mktemp)
  echo "$COMMITTED_URLS" > "$COMMITTED_TMP"

  # Filter ALL_SORTED to only PRs whose URL is not already committed
  NEW_TMP=$(mktemp)
  while IFS= read -r pr; do
    url=$(echo "$pr" | jq -r '.url')
    if ! grep -qF "$url" "$COMMITTED_TMP"; then
      echo "$pr" >> "$NEW_TMP"
    fi
  done < "$ALL_SORTED"

  rm -f "$COMMITTED_TMP"

  commit_prs "$NEW_TMP"
  rm -f "$NEW_TMP"

  # Push if remote is configured
  if git remote get-url origin &>/dev/null; then
    echo "→ Pushing to origin..."
    git push -q origin main
    echo "  ✓ Pushed."
  else
    echo "  (no remote configured — skipping push)"
    echo "  To push: cd $REPO_DIR && git remote add origin <url> && git push -u origin main"
  fi

fi

rm -f "$ALL_SORTED"

echo ""
echo "Last 5 commits:"
git -C "$REPO_DIR" log --oneline -5
