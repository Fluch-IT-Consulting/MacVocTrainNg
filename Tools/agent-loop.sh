#!/bin/zsh
# Works through the open issues labelled ready-for-agent, one after another. Each
# issue gets its own worktree and branch from origin/main, and a headless Claude Code
# session implements it and opens a pull request. Merging stays manual. An agent that
# gets stuck comments on the issue and swaps ready-for-agent for needs-info or
# ready-for-human instead. See docs/agents/afk-loop.md.
#
#   Tools/agent-loop.sh              every eligible issue, oldest first
#   Tools/agent-loop.sh 197 189      only these, if eligible
#   Tools/agent-loop.sh --dry-run    list what would run, change nothing
#
# Eligible: open, labelled ready-for-agent, not blocked, assigned to nobody, and no
# branch for it yet. The prompt is docs/agents/afk-prompt.md from this checkout; the
# agent's output goes to .claude/agent-runs/<issue>.log.

set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

DRY_RUN=false
typeset -a requested
for arg in "$@"; do
    case $arg in
        --dry-run) DRY_RUN=true ;;
        <->) requested+=("$arg") ;;
        *) echo "usage: $0 [--dry-run] [<issue> …]" >&2; exit 2 ;;
    esac
done

PROMPT_FILE=docs/agents/afk-prompt.md
LOG_DIR=.claude/agent-runs
WORKTREE_DIR=.claude/worktrees

# The agent may only read, edit and run these commands; everything else is denied
# without asking, except what Claude Code itself deems read-only (ls, for example).
# The deny rules take precedence over the allowed prefixes.
ALLOWED_TOOLS=(
    Read Glob Grep Edit Write TodoWrite
    "Bash(git *)" "Bash(gh *)" "Bash(xcodebuild *)" "Bash(swift *)" "Bash(xcrun *)"
)
DISALLOWED_TOOLS=(
    "Bash(gh pr merge *)" "Bash(gh issue create *)" "Bash(gh issue close *)"
    "Bash(gh issue delete *)" "Bash(gh api *)" "Bash(gh repo *)"
    "Bash(git push --force *)" "Bash(git push -f *)" "Bash(git push origin main *)"
)

# Issue number, issue type and title of each eligible issue, oldest first.
eligible() {
    gh issue list --state open --label ready-for-agent --limit 200 \
        --json number,title,issueType,assignees,labels,blockedBy,createdAt \
        --jq '
            map(select(
                (.assignees | length) == 0
                and (.labels | map(.name) | index("blocked") | not)
                and (.blockedBy.nodes | all(.state == "CLOSED"))
            ))
            | sort_by(.createdAt) | .[]
            | [.number, (.issueType.name // "-"), .title] | @tsv'
}

branch_for() {
    case $1 in
        Bug) echo "bugfix/$2" ;;
        Feature) echo "feature/$2" ;;
        Task) echo "task/$2" ;;
        *) return 1 ;;
    esac
}

has_branch() {
    git show-ref --quiet "refs/heads/$1" || git ls-remote --exit-code --heads origin "$1" >/dev/null
}

typeset -a queue queued summary
candidates=$(eligible)
for entry in ${(f)candidates}; do
    number=${entry%%$'\t'*}
    if (( ${#requested} == 0 )) || (( ${requested[(Ie)$number]} )); then
        queue+=("$entry")
        queued+=("$number")
    fi
done

for number in $requested; do
    if ! (( ${queued[(Ie)$number]} )); then
        summary+=("#$number  not eligible (closed, not ready-for-agent, assigned or blocked)")
    fi
done

git fetch --quiet origin main
$DRY_RUN || mkdir -p "$LOG_DIR"

for entry in $queue; do
    IFS=$'\t' read -r number type title <<< "$entry"
    if ! branch=$(branch_for "$type" "$number"); then
        summary+=("#$number  skipped: issue has no type")
        continue
    fi
    if has_branch "$branch"; then
        summary+=("#$number  skipped: branch $branch already exists")
        continue
    fi
    if $DRY_RUN; then
        summary+=("#$number  would run on $branch: $title")
        continue
    fi

    # The list above may be minutes old by now.
    if [[ -n $(gh issue view "$number" --json assignees --jq '.assignees[].login') ]]; then
        summary+=("#$number  skipped: assigned in the meantime")
        continue
    fi

    echo "▸ #$number $title"
    gh issue edit "$number" --add-assignee @me >/dev/null
    worktree=$WORKTREE_DIR/${branch//\//-}
    git worktree add --quiet --no-track -b "$branch" "$worktree" origin/main
    if [[ -f Config/Signing.local.xcconfig ]]; then
        cp Config/Signing.local.xcconfig "$worktree/Config/"
    fi

    log=$ROOT/$LOG_DIR/$number.log
    agent_status=0
    sed -e "s/{{ISSUE}}/$number/g" -e "s|{{BRANCH}}|$branch|g" "$PROMPT_FILE" \
        | (cd "$worktree" && claude -p --permission-mode dontAsk \
            --allowedTools "${ALLOWED_TOOLS[@]}" \
            --disallowedTools "${DISALLOWED_TOOLS[@]}" \
            --output-format stream-json --verbose) \
        > "$log" 2>&1 || agent_status=$?

    pr=$(gh pr list --head "$branch" --state open --json url --jq '.[0].url // empty')
    labels=$(gh issue view "$number" --json labels --jq '[.labels[].name] | join(", ")')
    if [[ -n $pr ]]; then
        if git worktree remove "$worktree" && git branch --quiet -D "$branch"; then
            summary+=("#$number  ✓ $pr")
        else
            summary+=("#$number  ✓ $pr (worktree kept: $worktree)")
        fi
    elif [[ ", $labels, " != *", ready-for-agent, "* ]]; then
        # Handed back: unassign, so the issue becomes eligible again once relabelled.
        gh issue edit "$number" --remove-assignee @me >/dev/null
        summary+=("#$number  ? handed back ($labels), worktree $worktree")
    else
        summary+=("#$number  ✗ no pull request, see $log, worktree $worktree")
    fi

    if (( agent_status != 0 )); then
        summary+=("stopped: claude exited with status $agent_status, see $log")
        break
    fi
done

echo
if (( ${#summary} == 0 )); then
    echo "No eligible issues."
else
    printf '%s\n' $summary
fi
