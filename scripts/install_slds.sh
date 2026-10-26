#!/bin/sh
# Install the exact reviewed SLDS source revision; no moving branch dependency.
set -eu
linklet_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
slds_luarocks=${SLDS_LUAROCKS:-luarocks}
if [ "$#" -gt 0 ]; then
    case "$1" in /*) slds_tree=$1;; *) slds_tree="$(pwd)/$1";; esac
fi
slds_revision=$(cat "$linklet_root/dependencies/lua-slds.ref")
case "$slds_revision" in *[!0-9a-f]*|"") echo "invalid SLDS revision" >&2; exit 1;; esac
[ "${#slds_revision}" -eq 40 ] || { echo "invalid SLDS revision length" >&2; exit 1; }
slds_temp=$(mktemp -d)
trap 'rm -rf "$slds_temp"' EXIT HUP INT TERM
git init -q "$slds_temp/source"
git -C "$slds_temp/source" remote add origin https://github.com/fangfengxiang/lua-slds.git
git -C "$slds_temp/source" fetch --quiet --depth=1 origin "$slds_revision"
git -C "$slds_temp/source" checkout --quiet --detach FETCH_HEAD
[ "$(git -C "$slds_temp/source" rev-parse HEAD)" = "$slds_revision" ]
cd "$slds_temp/source"
if [ "$#" -gt 0 ]; then
    "$slds_luarocks" make --deps-mode=none --tree="$slds_tree"
else
    "$slds_luarocks" make --deps-mode=none
fi
