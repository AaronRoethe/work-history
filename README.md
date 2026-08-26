# Work History

A personal archive of your engineering output, built from two independent
tools:

1. **PR history** — every pull request you've authored on GitHub Enterprise
   (`git.taservs.net`) and github.com, turned into a chronological, backdated
   git log you can browse with plain `git log`/`grep`.
2. **Local contributions scan** — a snapshot of which repos on your machine
   you've actually committed to, and which you haven't.

Neither tool touches application code. This repo _is_ the output.

---

## 1. PR history (`activity/`)

### Purpose

One commit per PR you've authored, across every org/repo on both hosts,
committed with its **real merge/close date** so `git log` reads like an
actual timeline of your work. The commit message carries the PR's metadata
(repo, state, lines changed, files, commits, comments, reviews).

### How to use it

```bash
cd github-activity/
./generate-work-history.sh              # fetch latest PRs + commit new ones + push
./generate-work-history.sh --no-fetch    # skip the API call, replay existing prs-raw.jsonl
```

Requires `git`, `jq`, and `gh` (GitHub CLI) authenticated to both
`git.taservs.net` and `github.com`. Check with:

```bash
gh auth status
```

The script fetches PRs authored by whichever account is **currently active**
on each host. If you have multiple `github.com` accounts (e.g. a personal
one) and want to exclude it, just don't switch to it before running —
there's no filtering step, only the active account's PRs are pulled.

Run it any time to catch up — it's idempotent: existing PRs (matched by URL)
are skipped, only new ones are appended and committed.

### Outputs / artifacts

| Path                            | What it is                                                                                                                     |
| ------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| `activity/YYYY.md`              | Human-readable log of every PR that year — one entry per PR with a stats table. This is what you read.                         |
| `github-activity/prs-raw.jsonl` | Raw newline-delimited JSON, one PR per line, all fields. Source of truth for everything else.                                  |
| `github-activity/prs.csv`       | Flattened CSV of the same data — for Excel/Sheets/pandas. See `github-activity/README.md` for the derive command.              |
| git commit history (this repo)  | The actual point of the tool — `git log`, `git log --grep`, `git log --since=...` all work as a queryable history of your PRs. |

---

## 2. Local contributions scan (`contributions.md`)

### Purpose

Scans every git checkout under `~/repos/*` for commits authored by you, and
reports which repos you've touched (with commit counts and date ranges) vs.
which you never have. Unrelated to the PR-history tool above — this reads
your local disk, not GitHub's API.

### How to use it

```bash
./my-contributions.sh                    # writes contributions.md
./my-contributions.sh other-output.md    # or write somewhere else
```

No auth or network required — just needs `~/repos/<name>/.git` checkouts to
exist locally, with an `origin` remote set (used to determine the org).

### Outputs / artifacts

| Path               | What it is                                                                                                                                            |
| ------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| `contributions.md` | Two tables: repos you've committed to (with org, commit count, first/last commit date, last commit message) and repos you never have, grouped by org. |

---

## Repo layout

```
README.md                     — this file
activity/
  YYYY.md                     — PR log for that year (generated)
github-activity/
  README.md                   — details on the PR-history data shape + manual refresh commands
  generate-work-history.sh     — the PR-history generator
  prs-raw.jsonl                — raw PR data (generated)
  prs.csv                      — flattened PR data (generated)
my-contributions.sh            — the local contributions scanner
contributions.md               — its output (generated)
```
