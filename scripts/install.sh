#!/usr/bin/env bash
# Installs the patched launcher and game client, keeping what they replace as backups.
#
#   ./scripts/install.sh                         # the build in .work/target/release
#   ./scripts/install.sh --download              # the newest GitHub release (needs gh)
#   ./scripts/install.sh --replace PATH          # replace a launcher already installed there
#   ./scripts/install.sh --uninstall             # put the launcher's backup back
#
# The game client (the skin patches) goes into the installed version's folder, the one Play
# starts: ~/.local/share/horizon-launcher/versions/<tag>/horizon-client. Horizon's own update of
# that version puts the official client back; run this again after one.
#
# The launcher keeps its data, so versions, worlds and accounts stay where they are. This build
# never updates itself (the official update would remove the patch); Horizon's game releases
# still install from the Versions page.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
version=$(grep -v '^[[:space:]]*#' "$root/version.txt" | grep -v '^[[:space:]]*$' | head -1)
work=${WORK:-$root/.work}
data=${HORIZON_LAUNCHER_HOME:-$HOME/.local/share/horizon-launcher}

say() { printf '\033[1m%s\033[0m\n' "$*"; }
die() { echo "error: $*" >&2; exit 1; }

binary=""
client=""
dest=${DEST:-}
replace=""
uninstall=""
download=""
with_client=1
while [ $# -gt 0 ]; do
    case $1 in
    --binary) binary=$2; shift 2 ;;
    --client) client=$2; shift 2 ;;
    --dest) dest=$2; shift 2 ;;
    --replace) replace=$2; shift 2 ;;
    --download) download=1; shift ;;
    --no-client) with_client=0; shift ;;
    --uninstall) uninstall=1; shift ;;
    -h | --help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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

# The installed version Play starts: settings.json's selection, else the newest installed.
selected_version() {
    local tag
    tag=$(sed -n 's/.*"selected"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
        "$data/settings.json" 2>/dev/null | head -1)
    if [ -z "$tag" ] && [ -d "$data/versions" ]; then
        tag=$(ls -1 "$data/versions" 2>/dev/null | sort -V | tail -1)
    fi
    echo "$tag"
}

if [ -n "$uninstall" ]; then
    backup=$(ls -1t "$dest".bak-* 2>/dev/null | head -1 || true)
    [ -n "$backup" ] || die "no backup beside $dest (nothing to restore)"
    [ -x "$dest" ] && "$dest" desktop-entry --remove >/dev/null 2>&1 || true
    mv -f "$backup" "$dest"
    say "Restored $("$dest" --version 2>/dev/null || echo "$dest")"
    tag=$(selected_version)
    client_dest=$data/versions/$tag/horizon-client
    client_backup=$(ls -1t "$client_dest".bak-* 2>/dev/null | head -1 || true)
    if [ -n "$client_backup" ]; then
        mv -f "$client_backup" "$client_dest"
        say "Restored the official game client of $tag"
    fi
    exit 0
fi

if [ -n "$download" ]; then
    command -v gh >/dev/null || die "--download needs the GitHub CLI (gh)"
    say "Downloading the newest release"
    tmp=$(mktemp -d)
    (cd "$root" && gh release download --pattern 'horizon-launcher-linux-x86_64.tar.gz' \
        --pattern 'horizon-client-linux-x86_64.tar.gz' --dir "$tmp")
    tar xzf "$tmp"/horizon-launcher-linux-x86_64.tar.gz -C "$tmp"
    binary=$tmp/horizon-launcher
    if [ -f "$tmp/horizon-client-linux-x86_64.tar.gz" ]; then
        tar xzf "$tmp"/horizon-client-linux-x86_64.tar.gz -C "$tmp"
        client=$tmp/horizon-client
    fi
fi

[ -n "$binary" ] || binary=$work/target/release/horizon-launcher
[ -x "$binary" ] || die "no launcher at $binary: run ./scripts/build.sh first, or --download"
if [ "$with_client" = 1 ] && [ -z "$client" ] && [ -x "$work/target/release/horizon-client" ]; then
    client=$work/target/release/horizon-client
fi

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

if [ "$with_client" = 1 ] && [ -n "$client" ]; then
    [ -x "$client" ] || die "no game client at $client (build it with ./scripts/build.sh --game)"
    tag=$(selected_version)
    [ -n "$tag" ] || die "no installed game version: install one on the Versions page, then run this again"
    client_dest=$data/versions/$tag/horizon-client
    [ -f "$client_dest" ] || die "no game client at $client_dest: install $tag on the Versions page first"
    cp -p "$client_dest" "$client_dest.bak-$(date +%Y%m%d%H%M%S)"
    install -m 755 "$client" "$client_dest"
    say "Patched the game client of $tag ($client_dest)"
elif [ "$with_client" = 1 ]; then
    echo "note: no game client built or downloaded: the game keeps its official one (default skins)"
fi

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
