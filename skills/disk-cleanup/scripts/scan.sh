#!/usr/bin/env bash
set -uo pipefail

home="${HOME:?}"
os="$(uname -s)"

size_kib() {
  [ -e "$1" ] || return 0
  local kib
  kib="$(du -sk "$1" 2>/dev/null | awk '{print $1}')"
  [ -n "$kib" ] && [ "$kib" -gt 0 ] && printf '%s\t%s\t%s%s\n' "$2" "$kib" "$1" "${3:+$'\t'$3}"
}

git_state() {
  local repo
  repo="$(git -C "$(dirname "$1")" rev-parse --show-toplevel 2>/dev/null)" || { echo no-git; return; }
  if [ -n "$(git -C "$repo" ls-files -- "$1" 2>/dev/null | head -1)" ]; then
    echo tracked
  elif git -C "$repo" check-ignore -q -- "$1" 2>/dev/null; then
    echo ignored
  else
    echo untracked
  fi
}

df -Pk / | awk 'NR==2 {printf "disk\t%s\ttotal\ndisk\t%s\tused\ndisk\t%s\tavailable\n", $2, $3, $4}'

for entry in "$home"/* "$home"/.[!.]*; do
  [ -L "$entry" ] && continue
  size_kib "$entry" top-home
done

candidates=(
  "$home/.cache"
  "$home/.npm/_cacache"
  "$home/.bun/install/cache"
  "$home/.cargo/registry"
  "$home/.cargo/git"
  "$home/.gradle/caches"
  "$home/.m2/repository"
  "$home/.terraform.d/plugin-cache"
  "$home/.local/share/pnpm/store"
  "$home/.cache/pip"
  "$home/.cache/uv"
  "$home/.cache/go-build"
  "$home/.cache/huggingface"
  "$home/go/pkg/mod"
  "$home/.Trash"
  "${TMPDIR:-/tmp}"
)
if [ "$os" = Darwin ]; then
  candidates+=(
    "$home/Library/Caches"
    "$home/Library/Logs"
    "$home/Library/Developer/Xcode/DerivedData"
    "$home/Library/Developer/Xcode/Archives"
    "$home/Library/Developer/Xcode/iOS DeviceSupport"
    "$home/Library/Developer/CoreSimulator/Caches"
    "$home/Library/Developer/CoreSimulator/Devices"
    "$home/Library/Containers/com.docker.docker/Data"
    "$home/Library/Group Containers/HUQ7J3W4SJ.com.orbstack"
  )
  for dir in "$home"/Library/Caches/*; do
    candidates+=("$dir")
  done
else
  candidates+=("$home/.local/share/Trash" "/var/tmp")
fi
command -v brew >/dev/null 2>&1 && candidates+=("$(brew --cache 2>/dev/null)")
command -v go >/dev/null 2>&1 && candidates+=("$(go env GOCACHE 2>/dev/null)" "$(go env GOMODCACHE 2>/dev/null)")

printf '%s\n' "${candidates[@]}" | awk 'NF && !seen[$0]++' | while IFS= read -r path; do
  size_kib "$path" candidate
done

roots=("$@")
[ ${#roots[@]} -eq 0 ] && roots=("$home/repos")
build_names=(node_modules target dist build out .next .nuxt .turbo .terraform .terragrunt-cache __pycache__ .pytest_cache .mypy_cache .ruff_cache .venv venv .gradle coverage .parcel-cache)
name_expr=()
for name in "${build_names[@]}"; do
  name_expr+=(-name "$name" -o)
done
unset 'name_expr[${#name_expr[@]}-1]'
for root in "${roots[@]}"; do
  [ -d "$root" ] || continue
  find "$root" -type d \( -name .git -prune -o \( "${name_expr[@]}" \) -prune -print \) 2>/dev/null |
    while IFS= read -r dir; do size_kib "$dir" build "$(git_state "$dir")"; done
done

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  docker system df --format '{{.Type}}\t{{.Size}}\t{{.Reclaimable}}' 2>/dev/null |
    awk -F'\t' '{printf "docker\t0\t%s | size %s | reclaimable %s\n", $1, $2, $3}'
  docker ps -a --filter status=exited --filter status=created --format '{{.Names}} {{.Image}} {{.Status}}' 2>/dev/null |
    awk '{printf "docker\t0\tstopped-container %s\n", $0}'
  docker volume ls -qf dangling=true 2>/dev/null | awk '{printf "docker\t0\tdangling-volume %s\n", $1}'
  docker images -qf dangling=true 2>/dev/null | awk '{printf "docker\t0\tdangling-image %s\n", $1}'
fi

if [ -d /nix/store ]; then
  size_kib /nix/store nix
  if command -v nix-env >/dev/null 2>&1; then
    nix-env --list-generations 2>/dev/null | awk 'END {printf "nix\t0\tuser-profile-generations %d\n", NR}'
  fi
fi
