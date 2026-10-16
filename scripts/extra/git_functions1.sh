#!/usr/bin/env bash

GIT_SAFETY_BRANCH=""
GIT_ACTIVATION_SAFETY_BRANCH=""
GIT_STASH_CREATED="false"

############################################
# SAFETY STATE
############################################

create_git_safety_branch() {
    GIT_SAFETY_BRANCH="git-safety-$(date '+%Y%m%d-%H%M%S')-$$"

    echo "[GIT] Creating safety branch: $GIT_SAFETY_BRANCH"

    if ! git branch "$GIT_SAFETY_BRANCH"; then
        echo "[GIT] ❌ Failed to create safety branch."
        GIT_SAFETY_BRANCH=""
        return 1
    fi

    echo "[GIT] ✅ Local committed state protected."
}


delete_git_safety_branch() {
    if [[ -z "$GIT_SAFETY_BRANCH" ]]; then
        return 0
    fi

    echo "[GIT] Removing safety branch: $GIT_SAFETY_BRANCH"

    if ! git branch -D "$GIT_SAFETY_BRANCH"; then
        echo "[GIT] ❌ Failed to delete safety branch."
        return 1
    fi

    echo "[GIT] ✅ Safety branch removed."
    GIT_SAFETY_BRANCH=""
}

create_git_activation_safety_branch() {
    GIT_ACTIVATION_SAFETY_BRANCH="git-activation-safety-$(date '+%Y%m%d-%H%M%S')-$$"

    echo "[GIT] Creating activation safety branch: $GIT_ACTIVATION_SAFETY_BRANCH"

    if ! git branch "$GIT_ACTIVATION_SAFETY_BRANCH"; then
        echo "[GIT] ❌ Failed to create activation safety branch."
        GIT_ACTIVATION_SAFETY_BRANCH=""
        return 1
    fi

    echo "[GIT] ✅ Activation commit protected."
}


delete_git_activation_safety_branch() {
    if [[ -z "$GIT_ACTIVATION_SAFETY_BRANCH" ]]; then
        return 0
    fi

    echo "[GIT] Removing activation safety branch: $GIT_ACTIVATION_SAFETY_BRANCH"

    if ! git branch -D "$GIT_ACTIVATION_SAFETY_BRANCH"; then
        echo "[GIT] ❌ Failed to delete activation safety branch."
        return 1
    fi

    echo "[GIT] ✅ Activation safety branch removed."
    GIT_ACTIVATION_SAFETY_BRANCH=""
}

############################################
# WORKING TREE PROTECTION
############################################

stash_git_changes() {
    if git diff --quiet && \
       git diff --cached --quiet && \
       [[ -z "$(git ls-files --others --exclude-standard)" ]]; then

        echo "[GIT] Working tree is clean."
        return 0
    fi

    echo "[GIT] Local uncommitted changes detected."
    echo "[GIT] Temporarily protecting working tree changes..."

    if git stash push --include-untracked \
        -m "git-automation-safety-$(date '+%Y%m%d-%H%M%S')"; then

        GIT_STASH_CREATED="true"
        echo "[GIT] ✅ Working tree changes protected."
        return 0
    fi

    echo "[GIT] ❌ Failed to protect working tree changes."
    return 1
}


restore_git_changes() {
    if [[ "$GIT_STASH_CREATED" != "true" ]]; then
        return 0
    fi

    echo "[GIT] Restoring protected working tree changes..."

    if git stash pop; then
        GIT_STASH_CREATED="false"
        echo "[GIT] ✅ Working tree changes restored."
        return 0
    fi

    echo
    echo "[GIT] ❌ Failed to restore working tree changes cleanly."
    echo "[GIT] Manual intervention is required."
    echo "[GIT] Safety branch preserved: $GIT_SAFETY_BRANCH"
    echo

    return 1
}


############################################
# REMOTE SYNCHRONIZATION
############################################

fetch_git_remote() {
    echo "[GIT] Fetching remote state..."

    if ! git fetch origin; then
        echo "[GIT] ❌ Failed to fetch remote."
        return 1
    fi

    echo "[GIT] ✅ Remote state updated."
}


rebase_git() {
    echo "[GIT] Rebasing local history onto origin/main..."

    if ! git rebase origin/main; then
        echo
        echo "[GIT] ❌ Rebase requires manual intervention."
        echo "[GIT] Safety branch preserved: $GIT_SAFETY_BRANCH"
        echo
        return 1
    fi

    echo "[GIT] ✅ Rebase successful."
}


############################################
# COMMIT / PUSH
############################################

commit_git() {
    local commit_message="$1"

    echo "[GIT] Staging changes..."

    git add .

    echo "[GIT] Creating commit..."

    if git commit -m "$commit_message"; then
        echo "[GIT] ✅ Commit created."
        return 0
    fi

    echo "[GIT] ⚠️ No changes to commit."
    return 0
}


push_git() {
    echo "[GIT] Pushing to remote..."

    if git push; then
        echo "[GIT] ✅ Push successful."
        return 0
    fi

    echo "[GIT] ⚠️ Push failed."
    return 1
}


############################################
# PREPARE LOCAL HISTORY
############################################

prepare_git() {
    echo
    echo "=================================================="
    echo "[GIT] PREPARING LOCAL HISTORY"
    echo "=================================================="

    ############################################
    # Protect committed local state.
    ############################################
    if ! create_git_safety_branch; then
        return 1
    fi

    ############################################
    # Protect uncommitted local work.
    ############################################
    if ! stash_git_changes; then
        echo "[GIT] ❌ Cannot continue."
        return 1
    fi

    ############################################
    # Get latest remote state.
    ############################################
    if ! fetch_git_remote; then
        echo "[GIT] ❌ Cannot continue."
        return 1
    fi

    ############################################
    # Reconcile existing local commits.
    ############################################
    if ! rebase_git; then
        echo
        echo "[GIT] ❌ Local history could not be reconciled."
        echo "[GIT] Pre-activation safety branch: $GIT_SAFETY_BRANCH"
        echo "[GIT] Activation safety branch: $GIT_ACTIVATION_SAFETY_BRANCH"
        echo
        return 1
    fi

    ############################################
    # Put local working changes back.
    ############################################
    if ! restore_git_changes; then
        return 1
    fi

    echo
    echo "[GIT] ✅ Local history prepared."
    echo "[GIT] Remote history is now the base for local work."
    echo

    return 0
}


############################################
# FINALIZE LOCAL CHANGES
############################################

finalize_git() {
    local commit_message="$1"

    echo
    echo "=================================================="
    echo "[GIT] FINALIZING LOCAL CHANGES"
    echo "=================================================="

    ############################################
    # Commit activation changes.
    ############################################
    if ! commit_git "$commit_message"; then
        echo "[GIT] ❌ Commit failed."
        return 1
    fi

    ############################################
    # Protect activation commit.
    ############################################
    if ! create_git_activation_safety_branch; then
        echo "[GIT] ❌ Cannot continue without activation safety."
        return 1
    fi

    ############################################
    # First push attempt.
    ############################################
    if push_git; then
        if ! delete_git_safety_branch; then
            return 1
        fi
        if ! delete_git_activation_safety_branch; then
            return 1
        fi
        return 0
    fi

    ############################################
    # Remote changed after preparation.
    ############################################
    echo
    echo "[GIT] Remote changed after preparation."
    echo "[GIT] Synchronizing again before retrying push..."
    echo

    if ! fetch_git_remote; then
        echo "[GIT] ❌ Failed to refresh remote state."
        echo "[GIT] Safety branch preserved: $GIT_SAFETY_BRANCH"
        return 1
    fi

    ############################################
    # Rebase activation commit onto new remote.
    ############################################
    if ! rebase_git; then
        echo
        echo "[GIT] ❌ Second rebase requires manual intervention."
        echo "[GIT] Pre-activation safety branch: $GIT_SAFETY_BRANCH"
        echo "[GIT] Activation safety branch: $GIT_ACTIVATION_SAFETY_BRANCH"
        echo
        return 1
    fi

    ############################################
    # Update activation safety to rebased HEAD.
    ############################################
    echo "[GIT] Updating activation safety branch to rebased HEAD..."
    if ! git branch -f "$GIT_ACTIVATION_SAFETY_BRANCH" HEAD; then
        echo "[GIT] ❌ Failed to update activation safety branch."
        echo "[GIT] Safety branch preserved: $GIT_ACTIVATION_SAFETY_BRANCH"
        return 1
    fi
    echo "[GIT] ✅ Rebasing result protected."

    ############################################
    # Retry push.
    ############################################
    if push_git; then
        if ! delete_git_safety_branch; then
          return 1
        fi
        if ! delete_git_activation_safety_branch; then
          return 1
        fi
        return 0
    fi

    echo
    echo "[GIT] ❌ Push failed after retry."
    echo "[GIT] Safety branch preserved: $GIT_SAFETY_BRANCH"
    echo

    return 1
}


############################################
# PUBLIC GIT ORCHESTRATOR
############################################

apply_git() {
    local action="${1:-rebase}"
    local phase="${2:-}"
    local commit_message="${3:-}"

    echo
    echo "--------------------------------------------------"
    echo "[GIT] ACTION: $action"
    echo "[GIT] PHASE:  ${phase:-none}"
    echo "--------------------------------------------------"

    case "$action" in

        rebase)

            case "$phase" in

                prepare)
                    prepare_git
                    ;;

                finalize)
                    finalize_git "$commit_message"
                    ;;

                *)
                    echo "[GIT] ❌ Invalid rebase phase: ${phase:-empty}"
                    echo
                    echo "Expected:"
                    echo "  apply_git rebase prepare"
                    echo "  apply_git rebase finalize \"commit message\""
                    return 1
                    ;;

            esac
            ;;

        resolve)
            echo "[GIT] ⚠️ Resolve action is not implemented yet."
            echo "[GIT] Safety state will be handled manually for now."
            return 1
            ;;

        *)
            echo "[GIT] ❌ Unknown ACTION: $action"
            echo
            echo "Supported actions:"
            echo "  rebase"
            echo "  resolve"
            return 1
            ;;

    esac
}


check_nested_git_repos() {
    local nested_git
    local found=0

    while IFS= read -r -d '' nested_git; do
        echo "[ERROR] ❌ Nested Git repository detected: $nested_git"
        found=1
    done < <(
        find "$ROOT" -mindepth 2 \
            \( -type d -o -type f \) -name ".git" -print0
    )

    if (( found )); then
        echo "[ERROR] ❌ Nested Git repositories found. Validation failed."
        return 1
    fi
    echo "[INFO] ✅ No nested Git repositories detected"
}
