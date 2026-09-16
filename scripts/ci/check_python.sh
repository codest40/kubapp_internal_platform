#!/bin/bash

set -euo pipefail

if command -v python >/dev/null 2>&1; then
            echo "Python command available"
            python --version
else
            echo "Python command not available, instaling...."
            sudo apt update
            sudo apt install python3 python3-pip
fi
