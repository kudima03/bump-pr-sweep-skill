---
name: bump-pr-sweep
description: Use this skill when the user wants to sweep their GitHub notifications for dependency bump PRs (Dependabot/Renovate) and approve + merge the safe ones. Triggers on phrases like "scan my gh notifications", "merge bump PRs", "sweep dependabot PRs", "approve green bumps", "merge PRs that bump tests/infra/submodules", or any request to batch-review dependency update PRs across repos. Only infra (workflows), test-project and submodule-pointer bumps with green CI are merged; everything else is reported.
---

# Bump PR Sweep

Find open dependency-bump PRs referenced by the user's GitHub notifications (read **and**
unread), approve and merge the ones that are low-risk and green, and report the rest.

## Overview of the workflow

1. Collect open bump PRs from notifications
2. Classify each PR by what it touches (in scope / out of scope)
3. For in-scope PRs: verify CI, merge state and the actual diff
4. Approve and merge with a **merge commit** (`--merge`, never squash/rebase)
5. Report merged and skipped PRs

The user's request (or the repo's `CLAUDE.md`) may widen or narrow the scope below — their
words win. If they say "include X too", treat X as in scope for this run.

---

## Step 1 — Collect

Run the bundled collector (read-only, ~30 s for ~170 notifications):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/bump-pr-sweep/scripts/collect-bump-prs.sh" > "$SCRATCH/bump-prs.jsonl"
```

- `$SCRATCH` = your scratchpad / temp dir. Pass `--unread-only` only if the user asks for unread only;
  the default (all notifications) is what users usually want — read notifications still point at
  open PRs.
- Output: one JSON object per **open** PR: `repo, number, title, url, author, files, mergeable,
  mergeStateStatus, checks` (`checks` is a `{CONCLUSION: count}` map). Entries with `"error"` could
  not be fetched — retry them individually and mention them in the report if they still fail.
- If `CLAUDE_PLUGIN_ROOT` is unset, locate the script next to this `SKILL.md`.

Most bump notifications point at PRs that are already merged or closed; an empty result is normal.

## Step 2 — Classify

A PR is **in scope** only when the author is a bump bot (`app/dependabot`, `app/renovate`, or
similar) **and every changed file** falls into one of these buckets:

| Bucket | Files | Typical diff |
|---|---|---|
| Infra | `.github/workflows/*.yml`, `.github/actions/**` | `uses: owner/action@old` → `@new` |
| Tests | project files under a test-only path (`src/Tests/**`, `tests/**`, `test/**`, `*.Tests/*.csproj`, `*.Tests.csproj`) | `Version="old"` → `"new"` |
| Submodules | a path with no extension that is a git submodule (diff shows `Subproject commit`) | `Subproject commit <sha>` → `<sha>` |

**Out of scope** — never merge, just report:
- Product/app dependencies: `package.json` / `package-lock.json` / `yarn.lock` in app code,
  non-test `.csproj`, `Directory.Packages.props`, `requirements*.txt`, `go.mod`, `Cargo.toml`, etc.
- Mixed PRs where *any* file is outside the buckets above.
- PRs not authored by a bump bot.

## Step 3 — Verify each in-scope PR

```bash
gh pr checks <n> -R <repo>
gh pr view   <n> -R <repo> --json mergeable,mergeStateStatus --jq '[.mergeable,.mergeStateStatus]|@tsv'
gh pr diff   <n> -R <repo> | grep '^[+-][^+-]'
```

Eligible only if **all** hold:
- **CI green**: every check is `pass`; `pass` + `skipping` is also green. `fail`, `pending`,
  `cancelled`, or **"no checks reported"** is **not** green.
- `mergeable == MERGEABLE` and `mergeStateStatus == CLEAN`.
- **Diff is only the version bump**: the changed lines are exactly the action ref / package
  version / `Subproject commit` line(s). Any other change → skip and report it.

## Step 4 — Approve and merge

For each eligible PR:

```bash
gh pr review <n> -R <repo> --approve
gh pr merge  <n> -R <repo> --merge
gh pr view   <n> -R <repo> --json state --jq .state   # expect MERGED
```

- Use `--merge` (classic merge commit). Do not use `--squash`, `--rebase`, `--auto` or `--admin`.
- Merge sequentially. When several PRs hit the same repo (e.g. two submodule bumps), a later
  one may turn `BEHIND`/`DIRTY` after the first merges. Don't force it: comment
  `@dependabot rebase` on it (this ping is intentional) and list it as "rebasing — merge next sweep".
- If approving fails because the user authored the PR or lacks permission, skip the review and
  report it; don't merge without the review the user asked for.

## Step 5 — Report

Keep it short:

1. **Merged** — table: `repo#number` | what changed (`old → new`).
2. **Skipped** — one line each with the reason: out of scope (say which file), CI failing/pending
   (name the failing check), not mergeable, unexpected extra diff, rebasing.
3. Call out notable risk seen in skipped PRs, e.g. lockfiles pulling transitive **major** bumps or
   **license changes**.

Do not open failing CI logs or try to fix anything unless the user asks.
