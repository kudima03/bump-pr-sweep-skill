# bump-pr-sweep-skill

A Claude Code plugin that sweeps your GitHub notifications for dependency bump PRs
(Dependabot / Renovate) and merges the low-risk ones.

Rule of thumb: **approve and merge-commit** a bump PR only if it touches nothing but
GitHub Actions workflows, test projects or git submodule pointers, its diff is just the
version line, and CI is green. Everything else is reported, not touched.

## Contents

| Type | Name | Description |
|---|---|---|
| Skill | `bump-pr-sweep` | Auto-triggered sweep: collect open bump PRs from notifications, classify, verify CI + diff, approve, `gh pr merge --merge`, report |
| Command | `/bump-pr-sweep` | Explicitly kick off the sweep (extra instructions can be passed as arguments) |
| Script | `skills/bump-pr-sweep/scripts/collect-bump-prs.sh` | Read-only collector: open bump PRs from all notifications as JSON Lines |

## Install

```
/plugin install bump-pr-sweep-skill --marketplace kudima03/claude-plugins
```

or, with the marketplace already registered:

```
/plugin marketplace add https://github.com/kudima03/claude-plugins
/plugin install bump-pr-sweep-skill@kudima03
```

## Usage

```
/bump-pr-sweep
/bump-pr-sweep also merge Directory.Packages.props bumps for test-only packages
```

Or just ask: *"scan my gh notifications including read, merge green bump PRs for tests, infra or submodules"*.

## Per-repo overrides

Use `CLAUDE.md` to widen or narrow the scope — it is always in context and takes priority
over skill guidance:

```markdown
<!-- CLAUDE.md -->
## Bump PR sweep
Also treat `build/**` as infra.
```

## Prerequisites

- [Claude Code](https://claude.ai/code)
- `gh` (GitHub CLI) authenticated with `notifications` and `repo` scopes
- `bash`, `xargs`

## License

MIT
