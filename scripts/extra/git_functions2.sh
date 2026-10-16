#!/usr/bin/env bash

############################################
# GIT FACTS
# Purpose:
#   Read and report Git repository state.
############################################


############################################
# REPOSITORY IDENTITY
############################################

get_git_branch() {
    local branch

    if ! branch="$(git branch --show-current 2>/dev/null)"; then
        echo "unavailable"
        return 0
    fi

    if [[ -z "$branch" ]]; then
        echo "none"
    else
        echo "$branch"
    fi
}


get_git_head() {
    local head

    if head="$(git rev-parse --verify HEAD 2>/dev/null)"; then
        echo "$head"
    else
        echo "unavailable"
    fi
}


get_git_head_state() {
    if git symbolic-ref --quiet HEAD >/dev/null 2>&1; then
        echo "attached"
    else
        # Distinguish detached HEAD from an invalid repository.
        if git rev-parse --verify HEAD >/dev/null 2>&1; then
            echo "detached"
        else
            echo "unavailable"
        fi
    fi
}


############################################
# UPSTREAM / REMOTE TRACKING
############################################

get_git_upstream() {
    local upstream
    local branch
    local remote
    local merge_ref

    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        echo "unavailable"
        return 0
    fi

    if upstream="$(
        git rev-parse \
            --abbrev-ref \
            --symbolic-full-name '@{upstream}' 2>/dev/null
    )"; then
        echo "$upstream"
        return 0
    fi

    branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null)" || {
        echo "none"
        return 0
    }

    remote="$(git config --get "branch.${branch}.remote" 2>/dev/null)" || {
        echo "none"
        return 0
    }

    merge_ref="$(git config --get "branch.${branch}.merge" 2>/dev/null)" || {
        echo "none"
        return 0
    }

    if [[ -n "$remote" && -n "$merge_ref" ]]; then
        echo "unavailable"
    else
        echo "none"
    fi
}

get_git_remote_head() {
    local head

    # Reports the commit of the configured upstream tracking ref.
    if head="$(
        git rev-parse --verify '@{upstream}^{commit}' 2>/dev/null
    )"; then
        echo "$head"
    else
        echo "unavailable"
    fi
}


############################################
# WORKING TREE STATE
############################################

get_git_worktree_state() {
    local status

    if ! status="$(git status --porcelain 2>/dev/null)"; then
        echo "unavailable"
        return 0
    fi

    if [[ -z "$status" ]]; then
        echo "clean"
    else
        echo "dirty"
    fi
}


############################################
# TRACKED CONTENT DIFFERENCES
############################################
# git diff --quiet exit codes:
#   0 = no differences
#   1 = differences exist
#   Other = command failure

_git_diff_check_state() {
    local result

    if git "$@" --quiet; then
        echo "none"
        return 0
    else
        result=$?
    fi

    if [[ "$result" -eq 1 ]]; then
        echo "present"
    else
        echo "unavailable"
    fi
}


get_git_staged_state() {
    _git_diff_check_state diff --cached
}


get_git_unstaged_state() {
    _git_diff_check_state diff
}


get_git_diff_state() {
    local staged
    local unstaged

    staged="$(get_git_staged_state)"
    unstaged="$(get_git_unstaged_state)"

    if [[ "$staged" == "unavailable" ||
          "$unstaged" == "unavailable" ]]; then
        echo "unavailable"

    elif [[ "$staged" == "present" &&
            "$unstaged" == "present" ]]; then
        echo "staged-and-unstaged"

    elif [[ "$staged" == "present" ]]; then
        echo "staged"

    elif [[ "$unstaged" == "present" ]]; then
        echo "unstaged"

    else
        echo "unchanged"
    fi
}


############################################
# UNTRACKED FILES
############################################

get_git_untracked_state() {
    local files

    if ! files="$(
        git ls-files --others --exclude-standard 2>/dev/null
    )"; then
        echo "unavailable"
        return 0
    fi

    if [[ -n "$files" ]]; then
        echo "present"
    else
        echo "none"
    fi
}


############################################
# LOCAL / UPSTREAM HISTORY
############################################

get_git_ahead_count() {
    local count

    # Number of commits reachable from HEAD but not upstream.

    if count="$(
        git rev-list --count '@{upstream}..HEAD' 2>/dev/null
    )"; then
        echo "$count"
    else
        echo "unavailable"
    fi
}


get_git_behind_count() {
    local count

    # Number of commits reachable from upstream but not HEAD.

    if count="$(
        git rev-list --count 'HEAD..@{upstream}' 2>/dev/null
    )"; then
        echo "$count"
    else
        echo "unavailable"
    fi
}


############################################
# ACTIVE GIT OPERATION
############################################

get_git_operation() {
    local path

    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        echo "unavailable"
        return 0
    fi

    # Rebase using the merge backend.
    path="$(git rev-parse --git-path rebase-merge 2>/dev/null)"
    if [[ -d "$path" ]]; then
        echo "rebase"
        return 0
    fi

    # rebase-apply is used by both rebase and git am.
    path="$(git rev-parse --git-path rebase-apply 2>/dev/null)"
    if [[ -d "$path" ]]; then
        if [[ -f "$path/rebasing" || -f "$path/applying" ]]; then
            if [[ -f "$path/applying" ]]; then
                echo "am"
            else
                echo "rebase"
            fi
        else
            echo "unknown"
        fi

        return 0
    fi

    # Merge.
    path="$(git rev-parse --git-path MERGE_HEAD 2>/dev/null)"
    if [[ -f "$path" ]]; then
        echo "merge"
        return 0
    fi

    # Cherry-pick.
    path="$(git rev-parse --git-path CHERRY_PICK_HEAD 2>/dev/null)"
    if [[ -f "$path" ]]; then
        echo "cherry-pick"
        return 0
    fi

    # Revert.
    path="$(git rev-parse --git-path REVERT_HEAD 2>/dev/null)"
    if [[ -f "$path" ]]; then
        echo "revert"
        return 0
    fi

    # Bisect.
    path="$(git rev-parse --git-path BISECT_START 2>/dev/null)"
    if [[ -f "$path" ]]; then
        echo "bisect"
        return 0
    fi

    echo "none"
}

############################################
# CONFLICT STATE
############################################

get_git_conflict_state() {
    local conflicts

    # Unmerged index entries represent unresolved conflicts.

    if ! conflicts="$(git ls-files -u 2>/dev/null)"; then
        echo "unavailable"
        return 0
    fi

    if [[ -n "$conflicts" ]]; then
        echo "conflicted"
    else
        echo "none"
    fi
}


############################################
# SAFETY BRANCHES
############################################

get_git_safety_branches() {
    # Report branch names and their commit hashes.
    # Empty output means no matching local safety branches.

    git for-each-ref \
        --format='%(refname:short) %(objectname)' \
        refs/heads/git-safety-* \
        refs/heads/git-activation-safety-*
}
