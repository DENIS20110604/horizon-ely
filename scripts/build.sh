#!/usr/bin/env bash
# Builds the patched launcher: a pinned upstream checkout, the patches, then cargo.
#
#   ./scripts/build.sh            # the launcher, into .work/target/release
#   ./scripts/build.sh --game     # also the game client (the skins), a longer build
#   JOBS=2 ./scripts/build.sh     # fewer rustc jobs (little RAM)
#
# The upstream clone lives in .work/upstream, the build in .work/target; both are ignored by git.
# Re-running resets the checkout to the pin and applies the patches again, so it always builds
# exactly the tag in upstream.txt.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
read -r ref sha <<<"$(grep -v '^[[:space:]]*#' "$root/upstream.txt" | grep -v '^[[:space:]]*$' | head -1)"
version=$(grep -v '^[[:space:]]*#' "$root/version.txt" | grep -v '^[[:space:]]*$' | head -1)
game_version=$(grep -v '^[[:space:]]*#' "$root/game-version.txt" | grep -v '^[[:space:]]*$' | head -1)
work=${WORK:-$root/.work}
src=$work/upstream
target=${CARGO_TARGET_DIR:-$work/target}
repo=${UPSTREAM_REPO:-https://github.com/horizon-rust/horizon.git}
game=0
for arg in "$@"; do
    case $arg in
    --game) game=1 ;;
    -h | --help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "error: unknown option $arg (see --help)" >&2; exit 2 ;;
    esac
done

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
    git apply --check --ignore-whitespace "$patch"
    git apply --ignore-whitespace "$patch"
done

say "Building $version (target: $target)"
cd "$src/launcher"
HORIZON_LAUNCHER_VERSION=$version \
    CARGO_TARGET_DIR=$target \
    cargo build --release --locked ${JOBS:+--jobs "$JOBS"}

bin=$target/release/horizon-launcher
[ -x "$bin" ] || { echo "error: no binary at $bin" >&2; exit 1; }
say "Built: $bin ($("$bin" --version))"

if [ "$game" = 1 ]; then
    say "Building the game client $game_version (the skins patches)"
    cd "$src"
    HORIZON_VERSION=$game_version \
        CARGO_TARGET_DIR=$target \
        cargo build --release --locked --features horizon-client/mods \
        -p horizon-client --bin horizon-client ${JOBS:+--jobs "$JOBS"}
    client=$target/release/horizon-client
    [ -x "$client" ] || { echo "error: no client at $client" >&2; exit 1; }
    say "Built: $client ($(stat -c%s "$client" 2>/dev/null || wc -c <"$client") bytes)"
fi
