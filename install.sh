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

cat > "$XDG_CONFIG_HOME/nvim/lua/plugins/git.lua" <<'GITLUA'
return {
  {
    "tpope/vim-fugitive",
    cmd = { "Git", "G", "Gdiffsplit", "Gvdiffsplit", "Gedit", "Gread", "Gwrite", "Gclog" },
    keys = {
      { "<leader>gFs", "<cmd>Git<cr>", desc = "Git Status (Fugitive)" },
      { "<leader>gFc", "<cmd>Git commit<cr>", desc = "Git Commit (Fugitive)" },
      { "<leader>gFd", "<cmd>Gvdiffsplit<cr>", desc = "Git Diff vs Index (Fugitive)" },
      { "<leader>gFb", "<cmd>Git blame<cr>", desc = "Git Blame (Fugitive)" },
      { "<leader>gFl", "<cmd>Git log --oneline --decorate -50<cr>", desc = "Git Log (Fugitive)" },
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
nvim --headless '+lua if not pcall(require, "lazyvim") then vim.cmd("cquit 1") end' +qa
printf '\nInstallation complete. Open a NEW terminal, then run: nvim\n'
printf 'Inside Neovim: :Mason  and  :checkhealth\n'
printf 'Backups have suffix: .bak-%s\n' "$stamp"
printf 'Python projects need a .venv; TS projects need their own dependencies/config.\n'
