#!/usr/bin/env bash
# So para o GitHub Actions: guarda o log do teste num branch "ci-logs-<nome>".
set -uo pipefail
ARQ="$1"
NOME=$(basename "$ARQ" .log)
[[ -f "$ARQ" ]] || echo "(sem log)" > "$ARQ"
DIR=$(mktemp -d)
cp "$ARQ" "$DIR/"
cd "$DIR"
git init -q -b "ci-logs-$NOME"
git config user.name "github-actions"
git config user.email "github-actions@users.noreply.github.com"
git add .
git commit -qm "log $NOME - run ${GITHUB_RUN_ID:-local}"
git push -q -f "https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" "ci-logs-$NOME"
