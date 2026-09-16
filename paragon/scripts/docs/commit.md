# Commit

## What It Does

The `commit.sh` script stages selected files or directories, creates a
Git commit, and pushes the changes to the `main` branch.

It:

- Detects whether it is running locally or in CI.
- Stages only the paths provided to the script.
- Creates a commit when changes exist.
- Pushes the commit to `main`.
- Rebases against the remote branch if the initial push fails.
- Retries the push up to three times.
- Uses a recovery strategy on the final failed attempt.

## What It Expects to Already Exist

The script expects:

- Git to be installed.
- The current directory to be inside a Git repository, or a valid
  repository working directory when running locally.
- The `main` branch to be the intended remote branch.
- A configured Git remote named `origin`.
- GitHub authentication/access for pushing to the repository.
- The files or directories being committed to already exist.

The script requires at least one argument specifying a file or directory.

```bash
./scripts/commit.sh <file_or_directory>

A commit message can optionally be provided as the last argument:
./scripts/commit.sh gitops/ "Update GitOps configuration"

