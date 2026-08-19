#!/usr/bin/env bash
#
# runme.sh — install neb14's personal bastion dotfiles.
#
# Idempotent and safe to re-run. Fetches the tracked dotfiles from this repo
# into $HOME, working around the two things that bite on a bastion:
#   1. raw.githubusercontent.com CDN caching (cache-busted with a timestamp).
#   2. a target file left root-owned by an earlier run (can't be overwritten;
#      we detect it and sudo-fix ownership).
#
# Personal config lives in ~/.bashrc.d/personal so the skel-managed ~/.bashrc
# (which sources ~/.bashrc.d/*) picks it up and skel-sync never clobbers it.
#
# Usage (on the bastion):
#   curl -fsSL https://raw.githubusercontent.com/neb14/duo-dotfiles/main/runme.sh | bash
#   # or, if already cloned/downloaded:
#   bash runme.sh

set -uo pipefail

REPO_RAW="https://raw.githubusercontent.com/neb14/duo-dotfiles/main"

# path-in-repo  ->  destination-in-$HOME
FILES=(
    ".bashrc.d/personal:$HOME/.bashrc.d/personal"
    ".screenrc:$HOME/.screenrc"
)

log()  { printf '  %s\n' "$*"; }
ok()   { printf '  \033[32m[ok]\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m[warn]\033[0m %s\n' "$*"; }
err()  { printf '  \033[31m[err]\033[0m %s\n' "$*" >&2; }

fetch_one() {
    local src="$1" dest="$2"
    local url="$REPO_RAW/$src?$(date +%s)"   # cache-bust

    mkdir -p "$(dirname "$dest")"

    # If the file exists but we can't write it (e.g. root-owned from a prior
    # run), fix ownership so the write succeeds.
    if [[ -e "$dest" && ! -w "$dest" ]]; then
        warn "$dest not writable — fixing ownership with sudo"
        sudo chown "$(id -un):$(id -gn)" "$dest" || { err "could not chown $dest"; return 1; }
    fi

    local tmp
    tmp="$(mktemp)" || { err "mktemp failed"; return 1; }
    if ! curl -fL --retry 2 "$url" -o "$tmp"; then
        err "download failed: $url"
        rm -f "$tmp"
        return 1
    fi
    if [[ ! -s "$tmp" ]]; then
        err "downloaded empty file: $url"
        rm -f "$tmp"
        return 1
    fi

    install -m 0644 "$tmp" "$dest"
    rm -f "$tmp"
    ok "$dest ($(wc -l < "$dest") lines)"
}

echo "Installing dotfiles from $REPO_RAW"
rc=0
for entry in "${FILES[@]}"; do
    src="${entry%%:*}"
    dest="${entry#*:}"
    fetch_one "$src" "$dest" || rc=1
done

if [[ $rc -ne 0 ]]; then
    err "one or more files failed — see above"
    exit 1
fi

# Apply now in the current shell (only meaningful when sourced or run
# interactively; harmless otherwise).
if [[ -f "$HOME/.bashrc.d/personal" ]]; then
    # shellcheck disable=SC1090
    source "$HOME/.bashrc.d/personal" 2>/dev/null || true
fi

echo
ok "done."
log "New shells load ~/.bashrc.d/personal automatically."
log "In THIS shell, if the prompt didn't change, run:  source ~/.bashrc.d/personal"
log "Verify with:  echo \"\$PROMPT_COMMAND\"   # expect: __personal_prompt"
