#!/usr/bin/env bash
# LazyVim + Rust, Go, Python, TypeScript. Run as your normal Linux user.
set -Eeuo pipefail
trap 'printf "\nERROR at line %s. Installation stopped; backups were not deleted.\n" "$LINENO" >&2' ERR

usage() {
  printf 'Usage: bash install.sh [--yes]\nSupported: Debian/Ubuntu, Fedora, Arch; x86_64/aarch64; Bash/Zsh.\n'
}
case "${1:-}" in
  --help|-h) usage; exit 0 ;;
  --yes) assume_yes=1 ;;
  "") assume_yes=0 ;;
  *) usage >&2; exit 2 ;;
esac
[[ $# -le 1 ]] || { usage >&2; exit 2; }
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
  *' debian '*|*' ubuntu '*) distro=debian ;;
  *' fedora '*) distro=fedora ;;
  *' arch '*) distro=arch ;;
  *) echo "Unsupported distribution: $ID" >&2; exit 1 ;;
esac
printf '%s\n' \
  'This installs system dependencies and downloads software from official upstreams.' \
  'It sets user defaults to Rust stable, Go latest and Node.js LTS.' \
  'Existing Neovim configuration/data/cache/state will be MOVED to .bak-* paths.' \
  'It adds one environment-file source line to ~/.bashrc and ~/.zshrc.' \
  'Re-running creates a fresh LazyVim configuration, not an in-place update.' \
  'On Arch, pacman -Syu also upgrades the entire system.'
if [[ $assume_yes == 0 ]]; then
  read -r -p 'Continue? [y/N] ' answer
  [[ $answer == y || $answer == Y ]] || exit 0
fi
command -v sudo >/dev/null || { echo 'Install sudo and grant this user access first.' >&2; exit 1; }
sudo -v

case "$distro" in
  debian)
    sudo apt-get update
    sudo apt-get install -y git curl ca-certificates unzip tar gzip xz-utils \
      build-essential pkg-config libssl-dev python3 python3-venv python3-pip \
      ripgrep fd-find xclip
    ;;
  fedora)
    sudo dnf install -y git curl ca-certificates unzip tar gzip xz \
      gcc gcc-c++ make pkgconf-pkg-config openssl-devel python3 python3-pip \
      ripgrep fd-find xclip
    ;;
  arch)
    # A full upgrade is necessary on Arch: partial upgrades are unsupported.
    sudo pacman -Syu --needed --noconfirm git curl ca-certificates unzip tar gzip xz \
      base-devel openssl python python-pip ripgrep fd xclip
    ;;
esac
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
mise use --global node@lts go@latest
mise reshim
node --version
npm --version
go version
# TypeScript compiler + the CLI required by newer nvim-treesitter versions.
npm install --global --allow-scripts=tree-sitter-cli typescript tree-sitter-cli

if ! command -v rustup >/dev/null; then
  fetch https://sh.rustup.rs "$tmp/rustup-install.sh"
  sh "$tmp/rustup-install.sh" -y --no-modify-path --profile minimal --default-toolchain stable
fi
rustup toolchain install stable --profile minimal
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
