discover_repo() {
  local remote_url repo_path

  remote_url="$(git -C "$ROOT_DIR" remote get-url origin 2>/dev/null || true)"

  if [[ -z "$remote_url" ]]; then
    echo "❌ Could not determine the GitHub repository from origin."
    exit 1
  fi

  case "$remote_url" in
    https://github.com/*)
      repo_path="${remote_url#https://github.com/}"
      ;;
    git@github.com:*)
      repo_path="${remote_url#git@github.com:}"
      ;;
    git-*:*/*)
      repo_path="${remote_url#*:}"
      ;;
    *)
      echo "❌ Unsupported GitHub remote format: $remote_url"
      exit 1
      ;;
  esac

  repo_path="${repo_path%.git}"

  REPO="$(gh repo view "$repo_path" --json nameWithOwner --jq '.nameWithOwner')"
  REPO_URL="$(gh repo view "$repo_path" --json url --jq '.url')"

  echo "Repository: $REPO"
  echo "URL:        $REPO_URL"
}


set_github_variable() {
  local name="$1"
  local value="$2"

  if gh variable list --repo "$REPO" --json name --jq '.[].name' |
    grep -Fxq "$name"; then
    echo "✓ $name already exists"
    return
  fi

  gh variable set "$name" --repo "$REPO" --body "$value"
  echo "✓ $name created"
}


set_github_secret() {
  local name="$1"
  local value="$2"

  if gh secret list --repo "$REPO" --json name --jq '.[].name' |
    grep -Fxq "$name"; then
    echo "✓ $name already exists"
    return
  fi

  gh secret set "$name" --repo "$REPO" --body "$value"
  echo "✓ $name created"
}


github_secret_exists() {
  local name="$1"

  gh secret list --repo "$REPO" --json name --jq '.[].name' |
    grep -Fxq "$name"
}


generate_age_key() {
  local key_file
  local age_key

  command -v age-keygen >/dev/null 2>&1 || {
    echo "❌ age-keygen is required to generate AGE_PRIVATE_KEY."
    exit 1
  }

  key_file="$(mktemp)"

  age-keygen -o "$key_file" >/dev/null 2>&1

  age_key="$(grep '^AGE-SECRET-KEY-' "$key_file")"

  rm -f "$key_file"

  if [[ -z "$age_key" ]]; then
    echo "❌ Failed to generate AGE private key."
    exit 1
  fi

  AGE_PRIVATE_KEY="$age_key"

  if [[ -n "${SETUP_ENV_FILE:-}" ]]; then
    if ! grep -q '^AGE_PRIVATE_KEY=' "$SETUP_ENV_FILE"; then
      printf '\nAGE_PRIVATE_KEY=%q\n' "$AGE_PRIVATE_KEY" >> "$SETUP_ENV_FILE"
    fi
  fi

  echo "✓ Generated AGE_PRIVATE_KEY"
}


configure_github_variables() {
  echo
  echo "========== GITHUB VARIABLES =========="

  set_github_variable "AWS_REGION" "$AWS_REGION"
  set_github_variable "AWS_ROLE_ARN" "$GITHUB_ROLE_ARN"
  set_github_variable "REPO" "$REPO"
  set_github_variable "REPO_URL" "$REPO_URL"

  if [[ -n "${DOMAIN:-}" ]]; then
    set_github_variable "DOMAIN" "$DOMAIN"
  fi

  if [[ -n "${DOCKER_USER:-}" ]]; then
    set_github_variable "DOCKER_USER" "$DOCKER_USER"
  fi
}


configure_github_secrets() {
  echo
  echo "========== GITHUB SECRETS =========="

  if github_secret_exists "AGE_PRIVATE_KEY"; then
    echo "✓ AGE_PRIVATE_KEY already exists"
  else
    if [[ -z "${AGE_PRIVATE_KEY:-}" ]]; then
      generate_age_key
    fi

    set_github_secret "AGE_PRIVATE_KEY" "$AGE_PRIVATE_KEY"
  fi

  if [[ -n "${APP_ID_GITHUB:-}" ]]; then
    set_github_secret "APP_ID_GITHUB" "$APP_ID_GITHUB"
  fi

  if [[ -n "${APP_PRIVATE_KEY_GITHUB:-}" ]]; then
    set_github_secret "APP_PRIVATE_KEY_GITHUB" "$APP_PRIVATE_KEY_GITHUB"
  fi

  if [[ -n "${INSTALLATION_ID:-}" ]]; then
    set_github_secret "INSTALLATION_ID" "$INSTALLATION_ID"
  fi

  if [[ -n "${ARGOCD_AUTH_TOKEN:-}" ]]; then
    set_github_secret "ARGOCD_AUTH_TOKEN" "$ARGOCD_AUTH_TOKEN"
  fi

  if [[ -n "${ARGOCD_SERVER:-}" ]]; then
    set_github_secret "ARGOCD_SERVER" "$ARGOCD_SERVER"
  fi

  if [[ -n "${DOCKER_PASS:-}" ]]; then
    set_github_secret "DOCKER_PASS" "$DOCKER_PASS"
  fi

  if [[ -n "${INFRACOST_API_KEY:-}" ]]; then
    set_github_secret "INFRACOST_API_KEY" "$INFRACOST_API_KEY"
  fi

  if [[ -n "${NVD_API_KEY:-}" ]]; then
    set_github_secret "NVD_API_KEY" "$NVD_API_KEY"
  fi

  if [[ -n "${SYS_MONITOR_WEBHOOK:-}" ]]; then
    set_github_secret "SYS_MONITOR_WEBHOOK" "$SYS_MONITOR_WEBHOOK"
  fi
}


configure_github_app() {
  local app_id_exists=false
  local private_key_exists=false
  local installation_id_exists=false

  echo
  echo "========== GITHUB APP =========="

  if github_secret_exists "APP_ID_GITHUB"; then
    app_id_exists=true
    echo "✓ APP_ID_GITHUB already exists"
  fi

  if github_secret_exists "APP_PRIVATE_KEY_GITHUB"; then
    private_key_exists=true
    echo "✓ APP_PRIVATE_KEY_GITHUB already exists"
  fi

  if github_secret_exists "INSTALLATION_ID"; then
    installation_id_exists=true
    echo "✓ INSTALLATION_ID already exists"
  fi

  if [[ "$app_id_exists" == true &&
        "$private_key_exists" == true &&
        "$installation_id_exists" == true ]]; then
    echo "✓ GitHub App configuration already exists"
    return
  fi

  if [[ -n "${APP_ID_GITHUB:-}" &&
        -n "${APP_PRIVATE_KEY_GITHUB:-}" &&
        -n "${INSTALLATION_ID:-}" ]]; then
    echo "✓ GitHub App credentials supplied through setup.env"
    return
  fi

  echo "⚠️ GitHub App configuration is incomplete."

  [[ "$app_id_exists" == false ]] &&
    echo "   Missing: APP_ID_GITHUB"

  [[ "$private_key_exists" == false ]] &&
    echo "   Missing: APP_PRIVATE_KEY_GITHUB"

  [[ "$installation_id_exists" == false ]] &&
    echo "   Missing: INSTALLATION_ID"

  echo
  echo "   GitHub App registration/installation is required for this account."
  echo "This is an interactive workflow"
  echo "Create it by running ./scripts/github/setup_app.sh"
  return 1
}


install_infracost() {
  echo
  echo "========== INFRACOST =========="

  if command -v infracost >/dev/null 2>&1; then
    echo "✓ Infracost already installed"
  else
    echo "Installing Infracost..."

    curl -fsSL https://raw.githubusercontent.com/infracost/cli/master/scripts/install.sh | sh

    command -v infracost >/dev/null 2>&1 || {
      echo "❌ Infracost installation failed."
      exit 1
    }

    echo "✓ Infracost installed"
  fi
}


configure_infracost() {
  echo
  echo "========== INFRACOST AUTH =========="

  if infracost auth whoami >/dev/null 2>&1; then
    echo "✓ Infracost already authenticated"
  else
    echo "Infracost authentication required..."
    infracost auth login
  fi

  if github_secret_exists "INFRACOST_API_KEY"; then
    echo "✓ INFRACOST_API_KEY already exists"
  elif [[ -n "${INFRACOST_API_KEY:-}" ]]; then
    set_github_secret "INFRACOST_API_KEY" "$INFRACOST_API_KEY"
  else
    echo "⚠️ INFRACOST_API_KEY is not configured in GitHub."
  fi
}

