#!/usr/bin/env bash
# List open dependency-bump PRs referenced by your GitHub notifications.
#
# Usage: collect-bump-prs.sh [--unread-only]
#
# Reads ALL notifications (read + unread) by default, paginated, keeps PullRequest
# subjects whose title contains "bump" (case-insensitive), and prints one JSON object
# per OPEN PR (JSON Lines) with author, changed files, merge state and a CI summary.
# Closed/merged PRs are dropped silently. Read-only: performs no writes.
#
# Env: JOBS = parallel `gh pr view` calls (default 8).
set -euo pipefail

all=true
[[ "${1:-}" == "--unread-only" ]] && all=false

out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT

view_pr() {
  local repo=$1 number=$2 out=$3
  gh pr view "$number" -R "$repo" \
    --json number,state,title,url,author,files,mergeable,mergeStateStatus,statusCheckRollup \
    --jq '
      select(.state == "OPEN") | {
        repo: "'"$repo"'",
        number,
        title,
        url,
        author: .author.login,
        files: [.files[].path],
        mergeable,
        mergeStateStatus,
        checks: ([.statusCheckRollup[]? |
                   if   (.conclusion // "") != "" then .conclusion
                   elif (.state // "")      != "" then .state
                   else (.status // "UNKNOWN") end]
                 | group_by(.) | map({key: .[0], value: length}) | from_entries)
      }' > "$out/${repo//\//__}#$number.json" 2>/dev/null \
    || echo "{\"repo\":\"$repo\",\"number\":$number,\"error\":\"gh pr view failed\"}" \
         > "$out/${repo//\//__}#$number.json"
}
export -f view_pr

gh api --paginate "notifications?all=${all}&per_page=100" \
  --jq '.[] | select(.subject.type == "PullRequest")
             | select(.subject.title | test("bump"; "i"))
             | "\(.repository.full_name) \(.subject.url | split("/") | last)"' \
| sort -u \
| xargs -r -P "${JOBS:-8}" -n 2 bash -c 'view_pr "$1" "$2" "'"$out"'"' _

cat "$out"/*.json 2>/dev/null || true
