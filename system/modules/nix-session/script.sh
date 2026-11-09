# nix-session: build a flake package once and keep its programs on PATH in
# every terminal until reboot. State lives in $XDG_RUNTIME_DIR (a tmpfs), so a
# reboot (or a full logout) wipes it, and the build's GC root goes with it.

dir="${XDG_RUNTIME_DIR:?XDG_RUNTIME_DIR is not set}/nix-session"
apps="$dir/apps"
bin="$dir/bin"

usage() {
  cat <<USAGE
Usage: nix-session <command> [args]

Build a flake package and keep its programs on PATH in every terminal until
reboot. Nothing in the dotfiles changes.

Commands:
  add [flake-ref] [nix build args...]
                         Build (default ".") and link its bin/* into PATH.
                         Running it again on the same ref rebuilds and relinks.
  list                   Show what is in this session.
  remove <key|flake-ref> Remove one entry (its build can be GC'd again).
  clear                  Remove everything now.

Examples:
  nix-session add
  nix-session add .#myapp -L
  nix-session add github:owner/repo
  nix-session remove .
USAGE
}

# Local paths become absolute, so "." means the same project from any folder.
normalize_ref() {
  local ref="$1" base frag=""
  base="${ref%%#*}"
  if [[ "$ref" == *"#"* ]]; then
    frag="#${ref#*#}"
  fi
  case "$base" in
    "" | . | .. | ./* | ../* | /*) base="$(realpath -- "${base:-.}")" ;;
    path:*) base="path:$(realpath -- "${base#path:}")" ;;
  esac
  printf '%s%s\n' "$base" "$frag"
}

key_of() {
  printf '%s' "$1" | sha1sum | cut -c1-12
}

# Remove the links in $bin that point into this entry.
unlink_entry() {
  local entry="$apps/$1" link target
  [[ -d "$bin" ]] || return 0
  for link in "$bin"/*; do
    [[ -L "$link" ]] || continue
    target="$(readlink -- "$link")"
    if [[ "$target" == "$entry/"* ]]; then
      rm -f -- "$link"
    fi
  done
}

# Programs this entry has linked into $bin.
linked_bins() {
  local entry="$apps/$1" link target names=()
  [[ -d "$bin" ]] || return 0
  for link in "$bin"/*; do
    [[ -L "$link" ]] || continue
    target="$(readlink -- "$link")"
    if [[ "$target" == "$entry/"* ]]; then
      names+=("$(basename -- "$link")")
    fi
  done
  printf '%s\n' "${names[*]-}"
}

# An entry given by key, or by the same flake ref that was added.
resolve_key() {
  local arg="$1" key
  if [[ "$arg" =~ ^[0-9a-f]{12}$ && -d "$apps/$arg" ]]; then
    printf '%s\n' "$arg"
    return 0
  fi
  key="$(key_of "$(normalize_ref "$arg")")"
  if [[ -d "$apps/$key" ]]; then
    printf '%s\n' "$key"
    return 0
  fi
  echo "nix-session: nothing added for '$arg' (see 'nix-session list')" >&2
  return 1
}

cmd_add() {
  local ref="." norm key entry exe name old linked=()
  if [[ $# -gt 0 && "$1" != -* ]]; then
    ref="$1"
    shift
  fi
  norm="$(normalize_ref "$ref")"
  key="$(key_of "$norm")"
  entry="$apps/$key"
  mkdir -p -- "$entry" "$bin"

  # --out-link registers a GC root for the build. It lives on a tmpfs, so the
  # root is gone after reboot and the next GC can collect the build.
  if ! nix build "$norm" --out-link "$entry/result" "$@"; then
    # A first build that failed leaves an empty entry behind; drop it.
    if [[ ! -e "$entry/result" ]]; then
      rm -rf -- "$entry"
    fi
    return 1
  fi
  printf '%s\n' "$norm" >"$entry/ref"

  unlink_entry "$key"
  if [[ -d "$entry/result/bin" ]]; then
    for exe in "$entry/result/bin"/*; do
      [[ -e "$exe" ]] || continue
      name="$(basename -- "$exe")"
      if [[ -L "$bin/$name" ]]; then
        old="$(readlink -- "$bin/$name")"
        old="$(cat -- "${old%/result/bin/*}/ref" 2>/dev/null || echo "$old")"
        if [[ "$old" != "$norm" ]]; then
          echo "nix-session: '$name' now comes from $norm (was $old)" >&2
        fi
      fi
      ln -sfn -- "$entry/result/bin/$name" "$bin/$name"
      linked+=("$name")
    done
  fi

  echo "Added $norm ($key) -> $(readlink -- "$entry/result")"
  if [[ ${#linked[@]} -gt 0 ]]; then
    echo "On PATH until reboot: ${linked[*]}"
  else
    echo "It has no bin/ folder, so nothing went on PATH; the build stays at $entry/result"
  fi
  case ":$PATH:" in
    *":$bin:"*) ;;
    *) echo "This shell started before nix-session was set up; open a new terminal to use them." >&2 ;;
  esac
}

cmd_list() {
  local entry key found=0
  for entry in "$apps"/*/; do
    [[ -d "$entry" ]] || continue
    found=1
    key="$(basename -- "$entry")"
    echo "$key  $(cat -- "$entry/ref" 2>/dev/null || echo '?')"
    echo "    $(readlink -- "$entry/result" 2>/dev/null || echo '(no build)')"
    echo "    bin: $(linked_bins "$key")"
  done
  if [[ $found -eq 0 ]]; then
    echo "Nothing in this session. Add something with: nix-session add [flake-ref]"
  fi
}

cmd_remove() {
  local arg key
  if [[ $# -eq 0 ]]; then
    echo "nix-session: remove needs a key or flake ref" >&2
    return 1
  fi
  for arg in "$@"; do
    key="$(resolve_key "$arg")" || return 1
    unlink_entry "$key"
    echo "Removed $(cat -- "$apps/$key/ref" 2>/dev/null || echo "$key")"
    rm -rf -- "${apps:?}/$key"
  done
}

cmd_clear() {
  rm -rf -- "$dir"
  echo "Cleared everything in this session."
}

case "${1-}" in
  add) shift; cmd_add "$@" ;;
  list | ls) shift; cmd_list "$@" ;;
  remove | rm) shift; cmd_remove "$@" ;;
  clear) cmd_clear ;;
  -h | --help | help | "") usage ;;
  *)
    echo "nix-session: unknown command '$1'" >&2
    usage >&2
    exit 1
    ;;
esac
