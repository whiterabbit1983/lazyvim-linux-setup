#!/usr/bin/env bash
# LazyVim + Rust, Go, Python, TypeScript. Run as your normal Linux user.
set -Eeuo pipefail
trap 'printf "\nERROR at line %s. Installation stopped; backups were not deleted.\n" "$LINENO" >&2' ERR

usage() {
  printf 'Usage: bash install.sh [--yes] [--with-python]\n'
  printf 'Default: use existing Python. --with-python builds latest stable Python from python.org.\n'
  printf 'Supported: Linux Mint, Debian/Ubuntu, Fedora, Arch; x86_64/aarch64; Bash/Zsh.\n'
}
assume_yes=0
install_python=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --yes) assume_yes=1 ;;
    --with-python) install_python=1 ;;
    *) usage >&2; exit 2 ;;
  esac
  shift
done
[[ $(uname -s) == Linux ]] || { echo 'Linux is required.' >&2; exit 1; }
[[ $EUID -ne 0 ]] || { echo 'Run without sudo; the script uses sudo for system packages only.' >&2; exit 1; }
[[ ${NVIM_APPNAME:-nvim} == nvim ]] || { echo 'Unset NVIM_APPNAME first.' >&2; exit 1; }
case "$(uname -m)" in
  x86_64) arch=x86_64 ;;
  aarch64|arm64) arch=arm64 ;;
  *) echo 'Unsupported CPU architecture.' >&2; exit 1 ;;
esac
# shellcheck disable=SC1091
source /etc/os-release
case " $ID ${ID_LIKE:-} " in
  *' linuxmint '*|*' debian '*|*' ubuntu '*) distro=debian ;;
  *' fedora '*) distro=fedora ;;
  *' arch '*) distro=arch ;;
  *) echo "Unsupported distribution: $ID" >&2; exit 1 ;;
esac
printf '%s\n' \
  'This installs system dependencies and downloads software from official upstreams.' \
  'It selects the latest stable Rust, Go and Node.js (Current, not LTS).' \
  'Python is NOT replaced by default. C/C++ remain distro packages.' \
  'Existing Neovim configuration/data/cache/state will be MOVED to .bak-* paths.' \
  'It adds one environment-file source line to ~/.bashrc and ~/.zshrc.' \
  'Re-running creates a fresh LazyVim configuration, not an in-place update.' \
  'On Arch, pacman -Syu also upgrades the entire system.'
if [[ $install_python == 1 ]]; then
  printf '%s\n' '--with-python: compile latest stable Python from python.org (can take several minutes).'
  printf '%s\n' 'The user default changes, but /usr/bin/python3 is not replaced.'
fi
if [[ $assume_yes == 0 ]]; then
  read -r -p 'Continue? [y/N] ' answer
  [[ $answer == y || $answer == Y ]] || exit 0
fi
command -v sudo >/dev/null || { echo 'Install sudo and grant this user access first.' >&2; exit 1; }
sudo -v

case "$distro" in
  debian)
    sudo apt-get update
    sudo apt-get install -y curl ca-certificates unzip tar gzip xz-utils \
      build-essential pkg-config libssl-dev python3 python3-venv python3-pip \
      ripgrep fd-find xclip
    ;;
  fedora)
    sudo dnf install -y curl ca-certificates unzip tar gzip xz \
      gcc gcc-c++ make pkgconf-pkg-config openssl-devel python3 python3-pip \
      ripgrep fd-find xclip
    ;;
  arch)
    # A full upgrade is necessary on Arch: partial upgrades are unsupported.
    sudo pacman -Syu --needed --noconfirm curl ca-certificates unzip tar gzip xz \
      base-devel openssl python python-pip ripgrep fd xclip
    ;;
esac
# BEGIN ENSURE_GIT
if ! command -v git >/dev/null 2>&1; then
  printf 'Git is missing; installing the distribution package.\n'
  case "$distro" in
    debian) sudo apt-get install -y git ;;
    fedora) sudo dnf install -y git ;;
    arch) sudo pacman -S --needed --noconfirm git ;;
  esac
else
  printf 'Using existing Git: %s\n' "$(command -v git)"
fi
git --version
# END ENSURE_GIT
if [[ $install_python == 1 ]]; then
  case "$distro" in
    debian)
      sudo apt-get install -y zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev \
        libffi-dev liblzma-dev libncurses-dev libgdbm-dev libgdbm-compat-dev \
        tk-dev uuid-dev libzstd-dev ;;
    fedora)
      sudo dnf install -y zlib-devel bzip2-devel readline-devel sqlite-devel \
        libffi-devel xz-devel ncurses-devel gdbm-devel tk-devel libuuid-devel libzstd-devel ;;
    arch)
      sudo pacman -S --needed --noconfirm zlib bzip2 readline sqlite libffi \
        ncurses gdbm tk util-linux-libs zstd ;;
  esac
fi
if [[ -n ${WAYLAND_DISPLAY:-} ]]; then
  case "$distro" in
    debian) sudo apt-get install -y wl-clipboard ;;
    fedora) sudo dnf install -y wl-clipboard ;;
    arch) sudo pacman -S --needed --noconfirm wl-clipboard ;;
  esac
fi

export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export MISE_DATA_DIR="${MISE_DATA_DIR:-$XDG_DATA_HOME/mise}"
mkdir -p "$HOME/.local/bin" "$HOME/.local/opt" "$HOME/.config/lazyvim-linux-setup"
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
stamp="$(date +%Y%m%d-%H%M%S)-$$"
backup() {
  if [[ -e $1 || -L $1 ]]; then
    mv -- "$1" "$1.bak-$stamp"
    printf 'Backup: %s\n' "$1.bak-$stamp"
  fi
}
fetch() { curl --fail --location --retry 3 "$1" -o "$2"; }

# A small shared PATH file works in both Bash and Zsh.
env_file="$HOME/.config/lazyvim-linux-setup/env.sh"
cat > "$env_file" <<'ENV'
export PATH="$HOME/.local/bin:${MISE_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/mise}/shims:${CARGO_HOME:-$HOME/.cargo}/bin:${XDG_DATA_HOME:-$HOME/.local/share}/nvim/mason/bin:$PATH"
ENV
# Expand HOME when the user's shell starts, not while generating the line.
# shellcheck disable=SC2016
source_line='[ ! -f "$HOME/.config/lazyvim-linux-setup/env.sh" ] || . "$HOME/.config/lazyvim-linux-setup/env.sh"'
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
  touch "$rc"
  if ! grep -Fqx "$source_line" "$rc"; then
    printf '\n%s\n' "$source_line" >> "$rc"
  fi
done
# shellcheck disable=SC1090
source "$env_file"
if ! command -v fd >/dev/null && command -v fdfind >/dev/null; then
  ln -s "$(command -v fdfind)" "$HOME/.local/bin/fd"
fi

# Use a neutral directory so an existing project's mise config does not interfere.
cd "$tmp"
fetch https://mise.jdx.dev/install.sh "$tmp/mise-install.sh"
MISE_INSTALL_PATH="$HOME/.local/bin/mise" sh "$tmp/mise-install.sh"
# Resolve versions from official upstreams, not the distro or a cached version list.
fetch https://nodejs.org/dist/index.json "$tmp/node-index.json"
fetch 'https://go.dev/dl/?mode=json' "$tmp/go-index.json"
if [[ $install_python == 1 ]]; then
  fetch https://www.python.org/downloads/source/ "$tmp/python-source.html"
fi
/usr/bin/python3 - "$tmp" "$install_python" > "$tmp/upstream-versions" <<'PYVERSIONS'
import json
import pathlib
import re
import sys
root = pathlib.Path(sys.argv[1])
def newest(versions):
    if not versions:
        raise SystemExit("No stable release found in upstream metadata.")
    return max(versions, key=lambda v: tuple(map(int, v.split("."))))
nodes = json.loads((root / "node-index.json").read_text())
gos = json.loads((root / "go-index.json").read_text())
node = newest([v["version"][1:] for v in nodes
               if re.fullmatch(r"v\d+\.\d+\.\d+", v["version"])])
go = newest([v["version"][2:] for v in gos if v.get("stable")
             and re.fullmatch(r"go\d+\.\d+(?:\.\d+)?", v["version"])])
python_version = "-"
if sys.argv[2] == "1":
    python = re.search(r"Latest Python 3 Release - Python (3\.\d+\.\d+)\s*<",
                       (root / "python-source.html").read_text())
    if not python:
        raise SystemExit("python.org layout changed; cannot determine latest stable Python.")
    python_version = python.group(1)
print(node, go, python_version)
PYVERSIONS
read -r node_version go_version python_version < "$tmp/upstream-versions"
printf 'Official stable releases: Node %s, Go %s\n' "$node_version" "$go_version"
mise use --global "node@$node_version" "go@$go_version"
if [[ $install_python == 1 ]]; then
  printf 'Official stable Python: %s\n' "$python_version"
  # python-build uses python.org sources instead of standalone builds/mirrors.
  # Limit compilation to 2 jobs by default to avoid exhausting memory.
  build_jobs="${PYTHON_BUILD_JOBS:-2}"
  [[ $build_jobs =~ ^[1-9][0-9]*$ ]] || { echo 'PYTHON_BUILD_JOBS must be a positive integer.' >&2; exit 1; }
  MISE_PYTHON_COMPILE=true PYTHON_BUILD_SKIP_MIRROR=1 MAKE_OPTS="-j$build_jobs" \
    mise use --global "python@$python_version"
fi
mise reshim
node --version
npm --version
go version
python3 --version
if [[ $install_python == 1 ]]; then
  python3 -c 'import ssl, sqlite3, bz2, lzma, ctypes, readline, zlib, tkinter; import compression.zstd'
fi
python3 -m pip --version
# TypeScript's official stable npm tag; no nightly/next releases.
npm install --global --registry=https://registry.npmjs.org \
  --allow-scripts=tree-sitter-cli typescript@latest tree-sitter-cli

if ! command -v rustup >/dev/null; then
  fetch https://sh.rustup.rs "$tmp/rustup-install.sh"
  sh "$tmp/rustup-install.sh" -y --no-modify-path --profile minimal --default-toolchain stable
fi
rustup toolchain install stable --profile minimal
rustup update stable
rustup default stable
rustup component add --toolchain stable rust-analyzer rustfmt clippy

# Install the official stable Neovim release in the user's home, not /usr/bin.
fetch "https://github.com/neovim/neovim/releases/download/stable/nvim-linux-$arch.tar.gz" "$tmp/nvim.tar.gz"
tar -xzf "$tmp/nvim.tar.gz" -C "$tmp"
"$tmp/nvim-linux-$arch/bin/nvim" --version
backup "$HOME/.local/opt/nvim"
backup "$HOME/.local/bin/nvim"
mv "$tmp/nvim-linux-$arch" "$HOME/.local/opt/nvim"
ln -s "$HOME/.local/opt/nvim/bin/nvim" "$HOME/.local/bin/nvim"
hash -r

# Fetch the starter before moving the existing configuration.
git clone --depth 1 https://github.com/LazyVim/starter.git "$tmp/starter"
for base in "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"; do
  mkdir -p "$base"
  backup "$base/nvim"
done
mkdir -p "$XDG_CONFIG_HOME/nvim"
git -C "$tmp/starter" archive HEAD | tar -x -C "$XDG_CONFIG_HOME/nvim"

# Explicit imports avoid depending on the version of lazyvim.json's schema.
python3 - "$XDG_CONFIG_HOME/nvim/lua/config/lazy.lua" <<'PY'
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()
needle = '    { "LazyVim/LazyVim", import = "lazyvim.plugins" },'
extras = ["lang.rust", "lang.go", "lang.python", "lang.typescript",
          "formatting.prettier", "linting.eslint"]
if text.count(needle) != 1:
    raise SystemExit("Starter layout changed; cannot safely add language extras.")
imports = "\n".join('    { import = "lazyvim.plugins.extras.' + name + '" },'
                    for name in extras)
path.write_text(text.replace(needle, needle + "\n" + imports))
PY
cat >> "$XDG_CONFIG_HOME/nvim/lua/config/options.lua" <<'LUA'

vim.g.lazyvim_python_lsp = "basedpyright"
vim.g.autoformat = true
LUA
cat > "$XDG_CONFIG_HOME/nvim/lua/plugins/python-format.lua" <<'LUA'
return {
  {
    "stevearc/conform.nvim",
    opts = {
      formatters_by_ft = {
        python = { "ruff_organize_imports", "ruff_format" },
      },
    },
  },
}
LUA

cat > "$XDG_CONFIG_HOME/nvim/lua/config/git_repos.lua" <<'GITREPOSLUA'
-- Local multi-repository dashboard. Only an explicit refresh may contact remotes.
local M = {}
local uv = vim.uv or vim.loop
local state = { rows = {}, cache = {}, generation = 0, warnings = {}, lines = {} }
local ns = vim.api.nvim_create_namespace("git-repos-dashboard")
local excluded = { [".git"] = true, node_modules = true, [".venv"] = true,
  venv = true, target = true, vendor = true, dist = true, build = true, [".cache"] = true }

local function clean(text)
  return tostring(text or ""):gsub("(https?://)[^/%s]+@", "%1<redacted>@"):gsub("[%c]", " ")
end

local function config_path()
  return vim.fn.stdpath("config") .. "/git-repos.json"
end

function M.load_config()
  local opts = { roots = { "~/work", "~/projects" }, max_depth = 4, max_repos = 100, max_dirs = 10000 }
  if uv.fs_stat(config_path()) then
    local ok, value = pcall(function()
      return vim.json.decode(table.concat(vim.fn.readfile(config_path()), "\n"))
    end)
    if not ok or type(value) ~= "table" then
      return nil, "Invalid JSON: " .. config_path()
    end
    opts = vim.tbl_extend("force", opts, value)
  end
  if type(opts.roots) ~= "table" or not vim.islist(opts.roots) or #opts.roots == 0 then
    return nil, "roots must be a non-empty JSON array of absolute paths or ~/paths"
  end
  for _, root in ipairs(opts.roots) do
    if type(root) ~= "string" or not (root:match("^/") or root == "~" or root:match("^~/")) then
      return nil, "Each root must be an absolute path or start with ~/"
    end
  end
  for key, bounds in pairs({ max_depth = { 0, 20 }, max_repos = { 1, 1000 }, max_dirs = { 1, 100000 } }) do
    local value = opts[key]
    if type(value) ~= "number" or value % 1 ~= 0 or value < bounds[1] or value > bounds[2] then
      return nil, key .. " must be an integer in " .. bounds[1] .. ".." .. bounds[2]
    end
  end
  return opts
end

-- Bounded, scheduled traversal. Follow explicit root symlinks, never child symlinks.
function M.discover(opts, callback)
  local queue, seen, repos, warnings = {}, {}, {}, {}
  for _, root in ipairs(opts.roots) do
    local path = root:gsub("^~", function() return vim.env.HOME end)
    path = uv.fs_realpath(path)
    if path and (uv.fs_stat(path) or {}).type == "directory" then
      queue[#queue + 1] = { path, 0 }
    else
      warnings[#warnings + 1] = "Root not found or inaccessible: " .. clean(root)
    end
  end
  local pos, visited = 1, 0
  local function finish()
    table.sort(repos)
    callback(repos, warnings)
  end
  local function step()
    if opts.cancelled and opts.cancelled() then return end
    for _ = 1, 25 do
      local item = queue[pos]
      if not item then finish(); return end
      pos = pos + 1
      local path, depth = item[1], item[2]
      if not seen[path] then
        seen[path], visited = true, visited + 1
        if visited > opts.max_dirs then
          warnings[#warnings + 1] = "Directory limit reached; results are incomplete"
          finish(); return
        end
        local marker = uv.fs_stat(path .. "/.git")
        if marker and (marker.type == "directory" or marker.type == "file") then
          repos[#repos + 1] = path
          if #repos >= opts.max_repos then
            warnings[#warnings + 1] = "Repository limit reached; results may be incomplete"
            finish(); return
          end
        end
        if depth < opts.max_depth then
          local handle = uv.fs_scandir(path)
          if not handle then
            warnings[#warnings + 1] = "Cannot read directory: " .. clean(path)
          else
            while true do
              local name, kind = uv.fs_scandir_next(handle)
              if not name then break end
              if kind == "directory" and not excluded[name] then
                queue[#queue + 1] = { path .. "/" .. name, depth + 1 }
              end
            end
          end
        end
      end
    end
    vim.schedule(step)
  end
  vim.schedule(step)
end

function M.parse_status(output)
  local row = { staged = 0, unstaged = 0, untracked = 0, conflicts = 0 }
  for line in output:gmatch("[^\n]+") do
    if line:match("^# branch.head ") then row.branch = line:sub(15)
    elseif line:match("^# branch.oid ") then row.unborn = line:sub(14) == "(initial)"
    elseif line:match("^# branch.ab ") then
      local a, b = line:match("%+(%d+) %-(%d+)")
      row.ahead, row.behind = tonumber(a), tonumber(b)
    elseif line:match("^[12] ") then
      local xy, sub = line:match("^[12] (%S+) (%S+)")
      if xy:sub(1, 1) ~= "." then row.staged = row.staged + 1 end
      if xy:sub(2, 2) ~= "." or (sub:sub(1, 1) == "S" and sub:sub(2) ~= "...") then
        row.unstaged = row.unstaged + 1
      end
    elseif line:match("^u ") then row.conflicts = row.conflicts + 1
    elseif line:match("^%? ") then row.untracked = row.untracked + 1 end
  end
  row.dirty = row.staged + row.unstaged + row.untracked + row.conflicts > 0
  return row
end

local function signature(row)
  return table.concat({ row.branch or "", row.remote or "", row.upstream_ref or "", row.remote_ref or "", row.remote_identity or "" }, "\t")
end

-- Argv arrays, no shell interpolation. Fetch uses batch SSH and existing SSH config/agent.
local function git(path, args, opts, callback, fetching)
  if opts.cancelled and opts.cancelled() then return end
  local argv = { "git", "--no-optional-locks", "-c", "core.fsmonitor=false", "-c", "core.hooksPath=/dev/null", "-C", path }
  vim.list_extend(argv, args)
  local env = vim.fn.environ()
  -- An editor started by Git can inherit another repository's index/worktree.
  -- Keep global credentials/config, but remove repository-local environment.
  for _, name in ipairs({ "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_CONFIG", "GIT_CONFIG_PARAMETERS",
    "GIT_CONFIG_COUNT", "GIT_OBJECT_DIRECTORY", "GIT_DIR", "GIT_WORK_TREE", "GIT_IMPLICIT_WORK_TREE",
    "GIT_GRAFT_FILE", "GIT_INDEX_FILE", "GIT_NO_REPLACE_OBJECTS", "GIT_REPLACE_REF_BASE", "GIT_PREFIX",
    "GIT_INTERNAL_SUPER_PREFIX", "GIT_SHALLOW_FILE", "GIT_COMMON_DIR", "GIT_NAMESPACE" }) do
    env[name] = nil
  end
  env = vim.tbl_extend("force", env, { LC_ALL = "C", GIT_TERMINAL_PROMPT = "0", GIT_ASKPASS = "/bin/false",
    SSH_ASKPASS = "/bin/false", GCM_INTERACTIVE = "never" })
  if fetching then env.GIT_SSH_COMMAND = "ssh -oBatchMode=yes -oStrictHostKeyChecking=yes -oConnectTimeout=10" end
  local ok, job = pcall(vim.system, argv, {
    text = true, env = env, clear_env = true, timeout = fetching and (opts.fetch_timeout or 30000) or 10000,
  }, vim.schedule_wrap(function(result)
    if not opts.cancelled or not opts.cancelled() then callback(result) end
  end))
  if not ok then
    callback({ code = 1, stderr = clean(job), stdout = "" })
  elseif opts.on_job then
    opts.on_job(job)
  end
end

local function read_repo(path, opts, callback)
  git(path, { "status", "--porcelain=v2", "--branch", "--untracked-files=all", "--ignore-submodules=none" }, opts, function(result)
    if result.code ~= 0 then
      callback({ path = path, error = clean(result.stderr):sub(1, 240) }); return
    end
    local row = M.parse_status(result.stdout)
    row.path = path
    if not row.branch then row.error = "Cannot determine current branch"; callback(row); return end
    if row.branch == "(detached)" or row.unborn then callback(row); return end
    local format = "%(upstream)%09%(upstream:short)%09%(upstream:remotename)%09%(upstream:remoteref)%09%(push)%09%(push:remotename)"
    git(path, { "for-each-ref", "--format=" .. format, "refs/heads/" .. row.branch }, opts, function(refs)
      if refs.code ~= 0 then row.error = clean(refs.stderr):sub(1, 240)
      else
        local fields = vim.split((refs.stdout or ""):gsub("\n$", ""), "\t", { plain = true })
        row.upstream_ref, row.upstream, row.remote, row.remote_ref, row.push_ref, row.push_remote = unpack(fields)
      end
      if row.error or not row.remote or row.remote == "" or row.remote == "." or row.push_remote ~= row.remote then
        callback(row); return
      end
      -- A single remote can fetch from one server and push to another. Do not
      -- treat its fetched snapshot as evidence about a different push URL.
      git(path, { "remote", "get-url", "--", row.remote }, opts, function(fetch_url)
        row.remote_identity = fetch_url.code == 0 and vim.fn.sha256(fetch_url.stdout) or "unknown"
        git(path, { "remote", "get-url", "--push", "--all", "--", row.remote }, opts, function(push_urls)
          row.push_url_unknown = fetch_url.code ~= 0 or push_urls.code ~= 0
          row.push_url_diff = not row.push_url_unknown and vim.trim(fetch_url.stdout) ~= vim.trim(push_urls.stdout)
          callback(row)
        end)
      end)
    end)
  end)
end

-- Cache records attest only to the named branch/upstream and to the recorded time.
function M.inspect(path, opts, callback)
  opts = opts or {}
  local cache = opts.cache or {}
  local function deliver(row)
    local saved = cache[path]
    if saved and saved.signature == signature(row) then row.fetch = saved end
    callback(row)
  end
  read_repo(path, opts, function(row)
    if not opts.fetch or row.error or not row.remote or row.remote == "" or row.remote == "." then
      deliver(row); return
    end
    if not (row.upstream_ref or ""):match("^refs/remotes/") or not (row.remote_ref or ""):match("^refs/heads/") then
      row.notice = "Unsupported fetch mapping; fetch manually"
      deliver(row); return
    end
    -- Fetch only this upstream branch into its remote-tracking ref. No prune, push,
    -- pull, reset, checkout, submodule updates or working-tree changes.
    local spec = "+" .. row.remote_ref .. ":" .. row.upstream_ref
    git(path, { "-c", "credential.interactive=false", "fetch", "--no-tags", "--no-recurse-submodules",
      "--no-write-fetch-head", "--", row.remote, spec }, opts, function(result)
      cache[path] = { signature = signature(row), at = os.date("%Y-%m-%d %H:%M:%S"),
        error = result.code ~= 0 and (clean(result.stderr):sub(1, 240) .. " (exit " .. result.code .. ")") or nil }
      read_repo(path, opts, function(updated)
        if signature(updated) ~= signature(row) then updated.notice = "Branch/upstream changed; fetch again" end
        deliver(updated)
      end)
    end, true)
  end)
end

function M.verdict(row)
  if row.error then return "ERROR" end
  if row.fetch and row.fetch.error then return "FETCH ERROR" end
  if row.notice then return row.notice end
  if row.unborn then return "NO COMMITS" end
  if row.branch == "(detached)" then return "DETACHED HEAD" end
  if not row.remote or row.remote == "" then return "NO UPSTREAM" end
  if row.remote == "." then return "LOCAL UPSTREAM (not a server)" end
  if row.ahead == nil or row.behind == nil then return "UPSTREAM MISSING" end
  if row.push_url_unknown then return "PUSH URL UNKNOWN" end
  if row.push_url_diff then return "PUSH URL != FETCH URL" end
  if not row.push_ref or row.push_ref == "" then return "PUSH TARGET UNKNOWN" end
  if row.push_ref ~= row.upstream_ref or row.push_remote ~= row.remote then return "PUSH TARGET != UPSTREAM" end
  if row.ahead > 0 and row.behind > 0 then return "DIVERGED" end
  if row.ahead > 0 then return "UNPUSHED" end
  if row.behind > 0 then return "BEHIND" end
  return "SYNC (upstream snapshot)"
end

local function render()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end
  local lines = {
    "GIT REPOSITORIES - working trees and CURRENT branches only",
    "r: local refresh | f: fetch upstreams | e: edit roots | Enter: Fugitive | q: close/cancel",
    "S=staged W=unstaged ?=untracked !=conflicts. Ignored files are excluded.",
    "Ahead/behind use LOCAL remote-tracking refs, not live server data. Fetch is explicit.",
    (state.progress or "Ready") .. " | scan depth: " .. (state.depth or "?") .. " | " .. config_path(),
    "",
  }
  state.lines = {}
  local highlights = {}
  for _, warning in ipairs(state.warnings) do lines[#lines + 1] = "WARNING: " .. warning end
  if #state.rows == 0 then lines[#lines + 1] = "No repositories yet. Press e to configure roots." end
  for _, row in ipairs(state.rows) do
    local verdict = M.verdict(row)
    local work = row.error and "UNKNOWN" or (row.conflicts > 0 and "CONFLICT" or (row.dirty and "DIRTY" or "CLEAN"))
    local first = #lines + 1
    lines[first] = "[" .. work .. " | " .. verdict .. "] " .. clean(row.path)
    lines[first + 1] = string.format("  %s -> %s | S:%s W:%s ?:%s !:%s | ahead:%s behind:%s",
      clean(row.branch or "?"), clean(row.upstream or "-"), row.staged or "?", row.unstaged or "?",
      row.untracked or "?", row.conflicts or "?", row.ahead or "?", row.behind or "?")
    local remote = "CACHED ONLY; no successful fetch recorded in this session"
    if row.fetch then
      remote = (row.fetch.error and "FETCH FAILED " or "Fetched ") .. row.fetch.at
      if row.fetch.error then remote = remote .. ": " .. row.fetch.error end
    end
    lines[first + 2] = "  " .. (row.error or remote)
    for i = first, first + 2 do state.lines[i] = row end
    local group = (row.error or (row.fetch and row.fetch.error)) and "DiagnosticError" or "DiagnosticWarn"
    if work == "CLEAN" and verdict == "SYNC (upstream snapshot)" then
      group = row.fetch and "DiagnosticOk" or "Comment"
    end
    highlights[#highlights + 1] = { first - 1, group }
  end
  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
  for _, hl in ipairs(highlights) do
    vim.api.nvim_buf_set_extmark(state.buf, ns, hl[1], 0, { end_col = #lines[hl[1] + 1], hl_group = hl[2] })
  end
end

local function cancel()
  state.generation = state.generation + 1
  if state.job then pcall(function() state.job:kill(15) end); state.job = nil end
end

function M.refresh(fetch)
  cancel()
  local generation = state.generation
  state.rows, state.warnings = {}, {}
  local opts, err = M.load_config()
  if not opts then state.progress = "ERROR: " .. err; render(); return end
  state.depth, state.progress = opts.max_depth, "Scanning..."
  opts.cancelled = function() return state.generation ~= generation end
  opts.on_job = function(job) state.job = job end
  opts.cache, opts.fetch = state.cache, fetch == true
  render()
  M.discover(opts, function(paths, warnings)
    state.warnings = warnings
    local i = 0
    local function next_repo()
      if opts.cancelled() then return end
      i = i + 1
      if not paths[i] then
        state.job, state.progress = nil, "Ready: " .. #state.rows .. " repositories (bounded scan)"
        render(); return
      end
      state.progress = (fetch and "Fetching/reading " or "Reading locally ") .. i .. "/" .. #paths
      render()
      M.inspect(paths[i], opts, function(row)
        state.rows[#state.rows + 1] = row
        render()
        vim.schedule(next_repo)
      end)
    end
    next_repo()
  end)
end

function M.edit_roots()
  if not uv.fs_stat(config_path()) then
    vim.fn.mkdir(vim.fn.stdpath("config"), "p")
    vim.fn.writefile({ '{', '  "roots": ["~/work", "~/projects"],', '  "max_depth": 4,',
      '  "max_repos": 100,', '  "max_dirs": 10000', '}' }, config_path())
  end
  vim.cmd("tabedit " .. vim.fn.fnameescape(config_path()))
end

function M.open(fetch)
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    state.buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(state.buf, "git-repos://dashboard")
    vim.bo[state.buf].buftype, vim.bo[state.buf].bufhidden = "nofile", "hide"
    vim.bo[state.buf].swapfile, vim.bo[state.buf].filetype = false, "gitrepos"
    local key_opts = { buffer = state.buf, silent = true }
    vim.keymap.set("n", "r", function() M.refresh(false) end, key_opts)
    vim.keymap.set("n", "f", function() M.refresh(true) end, key_opts)
    vim.keymap.set("n", "e", M.edit_roots, key_opts)
    vim.keymap.set("n", "q", function() vim.api.nvim_buf_delete(state.buf, { force = true }) end, key_opts)
    vim.keymap.set("n", "<CR>", function()
      local row = state.lines[vim.api.nvim_win_get_cursor(0)[1]]
      if not row then return end
      vim.cmd("tabnew")
      vim.cmd("tcd " .. vim.fn.fnameescape(row.path))
      vim.cmd("Git")
    end, key_opts)
    vim.api.nvim_create_autocmd("BufWipeout", { buffer = state.buf, once = true, callback = cancel })
  end
  local wins = vim.fn.win_findbuf(state.buf)
  if #wins > 0 then vim.api.nvim_set_current_win(wins[1])
  else vim.cmd("tabnew"); vim.api.nvim_win_set_buf(0, state.buf) end
  vim.wo.wrap, vim.wo.number, vim.wo.relativenumber = false, false, false
  M.refresh(fetch)
end

function M.setup()
  vim.api.nvim_create_user_command("GitRepos", function() M.open(false) end, { desc = "Local repository overview", force = true })
  vim.api.nvim_create_user_command("GitReposFetch", function() M.open(true) end, { desc = "Fetch configured upstreams and refresh overview", force = true })
  vim.api.nvim_create_user_command("GitReposRoots", M.edit_roots, { desc = "Edit repository search roots", force = true })
end

return M
GITREPOSLUA

cat > "$XDG_CONFIG_HOME/nvim/lua/plugins/git.lua" <<'GITLUA'
return {
  {
    "tpope/vim-fugitive",
    init = function()
      require("config.git_repos").setup()
    end,
    cmd = { "Git", "G", "Gdiffsplit", "Gvdiffsplit", "Gedit", "Gread", "Gwrite", "Gclog" },
    keys = {
      { "<leader>gFs", "<cmd>Git<cr>", desc = "Git Status (Fugitive)" },
      { "<leader>gFc", "<cmd>Git commit<cr>", desc = "Git Commit (Fugitive)" },
      { "<leader>gFd", "<cmd>Gvdiffsplit<cr>", desc = "Git Diff vs Index (Fugitive)" },
      { "<leader>gFb", "<cmd>Git blame<cr>", desc = "Git Blame (Fugitive)" },
      { "<leader>gFl", "<cmd>Git log --oneline --decorate -50<cr>", desc = "Git Log (Fugitive)" },
      { "<leader>gFa", "<cmd>GitRepos<cr>", desc = "Repository Overview (Local)" },
      { "<leader>gFu", "<cmd>GitReposFetch<cr>", desc = "Fetch Upstreams and Refresh Overview" },
      { "<leader>gFr", "<cmd>GitReposRoots<cr>", desc = "Configure Repository Folders" },
    },
  },
  {
    "lewis6991/gitsigns.nvim",
    opts = {
      signcolumn = true,
      numhl = false,
      linehl = false,
      current_line_blame = false,
      current_line_blame_opts = { delay = 400, virt_text_pos = "eol" },
    },
    keys = {
      { "<leader>gFt", "<cmd>Gitsigns toggle_current_line_blame<cr>", desc = "Toggle Git Line Blame" },
    },
  },
  {
    "folke/which-key.nvim",
    optional = true,
    opts = { spec = { { "<leader>gF", group = "Fugitive" } } },
  },
}
GITLUA

cat > "$XDG_CONFIG_HOME/nvim/lua/plugins/install-guard.lua" <<'LUA'
-- Only the installer's bootstrap uses this flag; normal sessions are unchanged.
if vim.env.LAZYVIM_INSTALLING ~= "1" then
  return {}
end
return {
  {
    "mason-org/mason.nvim",
    opts = function(_, opts)
      opts.ensure_installed = {}
    end,
  },
}
LUA
LAZYVIM_INSTALLING=1 nvim --headless '+Lazy! sync' +qa
# Run Mason alone to avoid races with LazyVim's automatic installers.
# MasonInstall waits for completion in headless mode and fails on install errors.
nvim --headless -u NONE \
  -c 'lua vim.opt.rtp:prepend(vim.env.XDG_DATA_HOME .. "/nvim/lazy/mason.nvim"); require("mason").setup()' \
  -c 'MasonInstall gopls goimports gofumpt golangci-lint basedpyright ruff vtsls prettier eslint-lsp codelldb stylua shfmt lua-language-server json-lsp' \
  -c 'lua local r = require("mason-registry"); for _, p in ipairs({"gopls", "goimports", "gofumpt", "golangci-lint", "basedpyright", "ruff", "vtsls", "prettier", "eslint-lsp", "codelldb", "stylua", "shfmt", "lua-language-server", "json-lsp"}) do if not r.get_package(p):is_installed() then vim.cmd("cquit 1") end end' \
  +qa

# Basic executable and startup checks. Project-specific checks are still needed.
rustc --version
cargo --version
python3 --version
tsc --version
cc --version
c++ --version
rust-analyzer --version
cargo fmt --version
cargo clippy --version
gopls version
ruff --version
basedpyright --version
prettier --version
tree-sitter --version
nvim --headless \
  '+lua if not pcall(require, "lazyvim") or not pcall(require, "config.git_repos") then vim.cmd("cquit 1") end' \
  '+lua for _, cmd in ipairs({"GitRepos", "GitReposFetch", "GitReposRoots"}) do if vim.fn.exists(":" .. cmd) ~= 2 then vim.cmd("cquit 1") end end' \
  +qa
printf '\nInstallation complete. Open a NEW terminal, then run: nvim\n'
printf 'Inside Neovim: :Mason  and  :checkhealth\n'
printf 'Git overview: :GitReposRoots (set folders), :GitRepos (local), :GitReposFetch (refresh upstreams).\n'
printf 'Backups have suffix: .bak-%s\n' "$stamp"
printf 'Python projects need a .venv; TS projects need their own dependencies/config.\n'
