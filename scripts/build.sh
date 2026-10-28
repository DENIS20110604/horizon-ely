#!/usr/bin/env bash
# Builds the patched launcher: a pinned upstream checkout, the patches, then cargo.
#
#   ./scripts/build.sh            # release build into .work/target/release
#   JOBS=2 ./scripts/build.sh     # fewer rustc jobs (little RAM)
#
# The upstream clone lives in .work/upstream, the build in .work/target; both are ignored by git.
# Re-running resets the checkout to the pin and applies the patches again, so it always builds
# exactly the tag in upstream.txt.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
read -r ref sha <<<"$(grep -v '^[[:space:]]*#' "$root/upstream.txt" | grep -v '^[[:space:]]*$' | head -1)"
version=$(tr -d '[:space:]' <"$root/version.txt")
work=${WORK:-$root/.work}
src=$work/upstream
target=${CARGO_TARGET_DIR:-$work/target}
repo=${UPSTREAM_REPO:-https://github.com/horizon-rust/horizon.git}

say() { printf '\033[1m%s\033[0m\n' "$*"; }

mkdir -p "$work"
if [ ! -d "$src/.git" ]; then
    say "Cloning $repo at $ref"
    git clone --depth 1 --branch "$ref" "$repo" "$src"
fi

cd "$src"
say "Resetting the checkout to $ref"
git fetch --depth 1 origin "refs/tags/$ref:refs/tags/$ref" >/dev/null 2>&1 || true
git checkout -f --quiet "$ref"
git clean -ffd --quiet
if [ "$(git rev-parse HEAD)" != "$sha" ]; then
    echo "error: $ref is $(git rev-parse HEAD), upstream.txt says $sha" >&2
    echo "       (the tag moved, or upstream.txt is stale; fix it before building)" >&2
    exit 1
fi

shopt -s nullglob
patches=("$root"/patches/*.patch)
if [ ${#patches[@]} -eq 0 ]; then
    echo "error: no patches in $root/patches" >&2
    exit 1
fi
for patch in "${patches[@]}"; do
    say "Applying $(basename "$patch")"
    git apply --check "$patch"
    git apply "$patch"
done

say "Building $version (target: $target)"
cd "$src/launcher"
HORIZON_LAUNCHER_VERSION=$version \
    CARGO_TARGET_DIR=$target \
    cargo build --release --locked ${JOBS:+--jobs "$JOBS"}

bin=$target/release/horizon-launcher
[ -x "$bin" ] || { echo "error: no binary at $bin" >&2; exit 1; }
say "Built: $bin ($("$bin" --version))"
