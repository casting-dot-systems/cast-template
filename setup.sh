#!/usr/bin/env bash
set -euo pipefail

# Usage: ./cast-setup.sh [--force]
#  --force : overwrite an existing cast.sh (a timestamped backup is kept)

command -v git >/dev/null 2>&1 || { echo "Error: git not found in PATH"; exit 1; }

REPO_ROOT="$(pwd)"
FORCE=0
if [[ "${1:-}" == "--force" ]]; then FORCE=1; fi

# Targets
CASTPLATES_PARENT="$REPO_ROOT/Media/Templates"
CASTPLATES_DIR="$CASTPLATES_PARENT/Castplates"
CASTPLATES_URL="https://github.com/casting-dot-systems/Castplates.git"

OBSIDIAN_DIR="$REPO_ROOT/.obsidian"
OBSIDIAN_URL="https://github.com/casting-dot-systems/.obsidian.git"

clone_if_needed() {
  local url="$1" dst="$2"
  if [[ -d "$dst/.git" ]]; then
    echo "Already a git repo: $dst  -> skip"
    return 0
  fi
  if [[ -e "$dst" && ! -d "$dst/.git" ]]; then
    echo "Exists but not a git repo: $dst"
    echo "Delete/move it, or turn it into a git repo, then rerun."
    exit 1
  fi
  mkdir -p "$(dirname "$dst")"
  echo "Cloning $url -> $dst"
  git clone "$url" "$dst"
}

write_cast_sh() {
  local out="$REPO_ROOT/cast.sh"
  if [[ -e "$out" && $FORCE -eq 0 ]]; then
    echo "cast.sh already exists. Use --force to overwrite (a backup will be created)."
    return 0
  fi
  if [[ -e "$out" && $FORCE -eq 1 ]]; then
    local ts; ts="$(date '+%Y%m%d-%H%M%S')"
    cp -f "$out" "$out.bak.$ts"
    echo "Backed up existing cast.sh -> $out.bak.$ts"
  fi

  cat > "$out" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

# Sub-repos (relative to repo root)
DIRS=(
  ".obsidian"
  "Media/Templates/Castplates"
)

usage() {
  cat <<'EOF'
Usage: ./cast.sh <save|update> [options]

Actions:
  save      -> git add -A && git commit -m "<msg>" && git push
  update    -> git reset --hard && git pull --ff-only

Options:
  -m, --message "msg"   Commit message for 'save' (default: chore: subrepo sync <timestamp>)
  --only <path>         Run on only this sub-repo (can be passed multiple times)
  -n, --dry-run         Show commands without executing
  -v, --verbose         Echo commands as they run
  -h, --help            Show this help

Examples:
  ./cast.sh save -m "wip: tweaks"
  ./cast.sh update
  ./cast.sh save --only .obsidian -m "update workspace"
  ./cast.sh update --only "Media/Templates/Castplates"
EOF
}

ACTION="${1:-}"; shift || true
DRY_RUN=0
VERBOSE=0
MESSAGE="chore: subrepo sync ($(date '+%Y-%m-%d %H:%M'))"
ONLY=()

while (( "$#" )); do
  case "$1" in
    -m|--message) MESSAGE="${2:-}"; shift 2;;
    --only) ONLY+=("${2:-}"); shift 2;;
    -n|--dry-run) DRY_RUN=1; shift;;
    -v|--verbose) VERBOSE=1; shift;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 1;;
  esac
done

if [[ -z "${ACTION}" || ! "${ACTION}" =~ ^(save|update)$ ]]; then
  usage; exit 1
fi

run() {
  [[ $VERBOSE -eq 1 ]] && echo "+ $*"
  if [[ $DRY_RUN -eq 1 ]]; then
    return 0
  fi
  "$@"
}

is_git_repo() {
  local dir="$1"
  [[ -d "$dir/.git" ]] || git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

current_branch() {
  git -C "$1" rev-parse --abbrev-ref HEAD
}

has_origin() {
  git -C "$1" remote get-url origin >/dev/null 2>&1
}

has_upstream() {
  git -C "$1" rev-parse --abbrev-ref --symbolic-full-name "@{u}" >/dev/null 2>&1
}

save_repo() {
  local dir="$1"
  echo "==> SAVE $dir"
  if ! is_git_repo "$dir"; then
    echo "    Skipped: not a git repo."
    return 0
  fi

  run git -C "$dir" add -A
  if ! run git -C "$dir" commit -m "$MESSAGE"; then
    echo "    Nothing to commit."
  fi

  if has_origin "$dir"; then
    if has_upstream "$dir"; then
      run git -C "$dir" push
    else
      local br; br="$(current_branch "$dir" || echo "")"
      if [[ -n "$br" && "$br" != "HEAD" ]]; then
        run git -C "$dir" push -u origin "$br"
      else
        echo "    No branch or detached HEAD; cannot push. (Try: git -C \"$dir\" checkout -b main)"
      fi
    fi
  else
    echo "    No 'origin' remote configured; skipping push."
  fi
}

update_repo() {
  local dir="$1"
  echo "==> UPDATE $dir"
  if ! is_git_repo "$dir"; then
    echo "    Skipped: not a git repo."
    return 0
  fi

  local br; br="$(current_branch "$dir" || echo "HEAD")"
  if [[ "$br" == "HEAD" ]]; then
    echo "    Detached HEAD in $dir. Please checkout a branch (e.g., 'git -C \"$dir\" checkout main'). Skipping."
    return 0
  fi

  run git -C "$dir" fetch --all --prune
  run git -C "$dir" reset --hard
  if has_origin "$dir"; then
    run git -C "$dir" pull --ff-only || {
      echo "    Fast-forward only pull failed. You may need to rebase or check remote branch."
      return 1
    }
  else
    echo "    No 'origin' remote configured; skipping pull."
  fi
}

main() {
  local targets=("${DIRS[@]}")
  if ((${#ONLY[@]})); then
    targets=("${ONLY[@]}")
  fi

  for d in "${targets[@]}"; do
    if [[ ! -d "$d" ]]; then
      echo "==> Skipping $d (missing directory)"
      continue
    fi
    case "$ACTION" in
      save)   save_repo "$d"   ;;
      update) update_repo "$d" ;;
    esac
  done
  echo "All done."
}

main
SCRIPT

  chmod +x "$out"
  echo "Wrote and chmod +x $out"
}

# --- Do the work ---
clone_if_needed "$CASTPLATES_URL" "$CASTPLATES_DIR"
clone_if_needed "$OBSIDIAN_URL"   "$OBSIDIAN_DIR"
write_cast_sh

echo "✅ Setup complete."
echo "Next: ./cast.sh save -m 'initial sync'  or  ./cast.sh update"

