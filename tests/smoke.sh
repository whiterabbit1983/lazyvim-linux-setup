#!/usr/bin/env bash
# Run after install.sh, as the same non-root Linux user.
set -Eeuo pipefail
# shellcheck disable=SC1091
source "$HOME/.config/lazyvim-linux-setup/env.sh"
LAZYVIM_SMOKE_LUA="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lsp.lua"
export LAZYVIM_SMOKE_LUA
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
cd "$tmp"

cargo new --vcs none rust-smoke
(cd rust-smoke && cargo check && cargo fmt --check && cargo clippy && \
  EXPECTED_LSP=rust-analyzer nvim --headless src/main.rs '+lua dofile(vim.env.LAZYVIM_SMOKE_LUA)')

mkdir go-smoke
cd go-smoke
go mod init example.com/smoke
printf 'package main\nfunc main() {}\n' > main.go
go build ./...
EXPECTED_LSP=gopls nvim --headless main.go '+lua dofile(vim.env.LAZYVIM_SMOKE_LUA)'
cd "$tmp"

mkdir python-smoke
cd python-smoke
printf '[project]\nname = "smoke"\nversion = "0.0.1"\n' > pyproject.toml
printf 'answer: int = 42\nprint(answer)\n' > main.py
python3 -c 'import ssl, sqlite3, bz2, lzma, ctypes, readline, zlib'
if [[ ${1:-} == --with-python ]]; then
  python3 -c 'import tkinter; import compression.zstd'
fi
python3 -m venv .venv
.venv/bin/python -m pip --version
.venv/bin/python -m py_compile main.py
ruff check main.py
EXPECTED_LSP=basedpyright,ruff nvim --headless main.py '+lua dofile(vim.env.LAZYVIM_SMOKE_LUA)'
cd "$tmp"

mkdir ts-smoke
cd ts-smoke
npm init -y
npm install --save-dev typescript
printf '{"compilerOptions":{"strict":true,"outDir":"dist"},"include":["main.ts"]}\n' > tsconfig.json
printf 'const answer: number = 42;\nconsole.log(answer);\n' > main.ts
npx tsc
node dist/main.js
EXPECTED_LSP=vtsls nvim --headless main.ts '+lua dofile(vim.env.LAZYVIM_SMOKE_LUA)'
cd "$tmp"

printf 'int main(void) { return 0; }\n' > main.c
cc main.c -o c-smoke
./c-smoke
printf 'int main() { return 0; }\n' > main.cpp
c++ main.cpp -o cpp-smoke
./cpp-smoke
bash "$(dirname -- "$LAZYVIM_SMOKE_LUA")/git-smoke.sh"
bash "$(dirname -- "$LAZYVIM_SMOKE_LUA")/repos-smoke.sh"
printf '\nPASS: Rust, Go, Python, TypeScript, C/C++, Git and the expected LSP clients.\n'
