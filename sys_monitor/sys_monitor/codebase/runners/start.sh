#!/bin/bash

echo "Starting Codebase..."
FILE=${RUNNER:-./runner.sh}

if [[ -f "$FILE" ]]; then
    echo "Running Scripts......"
    bash "$FILE"
else
  echo "Startup code Runner script for Report Creation is Not found"
  exit 1
fi

echo "Building Codebase App.."
docker build -t codebase .

echo ""
echo "Running codebase next..."
docker run \
  -p 8080:8080 \
  -v "$(cd ../evidence && pwd):/evidence" \
  codebase

