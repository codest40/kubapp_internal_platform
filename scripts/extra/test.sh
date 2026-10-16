#!/bin/bash

echo "========== REPOSITORY =========="
echo "branch:       $(get_git_branch)"
echo "HEAD:         $(get_git_head)"
echo "HEAD state:   $(get_git_head_state)"
echo "upstream:     $(get_git_upstream)"
echo "remote HEAD:  $(get_git_remote_head)"

echo
echo "========== WORKING TREE =========="
echo "worktree:     $(get_git_worktree_state)"
echo "diff:         $(get_git_diff_state)"
echo "staged:       $(get_git_staged_state)"
echo "unstaged:     $(get_git_unstaged_state)"
echo "untracked:    $(get_git_untracked_state)"

echo
echo "========== HISTORY =========="
echo "ahead:        $(get_git_ahead_count)"
echo "behind:       $(get_git_behind_count)"

echo
echo "========== OPERATION =========="
echo "operation:    $(get_git_operation)"
echo "conflict:     $(get_git_conflict_state)"

echo
echo "========== SAFETY =========="
get_git_safety_branches
