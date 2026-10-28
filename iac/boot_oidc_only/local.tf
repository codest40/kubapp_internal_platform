locals {
  github_repository_subject = "repo:${var.github_repository_owner}@${var.github_repository_owner_id}/${var.github_repository_name}@${var.github_repository_id}"

  github_branch_subjects = [
    for branch in var.github_branches :
    "${local.github_repository_subject}:ref:refs/heads/${branch}"
  ]

  github_environment_subjects = [
    for environment in var.github_environments :
    "${local.github_repository_subject}:environment:${environment}"
  ]

  github_allowed_subjects = concat(
    local.github_branch_subjects,
    local.github_environment_subjects
  )
}
