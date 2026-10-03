#!/usr/bin/env bash
# Run on every build so an incremental build cannot retain old Git metadata.
# The app target disables Xcode script sandboxing because git status must read
# tracked and untracked inputs throughout the checkout and its Git metadata.
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_path="${1:?Provide the output resource path}"
export GIT_OPTIONAL_LOCKS=0
revision="unknown"
if [[ -e "$project_dir/.git" ]]; then
    revision="$(git -C "$project_dir" rev-parse --verify HEAD)"
    if [[ -n "$(git -C "$project_dir" status --porcelain --untracked-files=normal)" ]]; then
        revision="$revision-modified"
    fi
elif [[ -f "$project_dir/.git-revision" ]]; then
    # git archive expands this tracked file through export-subst.
    archived_revision="$(cat "$project_dir/.git-revision")"
    if [[ "$archived_revision" =~ ^[0-9a-f]{40}$ ]]; then
        revision="$archived_revision"
    fi
fi
mkdir -p "$(dirname "$output_path")"
printf '%s\n' "$revision" > "$output_path"
