import subprocess
import sys
from pathlib import Path


res = subprocess.run(
    ["git", "rev-parse", "--show-toplevel"],
    capture_output=True,
    text=True,
)

if res.returncode != 0:
    ROOT = Path(__file__).resolve().parents[2]
else:
    ROOT = Path(res.stdout.strip())

SECRETS_DIR = ROOT / "gitops" / "secrets"


def apply_secret(secret_file):
    if secret_file.stat().st_size == 0:
        raise RuntimeError(f"Secret file is empty: {secret_file}")

    print(f"Decrypting: {secret_file}")

    decrypted = subprocess.run(
        ["sops", "-d", str(secret_file)],
        capture_output=True,
        text=True,
        check=True,
    )

    if not decrypted.stdout.strip():
        raise RuntimeError(
            f"Decrypted secret is empty: {secret_file}"
        )

    subprocess.run(
        ["kubectl", "apply", "--validate=false", "-f", "-"],
        input=decrypted.stdout,
        text=True,
        check=True,
    )

    print(f"✓ Applied: {secret_file}")


def execute_secrets():
    if not SECRETS_DIR.is_dir():
        raise RuntimeError(
            f"Secrets directory not found: {SECRETS_DIR}"
        )

    directories = sorted(
        path for path in SECRETS_DIR.iterdir()
        if path.is_dir()
    )

    for secret_dir in directories:

        yaml_files = sorted(secret_dir.glob("*.yaml"))

        if not yaml_files:
            print(f"SKIP: {secret_dir} is empty")
            continue

        print()
        print(f"Processing: {secret_dir.name}")

        for secret_file in yaml_files:
            apply_secret(secret_file)


def main():
    print("==============================")
    print(" KUBAPP SECRET EXECUTOR")
    print("==============================")
    print(f"Secrets: {SECRETS_DIR}")

    execute_secrets()

    print()
    print("✓ Secret execution complete.")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, subprocess.CalledProcessError) as exc:
        print(f"❌ {exc}", file=sys.stderr)
        sys.exit(1)
