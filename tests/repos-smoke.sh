#!/usr/bin/env bash
# All Git remotes in this test are temporary local bare repositories. No network.
set -Eeuo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
export TEST_REPOS_TMP="$tmp"
export GIT_REPOS_MODULE="$script_dir/../config/git_repos.lua"
export GIT_REPOS_TEST="$script_dir/repos.lua"
export XDG_CONFIG_HOME="$tmp/config" XDG_DATA_HOME="$tmp/data"
export XDG_STATE_HOME="$tmp/state" XDG_CACHE_HOME="$tmp/cache"
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
nvim --headless -u NONE '+lua dofile(vim.env.GIT_REPOS_TEST)'
