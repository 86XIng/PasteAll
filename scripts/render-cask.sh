#!/bin/bash
# Prints the Homebrew cask for a release: render-cask.sh <version> <sha256> [owner/repo]

set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="${1:-}"
sha256="${2:-}"
repository="${3:-86XIng/PasteAll}"
bundle_id="${PASTEALL_BUNDLE_ID:-io.github.86xing.PasteAll}"

[[ "$version" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || { echo "Invalid version: $version" >&2; exit 2; }
[[ "$sha256" =~ ^[0-9a-f]{64}$ ]] || { echo "Invalid SHA-256: $sha256" >&2; exit 2; }
[[ "$repository" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "Invalid repository: $repository" >&2; exit 2; }

sed -e "s|@VERSION@|$version|g" \
    -e "s|@SHA256@|$sha256|g" \
    -e "s|@REPOSITORY@|$repository|g" \
    -e "s|@BUNDLE_ID@|$bundle_id|g" \
    "$project_root/packaging/homebrew/paste-all.rb.template"
