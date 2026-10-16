#!/usr/bin/env bash

############################################
# GIT DIAGNOSIS
# Purpose:
#   Interpret facts returned by git_functions2.sh.
############################################

_GIT_DIAGNOSIS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$_GIT_DIAGNOSIS_DIR/git_functions2.sh"
unset _GIT_DIAGNOSIS_DIR

diagnose_git_history() {
    local upstream
    local ahead
    local behind

    upstream="$(get_git_upstream)"
    ahead="$(get_git_ahead_count)"
    behind="$(get_git_behind_count)"

    if [[ "$upstream" == "none" ]]; then
        echo "No upstream tracking branch is configured."
        return 0
    fi

    if [[ "$upstream" == "unavailable" ||
          "$ahead" == "unavailable" ||
          "$behind" == "unavailable" ]]; then
        echo "Unable to determine the history relationship."
        return 0
    fi

    if [[ ! "$ahead" =~ ^[0-9]+$ ||
          ! "$behind" =~ ^[0-9]+$ ]]; then
        echo "Unable to determine the history relationship."
        return 0
    fi

    if (( ahead > 0 && behind > 0 )); then
        echo "Local and upstream histories have diverged."

    elif (( ahead > 0 )); then
        echo "Local history is ahead of upstream."

    elif (( behind > 0 )); then
        echo "Local history is behind upstream."

    else
        echo "Local and upstream histories are synchronized."
    fi
}

############################################
# WORKING TREE DIAGNOSIS
############################################

diagnose_git_worktree() {
    local worktree
    local diff
    local untracked

    worktree="$(get_git_worktree_state)"
    diff="$(get_git_diff_state)"
    untracked="$(get_git_untracked_state)"

    echo "Git working tree diagnosis:"
    echo

    if [[ "$worktree" == "unavailable" ]]; then
        echo "Unable to determine the working tree state."
        return 0
    fi

    if [[ "$worktree" == "clean" ]]; then
        echo "Working tree is clean."
        echo "No tracked or untracked changes detected."
        return 0
    fi

    echo "Working tree has changes."

    case "$diff" in
        staged)
            echo "- Staged changes are present."
            ;;

        unstaged)
            echo "- Unstaged changes are present."
            ;;

        staged-and-unstaged)
            echo "- Both staged and unstaged changes are present."
            ;;

        unchanged)
            echo "- No tracked content differences detected."
            ;;

        unavailable)
            echo "- Unable to determine tracked content differences."
            ;;
    esac

    case "$untracked" in
        present)
            echo "- Untracked files are present."
            ;;

        none)
            echo "- No untracked files detected."
            ;;

        unavailable)
            echo "- Unable to determine untracked file state."
            ;;
    esac
}


############################################
# ACTIVE OPERATION AND CONFLICT DIAGNOSIS
############################################

diagnose_git_operation() {
    local operation
    local conflict

    operation="$(get_git_operation)"
    conflict="$(get_git_conflict_state)"

    echo "Git operation diagnosis:"
    echo

    case "$operation" in
        none)
            echo "No active Git operation detected."
            ;;

        unavailable)
            echo "Unable to determine the active Git operation."
            ;;

        *)
            echo "Active Git operation: $operation"
            ;;
    esac

    case "$conflict" in
        conflicted)
            echo "Unresolved conflicts are present."
            ;;

        none)
            echo "No unresolved conflicts detected."
            ;;

        unavailable)
            echo "Unable to determine the conflict state."
            ;;
    esac
}

############################################
# CONFLICT DIAGNOSIS
############################################

diagnose_git_conflicts() {
    local operation
    local conflict

    operation="$(get_git_operation)"
    conflict="$(get_git_conflict_state)"

    echo "Git conflict diagnosis:"
    echo

    if [[ "$operation" == "unavailable" ||
          "$conflict" == "unavailable" ]]; then
        echo "Unable to determine the complete conflict state."
        return 0
    fi

    if [[ "$conflict" == "conflicted" ]]; then
        echo "Unresolved conflicts are present."

        case "$operation" in
            rebase)
                echo "The repository has conflicts during a rebase."
                ;;

            merge)
                echo "The repository has conflicts during a merge."
                ;;

            cherry-pick)
                echo "The repository has conflicts during a cherry-pick."
                ;;

            revert)
                echo "The repository has conflicts during a revert."
                ;;

            none)
                echo "No recognized active Git operation was detected."
                echo "Further inspection is needed to understand the conflict state."
                ;;

            *)
                echo "The active operation is: $operation"
                echo "Inspect the repository state to understand the context."
                ;;
        esac

    else
        echo "No unresolved conflicts detected."

        case "$operation" in
            rebase)
                echo "A rebase is in progress without detected conflicts."
                ;;

            merge)
                echo "A merge is in progress without detected conflicts."
                ;;

            cherry-pick)
                echo "A cherry-pick is in progress without detected conflicts."
                ;;

            revert)
                echo "A revert is in progress without detected conflicts."
                ;;

            none)
                echo "No active Git operation detected."
                ;;

            *)
                echo "Active Git operation: $operation"
                ;;
        esac
    fi
}

############################################
# HISTORY AND WORKTREE RISK DIAGNOSIS
############################################

############################################
# HISTORY AND WORKTREE RISK DIAGNOSIS
############################################

diagnose_git_sync_risk() {
    local upstream
    local ahead
    local behind
    local worktree

    upstream="$(get_git_upstream)"
    ahead="$(get_git_ahead_count)"
    behind="$(get_git_behind_count)"
    worktree="$(get_git_worktree_state)"

    echo "Git synchronization diagnosis:"
    echo

    if [[ "$upstream" == "none" ]]; then
        echo "No upstream tracking branch is configured."
        echo "Local/upstream synchronization cannot be assessed."
        return 0
    fi

    if [[ "$upstream" == "unavailable" ||
          "$ahead" == "unavailable" ||
          "$behind" == "unavailable" ||
          "$worktree" == "unavailable" ]]; then
        echo "Unable to determine the complete synchronization state."
        return 0
    fi

    if [[ ! "$ahead" =~ ^[0-9]+$ ||
          ! "$behind" =~ ^[0-9]+$ ]]; then
        echo "Unable to determine the complete synchronization state."
        return 0
    fi

    if [[ "$worktree" != "clean" &&
          "$worktree" != "dirty" ]]; then
        echo "Unable to determine the complete synchronization state."
        return 0
    fi

    if (( ahead > 0 && behind > 0 )); then
        echo "Local and upstream histories have diverged."

        if [[ "$worktree" == "dirty" ]]; then
            echo "The working tree also contains local changes."
        fi

    elif (( behind > 0 )); then
        echo "Local history is behind upstream."

        if [[ "$worktree" == "dirty" ]]; then
            echo "The working tree contains local changes."
            echo "Preserve those changes when planning any history update."
        fi

    elif (( ahead > 0 )); then
        echo "Local commits have not yet reached upstream."

    else
        echo "Local and upstream histories are synchronized."
    fi
}

############################################
# REPOSITORY STATE VALIDATION
############################################

diagnose_git_repository_state() {
    local branch
    local head
    local head_state
    local upstream
    local issues=0

    branch="$(get_git_branch)"
    head="$(get_git_head)"
    head_state="$(get_git_head_state)"
    upstream="$(get_git_upstream)"

    echo "Git repository state validation:"
    echo

    # Validate repository identity.
    if [[ "$head_state" == "unavailable" ]]; then
        echo "Unable to verify a valid Git HEAD."
        echo "The repository may have no commits, or Git metadata may be unavailable."
        issues=$((issues + 1))
    else
        echo "HEAD state: $head_state"
    fi

    # Validate the current branch.
    if [[ "$branch" == "unavailable" ]]; then
        echo "Unable to determine the current branch."
        issues=$((issues + 1))

    elif [[ "$branch" == "none" ]]; then
        echo "No branch is checked out; HEAD is detached."

    else
        echo "Current branch: $branch"
    fi

    # Validate the current commit.
    if [[ "$head" == "unavailable" ]]; then
        echo "Current commit cannot be resolved."
        issues=$((issues + 1))
    else
        echo "Current commit: $head"
    fi

    # Check upstream configuration.
    if [[ "$upstream" == "none" ]]; then
        echo "No upstream tracking branch is configured."
        echo "Synchronization with an upstream cannot be assessed."
    else
        echo "Upstream: $upstream"
    fi

    echo

    if [[ "$issues" -gt 0 ]]; then
        echo "Repository validation: incomplete."
    else
        echo "Repository identity checks passed."
    fi
}

############################################
# COMPLETE GIT DIAGNOSIS
############################################
diagnose_git_repository() {
    echo "========================================"
    echo "GIT REPOSITORY DIAGNOSIS"
    echo "========================================"
    echo

    diagnose_git_repository_state

    echo
    echo "----------------------------------------"
    echo

    diagnose_git_sync_risk

    echo
    echo "----------------------------------------"
    echo

    diagnose_git_worktree

    echo
    echo "----------------------------------------"
    echo

    diagnose_git_conflicts

    echo
    echo "========================================"
    echo "DIAGNOSIS COMPLETE"
    echo "========================================"
}
