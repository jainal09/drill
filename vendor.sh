#!/bin/bash
# ============================================================================
#  vendor.sh -- fetch the sidebar's plugins, at pinned commits, into vendor/.
#
#  drill has no plugin manager, and this is not one: it is a table of three
#  (name, url, sha) rows and a loop. Each checkout is shallow, detached, and
#  byte-reproducible -- the same SHA on every machine, today and in a year.
#  Nothing here runs at editor startup; explorer.lua only reads the result.
#
#  Called by install.sh after copying files, by tests/run.sh as a preflight,
#  or by hand after a git pull. Already at the pin? It is an offline no-op.
# ============================================================================
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENDOR="$DIR/vendor"

# Pinned 2026-08-16. Bump deliberately: update the SHA, run ./vendor.sh,
# then run ./tests/run.sh -- suite_tree exercises every API call the glue
# makes, so a pin bump that breaks one fails loudly before it ships.
PINS="
nvim-tree.lua https://github.com/nvim-tree/nvim-tree.lua.git b2aadda94b107480c48e548d6db51c6840b7b33c
volt          https://github.com/nvzone/volt.git             620de1321f275ec9d80028c68d1b88b409c0c8b1
menu          https://github.com/nvzone/menu.git             7a0a4a2896b715c066cfbe320bdc048091874cc6
"

command -v git >/dev/null 2>&1 || {
  echo "vendor.sh: git is required to fetch the sidebar plugins" >&2
  exit 1
}

echo "$PINS" | while read -r name url sha; do
  [ -z "$name" ] && continue
  dest="$VENDOR/$name"
  have="$(git -C "$dest" rev-parse HEAD 2>/dev/null || true)"
  if [ "$have" = "$sha" ]; then
    echo "vendor.sh: $name already at ${sha:0:12}"
    continue
  fi
  echo "vendor.sh: fetching $name @ ${sha:0:12}"
  rm -rf "$dest"
  mkdir -p "$dest"
  git -C "$dest" init -q
  # GitHub serves fetches of a bare SHA (allow-any-sha1-in-want), so this
  # needs no branch name and survives upstream force-pushes.
  git -C "$dest" fetch -q --depth 1 "$url" "$sha"
  git -C "$dest" checkout -q FETCH_HEAD
done

echo "vendor.sh: vendor/ ready"
