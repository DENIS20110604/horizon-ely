#!/usr/bin/env bash
# Installs the patched launcher, keeping the one it replaces as a backup.
#
#   ./scripts/install.sh                         # the build in .work/target/release
#   ./scripts/install.sh --download              # the newest GitHub release (needs gh)
#   ./scripts/install.sh --replace PATH          # replace a launcher already installed there
#   ./scripts/install.sh --uninstall             # put the backup back
#
# The launcher keeps its data (~/.local/share/horizon-launcher), so versions, worlds and accounts
# stay where they are. This build never updates itself (the official update would remove the
# patch); Horizon's own game releases still install from the Versions page.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
version=$(tr -d '[:space:]' <"$root/version.txt")
work=${WORK:-$root/.work}

say() { printf '\033[1m%s\033[0m\n' "$*"; }
die() { echo "error: $*" >&2; exit 1; }

binary=""
dest=${DEST:-}
replace=""
uninstall=""
download=""
while [ $# -gt 0 ]; do
    case $1 in
    --binary) binary=$2; shift 2 ;;
    --dest) dest=$2; shift 2 ;;
    --replace) replace=$2; shift 2 ;;
    --download) download=1; shift ;;
    --uninstall) uninstall=1; shift ;;
    -h | --help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown option $1 (see --help)" ;;
    esac
done

# The launcher this run installs over: --replace, then --dest, then the one on PATH, then
# ~/.local/bin.
existing() {
    if [ -n "$replace" ]; then echo "$replace"; return; fi
    if [ -n "$dest" ]; then echo "$dest"; return; fi
    local found
    found=$(command -v horizon-launcher 2>/dev/null || true)
    if [ -n "$found" ]; then echo "$found"; return; fi
    if [ -x "$HOME/.local/bin/horizon-launcher" ]; then
        echo "$HOME/.local/bin/horizon-launcher"
        return
    fi
    echo "$HOME/.local/bin/horizon-launcher"
}

dest=$(existing)

if [ -n "$uninstall" ]; then
    backup=$(ls -1t "$dest".bak-* 2>/dev/null | head -1 || true)
    [ -n "$backup" ] || die "no backup beside $dest (nothing to restore)"
    [ -x "$dest" ] && "$dest" desktop-entry --remove >/dev/null 2>&1 || true
    mv -f "$backup" "$dest"
    say "Restored $("$dest" --version 2>/dev/null || echo "$dest")"
    exit 0
fi

if [ -z "$binary" ]; then
    if [ -n "$download" ]; then
        command -v gh >/dev/null || die "--download needs the GitHub CLI (gh)"
        say "Downloading the newest release"
        tmp=$(mktemp -d)
        gh release download --pattern 'horizon-launcher-linux-x86_64.tar.gz' --dir "$tmp"
        tar xzf "$tmp"/horizon-launcher-linux-x86_64.tar.gz -C "$tmp"
        binary=$tmp/horizon-launcher
    else
        binary=$work/target/release/horizon-launcher
    fi
fi
[ -x "$binary" ] || die "no binary at $binary: run ./scripts/build.sh first, or --download"

got=$("$binary" --version | awk '{print $2}')
[ "$got" = "$version" ] || die "$binary says $got, this repository builds $version"

if [ -e "$dest" ]; then
    old=$("$dest" --version 2>/dev/null | awk '{print $2}' || true)
    backup=$dest.bak-${old:-unknown}-$(date +%Y%m%d%H%M%S)
    say "Backing up $dest (${old:-unknown}) to $(basename "$backup")"
    cp -p "$dest" "$backup"
fi

mkdir -p "$(dirname "$dest")"
install -m 755 "$binary" "$dest"
say "Installed $("$dest" --version) at $dest"

case $dest in
"$HOME"/*)
    case ":$PATH:" in
    *":$(dirname "$dest"):"*) ;;
    *) echo "note: $(dirname "$dest") is not on PATH: run it as $dest" ;;
    esac
    ;;
esac

# The applications-menu entry points at this binary (a Linux-only command; the rest ignore it).
"$dest" desktop-entry >/dev/null 2>&1 || true

say "Offline: Settings → Account → add a name. Ely.by: the Ely.by card in Settings → Account."
