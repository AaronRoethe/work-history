# github-activity

Raw export of all pull request activity from `git.taservs.net` (Axon GitHub Enterprise).

---

## Purpose

This folder is a research base layer — a flat, queryable record of every PR the authenticated user has authored across all orgs and repos on the enterprise GitHub instance. It is not curated or filtered. The intent is to have a single source of truth you can slice any direction: by repo, org, time period, volume of change, review activity, etc.

Use it for:
- Understanding which repos and orgs you've contributed to over time
- Tracking your output (PRs merged, lines changed, review cycles)
- Feeding into AI context or personal productivity analysis
- Auditing work history across teams and projects

---

## Files

| File | Description |
|---|---|
| `prs-raw.jsonl` | Newline-delimited JSON — one PR per line, all available fields. This is the source of truth. |
| `prs.csv` | Flattened CSV derived from the raw file. Suitable for Excel, Google Sheets, or pandas. |

---

## Data Shape (per record in `prs-raw.jsonl`)

```json
{
  "number": 44,
  "title": "perf: paginate SoftDeleteSubmission to fix OOMKill",
  "state": "MERGED",
  "url": "https://git.taservs.net/org/repo/pull/44",
  "createdAt": "2026-02-24T18:09:43Z",
  "mergedAt": "2026-02-24T19:29:46Z",
  "closedAt": "2026-02-24T19:29:46Z",
  "additions": 150,
  "deletions": 30,
  "changedFiles": 5,
  "baseRefName": "main",
  "headRefName": "perf/paginate-soft-delete",
  "commits": { "totalCount": 3 },
  "comments": { "totalCount": 6 },
  "reviews": { "totalCount": 2 },
  "labels": [{ "name": "violate-security-policy" }],
  "repository": {
    "nameWithOwner": "rcom/ibrsubmissionsvc",
    "name": "ibrsubmissionsvc",
    "owner": { "login": "rcom" }
  },
  "body": "..."
}
```

## CSV Columns

```
number, state, createdAt, mergedAt, closedAt, org, repo,
title, additions, deletions, changedFiles, commits, comments,
reviews, baseRef, headRef, url
```

---

## How to Refresh

Re-run the following to regenerate both files (requires `gh` CLI authenticated to `git.taservs.net`):

```bash
# 1. Pull raw JSONL
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
  }' \
  > prs-raw.jsonl

# 2. Derive CSV from raw
jq -r '
  [
    .number, .state, .createdAt,
    (.mergedAt // ""),
    (.closedAt // ""),
    .repository.owner.login,
    .repository.name,
    .title,
    (.additions // 0), (.deletions // 0), (.changedFiles // 0),
    .commits.totalCount, .comments.totalCount,
    .reviews.totalCount,
    .baseRefName, .headRefName,
    .url
  ] | @csv
' prs-raw.jsonl \
  | awk 'BEGIN{print "number,state,createdAt,mergedAt,closedAt,org,repo,title,additions,deletions,changedFiles,commits,comments,reviews,baseRef,headRef,url"} {print}' \
  > prs.csv
```

---

## Useful `jq` Queries Against the Raw File

```bash
# Total PR count
jq -s 'length' prs-raw.jsonl

# Merged only
jq 'select(.state == "MERGED")' prs-raw.jsonl

# PRs per org (ranked)
jq -r '.repository.owner.login' prs-raw.jsonl | sort | uniq -c | sort -rn

# PRs per repo (ranked)
jq -r '.repository.nameWithOwner' prs-raw.jsonl | sort | uniq -c | sort -rn

# PRs by month
jq -r '.createdAt[:7]' prs-raw.jsonl | sort | uniq -c

# Total lines added + deleted (merged PRs only)
jq -s '[.[] | select(.state == "MERGED")] | {additions: map(.additions) | add, deletions: map(.deletions) | add}' prs-raw.jsonl

# PRs with more than 500 lines changed
jq 'select((.additions + .deletions) > 500) | {number, title, additions, deletions, repo: .repository.nameWithOwner}' prs-raw.jsonl
```

---

## Source

- **Instance:** `git.taservs.net` (Axon GitHub Enterprise)
- **Scope:** PRs authored by `@me` across all accessible orgs and repos
- **API:** GitHub GraphQL v4 via `gh api graphql`
- **Last refreshed:** See file modification date on `prs-raw.jsonl`
