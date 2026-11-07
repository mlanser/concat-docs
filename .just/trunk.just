# trunk.just — shared trunk-based git + GitHub workflow for F451 Labs repos.
#
# VENDORED from mlanser/f451labs-templates (just/). Do not edit in a project repo:
# change it upstream, and the copy here is refreshed by a PR from that repo.
#
# Loop:  just start feat/x | just start 42  →  just commit "feat: x"  →  just pr
#        →  (review + merge on GitHub)  →  just done
#
# Rules this file keeps:
# - User text (messages, titles, names) reaches bash only as exported `$param`
#   environment variables — never `{{param}}` interpolation, which bash would parse.
# - Runs on macOS /bin/bash 3.2: no associative arrays, no ${x,,}, no sed -i.
# - Per-repo knobs come from the importing justfile, e.g. `export TRUNK_SCOPES := "api hugo"`.

_cc_types := "feat fix chore docs refactor test ci perf build revert"
_cc_re := '^(feat|fix|chore|docs|refactor|test|ci|perf|build|revert)(\([a-z0-9._/-]+\))?!?: .+'

# Print where you are: repo, branch, distance from origin/main, PR
status: _banner
    #!/usr/bin/env bash
    set -uo pipefail
    git fetch --quiet origin main 2>/dev/null || echo "(offline: comparing with the last-fetched origin/main)"
    counts="$(git rev-list --left-right --count origin/main...HEAD)"
    behind="${counts%%[[:space:]]*}"; ahead="${counts##*[[:space:]]}"
    dirty="$(git status --porcelain | wc -l | tr -d ' ')"
    echo "vs origin/main: $ahead ahead, $behind behind · $dirty uncommitted file(s)"
    br="$(git branch --show-current)"
    if [ -n "$br" ] && [ "$br" != main ]; then
        echo "PR: $(gh pr view "$br" --json state,url -q '.state + " " + .url' 2>/dev/null || echo none)"
    fi

# Start a branch off a fresh origin/main: `just start feat/x`, or `just start 42` for issue #42
start $target: _banner _hooks
    #!/usr/bin/env bash
    set -euo pipefail
    [ -z "$(git status --porcelain)" ] || { echo "error: uncommitted changes — commit or stash them first" >&2; exit 1; }
    types="{{_cc_types}} ${TRUNK_SCOPES:-}"
    case "$target" in
        ''|*[!0-9]*) name="$target" ;;
        *)
            title="$(gh issue view "$target" --json title -q .title)"
            labels=" $(gh issue view "$target" --json labels -q '.labels[].name' | tr '\n' ' ') "
            case "$labels" in
                *" bug "*) type=fix ;;
                *" enhancement "*|*" feature "*) type=feat ;;
                *" documentation "*) type=docs ;;
                *) type=chore ;;
            esac
            slug="$("{{just_executable()}}" --justfile "{{justfile()}}" _slug "$title")"
            name="$type/$target-$slug" ;;
    esac
    prefix="${name%%/*}"; rest="${name#*/}"; known=0
    for t in $types; do [ "$t" = "$prefix" ] && known=1; done
    if [ "$known" = 0 ] || [ "$prefix" = "$name" ] || ! printf '%s' "$rest" | grep -Eq '^[a-z0-9][a-z0-9._-]*$'; then
        echo "error: branch must be <type>/<name> in lowercase, e.g. feat/login-form (types: $types)" >&2
        exit 1
    fi
    if git show-ref --verify --quiet "refs/heads/$name"; then
        echo "error: branch $name already exists — switch to it with: git switch $name" >&2
        exit 1
    fi
    git fetch --quiet origin main
    git switch --quiet --no-track -c "$name" origin/main
    echo "on $name (from origin/main $(git rev-parse --short origin/main))"

# Commit with a Conventional Commit message (pre-commit hooks run). Commits what is staged, or everything if nothing is staged
commit $msg: _banner _not-main _hooks
    #!/usr/bin/env bash
    set -euo pipefail
    re='{{_cc_re}}'
    if ! [[ "$msg" =~ $re ]]; then
        echo "error: not a Conventional Commit message: $msg" >&2
        echo "  expected <type>[(scope)][!]: <description>, type one of: {{_cc_types}}" >&2
        exit 1
    fi
    if git diff --cached --quiet; then
        [ -n "$(git status --porcelain)" ] || { echo "error: nothing to commit" >&2; exit 1; }
        git add -A
    fi
    git status --short
    tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
    git diff --cached --name-only --diff-filter=d | sort > "$tmp/staged"
    git diff --name-only | sort > "$tmp/unstaged-before"
    # Committing only what was staged (e.g. after a `git mv`) must not silently leave
    # the rest of the work behind: name whatever is still uncommitted.
    leftovers() {
        local left; left="$(git status --porcelain)"
        [ -z "$left" ] || { echo "warning: not in this commit (still uncommitted):" >&2; printf '%s\n' "$left" >&2; }
    }
    if git commit --quiet -m "$msg"; then
        git --no-pager log --oneline -1
        leftovers
        exit 0
    fi
    # Fixer hooks (ruff-format, end-of-file-fixer, ...) rewrite staged files and fail
    # the commit. Re-stage exactly those files — staged before, modified now, not
    # already unstaged before — and retry once. A second failure is real; stop.
    git diff --name-only | sort > "$tmp/unstaged-after"
    comm -13 "$tmp/unstaged-before" "$tmp/unstaged-after" | comm -12 - "$tmp/staged" > "$tmp/fixed"
    if [ ! -s "$tmp/fixed" ]; then
        echo "error: commit failed (see hook output above)" >&2
        exit 1
    fi
    echo "hooks rewrote $(wc -l < "$tmp/fixed" | tr -d ' ') file(s) — re-staging and retrying once"
    while IFS= read -r f; do git add -- "$f"; done < "$tmp/fixed"
    git commit --quiet -m "$msg" || { echo "error: commit failed again after re-staging hook fixes" >&2; exit 1; }
    git --no-pager log --oneline -1
    leftovers

# Rebase on origin/main, run `just check`, push, and open (or update) the PR. Never merges
pr: _banner _not-main _clean
    #!/usr/bin/env bash
    set -euo pipefail
    br="$(git branch --show-current)"
    git fetch --quiet origin main
    if ! git rebase --quiet origin/main; then
        echo "error: rebase onto origin/main stopped on a conflict." >&2
        echo "  fix the files, 'git add' them, run 'git rebase --continue', then re-run 'just pr'" >&2
        echo "  (or 'git rebase --abort' to undo)" >&2
        exit 1
    fi
    [ -n "$(git log --oneline origin/main..HEAD)" ] || { echo "error: $br has no commits beyond origin/main" >&2; exit 1; }
    "{{just_executable()}}" check
    git push --quiet --force-with-lease -u origin HEAD
    open_url="$(gh pr view "$br" --json state,url -q 'select(.state == "OPEN") | .url' 2>/dev/null || true)"
    if [ -n "$open_url" ]; then
        echo "updated PR: $open_url"
    else
        title="$(git log --reverse --format=%s origin/main..HEAD | head -1)"
        body="$(git log --reverse --format='- %s' origin/main..HEAD)"
        issue="$(printf '%s' "$br" | sed -nE 's#^[a-z]+/([0-9]+)-.*#\1#p')"
        [ -z "$issue" ] || body="$body"$'\n\n'"Closes #$issue"
        gh pr create --base main --head "$br" --title "$title" --body "$body"
    fi
    echo "Review and merge on GitHub, then run: just done"

# After you merge on GitHub: back to an up-to-date main, merged local branches deleted
done: _banner _clean
    #!/usr/bin/env bash
    set -euo pipefail
    br="$(git branch --show-current)"
    if [ "$br" != main ]; then
        state="$(gh pr view "$br" --json state -q .state 2>/dev/null || echo NONE)"
        case "$state" in
            MERGED) ;;
            NONE) echo "error: no PR for $br — open one with 'just pr'" >&2; exit 1 ;;
            *) echo "error: PR for $br is $state — merge it on GitHub first" >&2; exit 1 ;;
        esac
        head="$(gh pr view "$br" --json headRefOid -q .headRefOid)"
        git switch --quiet main
    fi
    git fetch --quiet origin main
    git merge --quiet --ff-only origin/main
    # Delete the branch just proven merged, even if GitHub kept its remote copy (repos
    # with delete_branch_on_merge off) — but only if it holds nothing the PR lacked.
    if [ "$br" != main ]; then
        if [ "$(git rev-parse "$br")" = "$head" ]; then
            git branch --quiet -D "$br" && echo "reaped $br"
        else
            echo "kept $br: it has commits that are not in the merged PR" >&2
        fi
    fi
    "{{just_executable()}}" tidy
    git --no-pager log --oneline -3

# Delete local branches whose remote is gone AND whose PR merged (anything else is reported, kept)
tidy:
    #!/usr/bin/env bash
    # -D, not -d: squash merges rewrite the commits, so a merged branch never looks
    # merged to git. -D on "upstream gone" alone would also destroy a branch whose
    # remote was deleted WITHOUT a merge, so a branch is reaped only on positive
    # proof it landed: reachable from origin/main, or GitHub reports a merged PR.
    set -euo pipefail
    git fetch --quiet --prune
    reaped=0
    while read -r br; do
        [ -n "$br" ] || continue
        if git merge-base --is-ancestor "$br" origin/main \
            || [ -n "$(gh pr list --head "$br" --state merged --json number --jq '.[].number')" ]; then
            git branch --quiet -D "$br"
            echo "reaped $br"
            reaped=$((reaped + 1))
        else
            echo "skipped $br — upstream gone, and no merge landed it on main"
        fi
    done < <(git for-each-ref --format='%(refname:short) %(upstream:track)' refs/heads \
        | awk '$2 == "[gone]" { print $1 }')
    [ "$reaped" -gt 0 ] || echo "nothing to reap"

# Open a GitHub issue: `just issue "Login redirect loops" "optional body"`
issue $title $body="": _banner
    @gh issue create --title "$title" --body "$body"

# Small change from main in one step: start + commit + pr (no auto-merge). Optional branch name
ship $msg $branch="": _banner _hooks
    #!/usr/bin/env bash
    set -euo pipefail
    [ "$(git branch --show-current)" = main ] || { echo "error: ship starts from main — on a branch, use 'just commit' then 'just pr'" >&2; exit 1; }
    [ -n "$(git status --porcelain)" ] || { echo "error: nothing to ship" >&2; exit 1; }
    re='{{_cc_re}}'
    [[ "$msg" =~ $re ]] || { echo "error: not a Conventional Commit message: $msg" >&2; exit 1; }
    slug="$branch"
    if [ -z "$slug" ]; then
        type="$(printf '%s' "$msg" | sed -nE 's/^([a-z]+).*/\1/p')"
        scope="$(printf '%s' "$msg" | sed -nE 's/^[a-z]+\(([^)]*)\).*/\1/p')"
        prefix=chore
        for t in {{_cc_types}}; do [ "$t" = "$type" ] && prefix="$type"; done
        for s in ${TRUNK_SCOPES:-}; do [ "$s" = "$scope" ] && prefix="$scope"; done
        body="$("{{just_executable()}}" --justfile "{{justfile()}}" _slug "$(printf '%s' "$msg" | sed -E 's/^[a-z]+(\([^)]*\))?!?: //')")"
        slug="$prefix/$body"
    fi
    git fetch --quiet origin main
    git switch --quiet --no-track -c "$slug" origin/main   # carries the uncommitted changes along
    "{{just_executable()}}" commit "$msg"
    "{{just_executable()}}" pr

# Show the command reference and the recipes available here
help:
    @echo "Command reference: https://github.com/mlanser/f451labs-templates/blob/main/docs/HOWTO.md"
    @"{{just_executable()}}" --list

[private]
_banner:
    @printf 'repo: %s · branch: %s\n' "$(git rev-parse --show-toplevel)" "$(git branch --show-current)"

[private]
_not-main:
    @[ "$(git branch --show-current)" != main ] || { echo "error: on main — start a branch with 'just start <type>/<name>'" >&2; exit 1; }

[private]
_clean:
    @[ -z "$(git status --porcelain)" ] || { echo "error: uncommitted changes — 'just commit' them first" >&2; exit 1; }

# Self-heal: a repo with a prek config but no installed hook silently skips every hook.
[private]
_hooks:
    #!/usr/bin/env bash
    set -euo pipefail
    [ -f .pre-commit-config.yaml ] || exit 0
    # Install a git hook for every stage the config uses, not only pre-commit: a hook
    # declared `stages: [pre-push]` never runs when only pre-commit is installed.
    wanted="pre-commit"
    grep -q 'pre-push' .pre-commit-config.yaml && wanted="$wanted pre-push"
    missing=()
    for t in $wanted; do
        [ -f "$(git rev-parse --git-path "hooks/$t")" ] || missing+=(--hook-type "$t")
    done
    [ "${#missing[@]}" -gt 0 ] || exit 0
    if command -v prek >/dev/null 2>&1; then
        echo "git hooks were not installed — installing with prek"
        prek install "${missing[@]}"
    else
        echo "warning: hooks are NOT installed and prek is missing — run: uv tool install prek" >&2
    fi

# Kebab-case slug of $text, at most 40 characters, cut at a word boundary: a word the
# limit would split is dropped, unless the slug is one long word.
[private]
_slug $text:
    #!/usr/bin/env bash
    set -euo pipefail
    slug="$(printf '%s' "$text" | tr 'A-Z' 'a-z' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
    if [ "${#slug}" -gt 40 ]; then
        cut="$(printf '%s' "$slug" | cut -c1-41)"
        case "$cut" in
            *-) slug="${cut%-}" ;;
            *-*) slug="${cut%-*}" ;;
            *) slug="$(printf '%s' "$slug" | cut -c1-40)" ;;
        esac
    fi
    printf '%s\n' "$slug"
