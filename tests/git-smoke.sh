#!/usr/bin/env bash
# Run after installation. Changes only a temporary local repository; never pushes.
set -Eeuo pipefail
if [[ -f "$HOME/.config/lazyvim-linux-setup/env.sh" ]]; then
  # shellcheck disable=SC1091
  source "$HOME/.config/lazyvim-linux-setup/env.sh"
fi
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
export LAZYVIM_GIT_SMOKE_LUA="$script_dir/git.lua"
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
cd "$tmp"
git init -q --template=
mkdir empty-hooks
git config --local core.hooksPath "$tmp/empty-hooks"
git config --local user.name 'LazyVim Smoke Test'
git config --local user.email 'smoke@example.invalid'
git config --local commit.gpgsign false
printf 'original\n' > tracked.txt
git add tracked.txt
git commit -q -m initial
printf 'changed\n' > tracked.txt
nvim --headless tracked.txt '+lua dofile(vim.env.LAZYVIM_GIT_SMOKE_LUA)'
[[ $(git rev-list --count HEAD) == 2 ]]
printf 'PASS: Git status, stage, commit, blame, diff, log, keymaps and Gitsigns.\n'
