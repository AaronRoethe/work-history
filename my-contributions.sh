#!/usr/bin/env bash
# my-contributions.sh — generate a report of repos you've personally committed to
#
# Usage:
#   ./my-contributions.sh [output-file]
#
# Defaults to writing: contributions.md

set -eu

CONTEXT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT="${1:-$CONTEXT_DIR/contributions.md}"
AUTHOR="Aaron Roethe"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

TOUCHED_FILE=$(mktemp)
UNTOUCHED_FILE=$(mktemp)
trap 'rm -f "$TOUCHED_FILE" "$UNTOUCHED_FILE"' EXIT

echo "Scanning repos for commits by: $AUTHOR ..."
echo ""

for repo in "$CONTEXT_DIR"/*/repos/*/; do
  [[ -d "$repo/.git" ]] || continue

  org=$(echo "$repo" | sed "s|$CONTEXT_DIR/||" | cut -d/ -f1)
  name=$(basename "$repo")

  commit_count=$(git -C "$repo" log --all --author="$AUTHOR" --oneline 2>/dev/null | wc -l | tr -d ' ')

  if [[ "$commit_count" -gt 0 ]]; then
    last_date=$(git -C "$repo" log --all --author="$AUTHOR" --format="%as" 2>/dev/null | head -1)
    first_date=$(git -C "$repo" log --all --author="$AUTHOR" --format="%as" 2>/dev/null | tail -1)
    last_msg=$(git -C "$repo" log --all --author="$AUTHOR" --format="%s" 2>/dev/null | head -1)
    echo "${last_date}|${org}|${name}|${commit_count}|${first_date}|${last_msg}" >> "$TOUCHED_FILE"
    echo "  ✓ $org/$name ($commit_count commits)"
  else
    echo "${org}|${name}" >> "$UNTOUCHED_FILE"
  fi
done

touched_count=$(wc -l < "$TOUCHED_FILE" | tr -d ' ')
untouched_count=$(wc -l < "$UNTOUCHED_FILE" | tr -d ' ')

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
    echo "| Repo | Org | Commits | First commit | Last commit | Last message |"
    echo "|------|-----|---------|--------------|-------------|--------------|"

    sort -r "$TOUCHED_FILE" | while IFS='|' read -r last_date org name count first_date last_msg; do
      summary_link="$org/${name}.md"
      if [[ -f "$CONTEXT_DIR/$summary_link" ]]; then
        echo "| [$name]($summary_link) | $org | $count | $first_date | $last_date | $last_msg |"
      else
        echo "| $name | $org | $count | $first_date | $last_date | $last_msg |"
      fi
    done
  fi

  echo ""
  echo "---"
  echo ""

  # ── Repos I've never touched ─────────────────────────────────────────────────
  echo "## Repos I've never committed to ($untouched_count)"
  echo ""

  if [[ "$untouched_count" -eq 0 ]]; then
    echo "_All repos have your commits._"
  else
    prev_org=""
    sort "$UNTOUCHED_FILE" | while IFS='|' read -r org name; do
      if [[ "$org" != "$prev_org" ]]; then
        [[ -n "$prev_org" ]] && echo ""
        echo "### $org"
        echo ""
        prev_org="$org"
      fi
      summary_link="$org/${name}.md"
      if [[ -f "$CONTEXT_DIR/$summary_link" ]]; then
        echo "- [$name]($summary_link)"
      else
        echo "- $name"
      fi
    done
  fi

} > "$OUTPUT"

echo "Done. $touched_count repos touched, $untouched_count never touched."
echo "  Report: $OUTPUT"
