#!/bin/bash
set -euo pipefail

check_cmd() {
    local cmd="$1"
    local packages=("${@:2}")

    if command -v "$cmd" >/dev/null 2>&1; then
        echo "$cmd command available"
        "$cmd" --version
    else
        echo "ERROR: $cmd command not available."
        echo "Attempting to install the required package(s): ${packages[*]}"

        sudo apt update
        sudo apt install -y "${packages[@]}"

        if command -v "$cmd" >/dev/null 2>&1; then
            echo "$cmd command installed successfully."
            "$cmd" --version
        else
            echo "ERROR: Installation completed, but $cmd is still unavailable." >&2
            return 1
        fi
    fi
}

check_python() {
    check_cmd python python3
}

check_podman() {
    check_cmd podman podman uidmap slirp4netns fuse-overlayfs
}

check_python
check_podman
