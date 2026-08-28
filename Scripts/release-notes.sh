#!/bin/bash
#
# Builds the notes for one release.
#
# The notes are two pieces joined together. The first is what changed in this
# version, taken from its section of CHANGELOG.md so the changelog stays the one
# place a change is written down. The second is the standing description of what
# the app does and how to install it, from RELEASE_TEMPLATE.md, which is the
# same every time apart from the version in the file names.
#
# Usage:
#     Scripts/release-notes.sh [version]
#
# With no argument the version is read from Config/Base.xcconfig. The notes go
# to standard output, so redirect them where you need them.

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_directory/.." && pwd)"

changelog="$repository_root/CHANGELOG.md"
template="$repository_root/.github/RELEASE_TEMPLATE.md"

for required in "$changelog" "$template"; do
    if [ ! -f "$required" ]; then
        echo "Missing $required" >&2
        exit 1
    fi
done

if [ "$#" -ge 1 ]; then
    version="$1"
else
    version="$(
        grep '^MARKETING_VERSION' "$repository_root/Config/Base.xcconfig" \
            | head -1 \
            | sed 's/.*= *//' \
            | tr -d '[:space:]'
    )"
fi

if [ -z "$version" ]; then
    echo "Could not work out which version to build notes for." >&2
    exit 1
fi

# The section runs from this version's heading to the next version heading.
changes="$(
    awk -v want="## [$version]" '
        index($0, want) == 1 { collecting = 1; next }
        collecting && /^## \[/ { exit }
        collecting { print }
    ' "$changelog"
)"

# Trim the blank lines the section picks up at each end.
changes="$(printf '%s\n' "$changes" | sed '/./,$!d' | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')"

if [ -z "$changes" ]; then
    echo "CHANGELOG.md has no section for $version." >&2
    echo "Add one before building the notes." >&2
    exit 1
fi

printf '## What changed in %s\n\n' "$version"
printf '%s\n\n' "$changes"

# VERSION in the template stands in for the number, so the file names in the
# install section match the files actually attached to the release.
sed "s/VERSION/$version/g" "$template"
