#!/bin/sh
# Seed one linked worktree with the ignored build artifacts named by its
# .worktreeinclude, then prove that the Apple core it received is current.
#
# Codex worktree setup supplies CODEX_WORKTREE_PATH. Running this script by
# hand from inside a linked worktree uses that checkout as the target instead.

set -eu

script_dir=$(cd "$(dirname "$0")" && pwd -P)
target=${CODEX_WORKTREE_PATH:-$script_dir}
target=$(cd "$target" && pwd -P)

common_dir=$(git -C "$script_dir" rev-parse --path-format=absolute --git-common-dir)
source_checkout=$(dirname "$common_dir")
workspace=$(dirname "$source_checkout")

if [ "$target" = "$source_checkout" ]; then
  echo "error: the primary checkout cannot be seeded as a worktree." >&2
  exit 1
fi
case "$target/" in
  "$workspace"/*/) ;;
  *)
    echo "error: the target is outside the MiniXiangqi workspace: $target" >&2
    exit 1
    ;;
esac

target_common=$(git -C "$target" rev-parse --path-format=absolute --git-common-dir)
if [ "$target_common" != "$common_dir" ]; then
  echo "error: the target is not a linked worktree of $source_checkout" >&2
  exit 1
fi

include="$target/.worktreeinclude"
if [ ! -f "$include" ]; then
  echo "error: the target has no .worktreeinclude" >&2
  exit 1
fi

while IFS= read -r path || [ -n "$path" ]; do
  path=${path%/}
  case "$path" in
    ""|[[:space:]]*|\#*) continue ;;
    /*|.|..|../*|*/../*|*/..|.git|.git/*|*\**|*\?*|*\[* )
      echo "error: .worktreeinclude contains a non-literal or unsafe path: $path" >&2
      exit 1
      ;;
  esac

  if ! git -C "$target" check-ignore -q -- "$path" &&
     ! git -C "$target" check-ignore -q -- "$path/"; then
    echo "error: .worktreeinclude path is not ignored: $path" >&2
    exit 1
  fi

  source_path="$source_checkout/$path"
  target_path="$target/$path"
  if [ ! -e "$source_path" ] && [ ! -L "$source_path" ]; then
    echo "note: source artifact is absent and was not seeded: $path"
    continue
  fi

  if [ -L "$target_path" ] || [ -f "$target_path" ]; then
    rm -f "$target_path"
  elif [ -d "$target_path" ]; then
    rm -rf "$target_path"
  elif [ -e "$target_path" ]; then
    echo "error: refusing to replace an unsupported filesystem object: $target_path" >&2
    exit 1
  fi

  mkdir -p "$(dirname "$target_path")"
  cp -pR "$source_path" "$target_path"
  echo "seeded $path"
done < "$include"

cd "$target"
./apple/check-core-is-current.sh
