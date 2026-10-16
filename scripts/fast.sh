
#!/bin/bash

DIR="${DIR:-}"
ARG="${1:-}"

P="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "$ARG" ]]; then
    echo "CORRECT USAGE: ./$0 <file ext type>"
    exit 1
fi

if [[ -n "$DIR" && -d "$P/$DIR" ]]; then
    cd "$DIR"
elif [[ ! -d "$P/$DIR" ]]; then
   echo "INVALID DIR: $P/$DIR"
   exit 1
fi

shopt -s nullglob
files=(*."$ARG")

if (( ${#files[@]} == 0 )); then
    echo "No .$ARG files found."
    exit 1
fi

for i in "${files[@]}"; do
    echo "======================================================="
    echo "$i"
    echo "======================================================="
    cat "$i"
done
