#!/usr/bin/env bash
# my-contributions.sh — generate a report of repos you've personally committed to
#
# Usage:
#   ./my-contributions.sh [output-file]
#
# Defaults to writing: contributions.md

set -eu

CONTEXT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPOS_DIR="$(cd "$CONTEXT_DIR/.." && pwd)"
OUTPUT="${1:-$CONTEXT_DIR/contributions.md}"
AUTHOR="Aaron Roethe"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

TOUCHED_FILE=$(mktemp)
trap 'rm -f "$TOUCHED_FILE"' EXIT

echo "Scanning repos for commits by: $AUTHOR ..."
echo ""

# Extension -> language, for classifying which language you wrote the most
# lines in per repo. Docs/lockfiles are excluded from language detection
# (but still counted in the lines-changed total).
ext_to_lang() {
  case "$1" in
    go) echo "Go" ;;
    ts|tsx) echo "TypeScript" ;;
    js|jsx|mjs|cjs) echo "JavaScript" ;;
    py) echo "Python" ;;
    java) echo "Java" ;;
    rb) echo "Ruby" ;;
    sh|bash) echo "Shell" ;;
    yaml|yml) echo "YAML" ;;
    tf|tfvars|hcl) echo "Terraform" ;;
    sql) echo "SQL" ;;
    proto) echo "Protobuf" ;;
    feature) echo "Gherkin" ;;
    json) echo "JSON" ;;
    html) echo "HTML" ;;
    xml) echo "XML" ;;
    css|scss) echo "CSS" ;;
    cs) echo "C#" ;;
    rs) echo "Rust" ;;
    kt) echo "Kotlin" ;;
    gradle) echo "Gradle" ;;
    groovy) echo "Groovy" ;;
    c|h) echo "C" ;;
    cpp|cc|hpp) echo "C++" ;;
    *) echo "" ;;
  esac
}

for repo in "$REPOS_DIR"/*/; do
  [[ -d "$repo/.git" ]] || continue

  name=$(basename "$repo")
  [[ "$name" == "work-history" ]] && continue

  remote_url=$(git -C "$repo" remote get-url origin 2>/dev/null || echo "")
  # git@host:org/repo.git or https://host/org/repo(.git)
  org=$(echo "$remote_url" | sed -E 's#^git@[^:]+:##; s#^https?://[^/]+/##; s#\.git$##' | awk -F/ '{print $1}')
  [[ -z "$org" ]] && org="unknown"

  commit_count=$(git -C "$repo" log --all --author="$AUTHOR" --oneline 2>/dev/null | wc -l | tr -d ' ')

  if [[ "$commit_count" -gt 0 ]]; then
    last_date=$(git -C "$repo" log --all --author="$AUTHOR" --format="%as" 2>/dev/null | head -1)
    first_date=$(git -C "$repo" log --all --author="$AUTHOR" --format="%as" 2>/dev/null | tail -1)
    last_msg=$(git -C "$repo" log --all --author="$AUTHOR" --format="%s" 2>/dev/null | head -1)

    # Lines changed + dominant extension, from your own commits only.
    # Binary files report "-" for add/del in --numstat and are skipped.
    numstat_summary=$(git -C "$repo" log --all --author="$AUTHOR" --numstat --format='' 2>/dev/null | awk '
      $1 != "-" && $2 != "-" {
        total += $1 + $2
        file = $3
        n = split(file, parts, ".")
        if (n > 1) {
          ext = tolower(parts[n])
          if (ext != "md" && ext != "txt" && ext != "lock" && ext != "sum" && ext != "log" && ext != "snapshot") {
            ext_lines[ext] += $1 + $2
          }
        }
      }
      END {
        best = ""; best_lines = 0
        for (e in ext_lines) {
          if (ext_lines[e] > best_lines) { best_lines = ext_lines[e]; best = e }
        }
        printf "%d|%s", total, best
      }
    ')
    lines_changed="${numstat_summary%%|*}"
    top_ext="${numstat_summary#*|}"
    language=$(ext_to_lang "$top_ext")
    [[ -z "$language" ]] && language="—"

    echo "${last_date}|${org}|${name}|${commit_count}|${first_date}|${lines_changed}|${language}|${last_msg}" >> "$TOUCHED_FILE"
    echo "  ✓ $org/$name ($commit_count commits, $lines_changed lines, $language)"
  fi
done

touched_count=$(wc -l < "$TOUCHED_FILE" | tr -d ' ')

echo ""
echo "Writing report to: $OUTPUT"

{
  echo "# My Contributions"
  echo ""
  echo "_Author: $AUTHOR — generated ${TIMESTAMP}_"
  echo ""
  echo "---"
  echo ""

  # ── Repos I've touched ──────────────────────────────────────────────────────
  echo "## Repos I've committed to ($touched_count)"
  echo ""

  if [[ "$touched_count" -eq 0 ]]; then
    echo "_No commits found._"
  else
    echo "| Repo | Org | Commits | Lines changed | Primary language | First commit | Last commit | Last message |"
    echo "|------|-----|---------|----------------|-------------------|--------------|-------------|--------------|"

    # Order orgs by total commits across all their repos (largest bucket
    # first), then repos within an org by commit count descending.
    awk -F'|' '
      FNR==NR { total[$2] += $4; next }
      { printf "%012d|%s\n", total[$2], $0 }
    ' "$TOUCHED_FILE" "$TOUCHED_FILE" \
      | sort -t'|' -k1,1nr -k5,5nr \
      | cut -d'|' -f2- \
      | while IFS='|' read -r last_date org name count first_date lines_changed language last_msg; do
      summary_link="$org/${name}.md"
      if [[ -f "$CONTEXT_DIR/$summary_link" ]]; then
        echo "| [$name]($summary_link) | $org | $count | $lines_changed | $language | $first_date | $last_date | $last_msg |"
      else
        echo "| $name | $org | $count | $lines_changed | $language | $first_date | $last_date | $last_msg |"
      fi
    done
  fi

} > "$OUTPUT"

echo "Done. $touched_count repos touched."
echo "  Report: $OUTPUT"
