#!/usr/bin/env python3

import os
import subprocess
import tempfile
from pathlib import Path

from reuse import get_root


ROOT = get_root("path")
if not ROOT:
    raise SystemExit("Could not determine repository root")


SECRET_FILE = (
    ROOT
    / "gitops"
    / "secret_mgt"
    / "db"
    / "kubapp-db-secrets.yml"
)


def run(command, cwd=None, env=None):
    return subprocess.run(
        command,
        cwd=cwd,
        env=env,
        text=True,
        capture_output=True,
    )


def update_secret(status, host=None):
    with tempfile.NamedTemporaryFile(
        mode="w",
        suffix=".yml",
        delete=False,
    ) as temp:
        temp_file = Path(temp.name)

    try:
        decrypt = run(
            ["sops", "-d", str(SECRET_FILE)],
            cwd=ROOT,
        )

        if decrypt.returncode != 0:
            print(decrypt.stderr.strip())
            raise SystemExit(
                "Failed to decrypt database secret file"
            )

        temp_file.write_text(
            decrypt.stdout,
            encoding="utf-8",
        )

        env = os.environ.copy()
        env["DB_STATUS"] = status

        expression = (
            ".secrets.DB_STATUS = strenv(DB_STATUS)"
        )

        if host:
            env["DB_HOST"] = host
            expression += (
                " | .secrets.DB_HOST = strenv(DB_HOST)"
            )

        update = run(
            [
                "yq",
                "-i",
                expression,
                str(temp_file),
            ],
            cwd=ROOT,
            env=env,
        )

        if update.returncode != 0:
            print(update.stderr.strip())
            raise SystemExit(
                "Failed to update database secret"
            )

        encrypt = run(
            [
                "sops",
                "-e",
                "--filename-override",
                str(SECRET_FILE),
                str(temp_file),
            ],
            cwd=ROOT,
        )

        if encrypt.returncode != 0:
            print(encrypt.stderr.strip())
            raise SystemExit(
                "Failed to encrypt database secret"
            )

        SECRET_FILE.write_text(
            encrypt.stdout,
            encoding="utf-8",
        )

    finally:
        temp_file.unlink(missing_ok=True)


def main():
    if not SECRET_FILE.exists():
        raise SystemExit(
            f"Database secret file not found: {SECRET_FILE}"
        )

    print("======================================")
    print(" Database Secret Update")
    print("======================================")

    host = os.environ.get("DB_HOST", "").strip()

    if not host:
        print("⚠️ Database endpoint is empty")
        print("Marking database as inactive")

        update_secret("inactive")

        print("✅ Database secret marked inactive")
        return

    print("Database endpoint detected")
    #print("Database endpoint: {host}")
    update_secret(
        "active",
        host,
    )

    print("✅ Database secret updated")
    print("   DB_STATUS: active")


if __name__ == "__main__":
    main()
