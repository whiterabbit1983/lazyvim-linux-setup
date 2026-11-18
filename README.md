# LazyVim для Rust, Go, Python и TypeScript

Один установочный скрипт для **Debian/Ubuntu, Fedora и Arch Linux** (x86_64 / aarch64, glibc). Настройка окружения рассчитана на Bash и Zsh. Для Alpine/musl, NixOS и Fish скрипт не предназначен.

## Запуск

Нужны интернет, `sudo` и несколько гигабайт свободного места. Запускайте **от обычного пользователя**, не через `sudo bash`.

```bash
git clone https://github.com/whiterabbit1983/lazyvim-linux-setup.git
cd lazyvim-linux-setup
bash install.sh
```

Репозиторий приватный: для клонирования нужна авторизация GitHub. Можно скачать `install.sh` через сайт или использовать `gh repo clone whiterabbit1983/lazyvim-linux-setup`.

Для запуска без подтверждения:

```bash
bash install.sh --yes
```

После установки **откройте новый терминал** и выполните `nvim`. Для текущего Bash/Zsh можно загрузить пути вручную:

```bash
source ~/.config/lazyvim-linux-setup/env.sh
nvim
```

> Скрипт скачивает и запускает официальные установщики mise и rustup. Прочитайте `install.sh` перед запуском. Версии не зафиксированы: используются актуальные upstream-релизы, поэтому результат со временем меняется.

## Что устанавливается

| Назначение | Инструменты |
|---|---|
| Редактор | Стабильный Neovim, LazyVim starter |
| Rust | `rustup`, `rustc`, `cargo`, `rust-analyzer`, `rustfmt`, Clippy |
| Go | Go, `gofmt`, `gopls`, `goimports`, `gofumpt`, `golangci-lint` |
| Python | Python 3, pip, venv, `basedpyright`, `ruff` |
| TypeScript / JavaScript | Node.js LTS, npm, TypeScript (`tsc`), `vtsls`, Prettier, ESLint language server |
| Сборка зависимостей | C/C++ compiler, make, OpenSSL headers, pkg-config |
| Neovim-плагины | Tree-sitter CLI, `stylua`, `shfmt`, Lua/JSON language servers |
| Rust debugger | `codelldb` (его запрашивает Rust-дополнение LazyVim) |
| Поиск и буфер обмена | `ripgrep`, `fd`, `xclip`; `wl-clipboard` в Wayland-сессии |

Python — интерпретатор, а не отдельный компилятор вроде `rustc`. Скрипт устанавливает Python из репозитория дистрибутива. TypeScript-компилятор устанавливается глобально для пользователя; проекты могут и должны закреплять собственную версию TypeScript.

Node.js и Go устанавливаются через **mise**, Rust — через **rustup**, остальные языковые инструменты — через **Mason**. `sudo npm` и установка Python-пакетов в системное окружение не используются.

Включены дополнения:

- `lang.rust`
- `lang.go`
- `lang.python`
- `lang.typescript`
- `formatting.prettier`
- `linting.eslint`

Включено форматирование при сохранении. Python использует Ruff для форматирования и организации импортов, BasedPyright — для типов и навигации.

## Изменения и резервные копии

Скрипт:

1. Устанавливает системные пакеты. **На Arch команда `pacman -Syu` также обновляет всю систему** — частичные обновления Arch не поддерживаются.
2. Выбирает Go latest и Node.js LTS как глобальные версии mise для пользователя, Rust stable — как стандартную toolchain rustup. Уже настроенные менеджеры версий могут конфликтовать по `PATH`.
3. Устанавливает Neovim в `~/.local/opt/nvim`, ссылку — в `~/.local/bin/nvim`. Системный `/usr/bin/nvim` не меняется, но новая версия получает приоритет в `PATH`.
4. Перемещает старые каталоги Neovim в соседние каталоги с суффиксом `.bak-ДАТА-ВРЕМЯ-PID`:
   - `${XDG_CONFIG_HOME:-~/.config}/nvim`
   - `${XDG_DATA_HOME:-~/.local/share}/nvim`
   - `${XDG_STATE_HOME:-~/.local/state}/nvim`
   - `${XDG_CACHE_HOME:-~/.cache}/nvim`
5. Также сохраняет прежние `~/.local/opt/nvim` и `~/.local/bin/nvim`, если они существуют.
6. Создаёт `~/.config/lazyvim-linux-setup/env.sh` и добавляет строку его загрузки в `~/.bashrc` и `~/.zshrc`. Остальное содержимое этих файлов сохраняется.

**Повторный запуск создаёт свежую конфигурацию и новую резервную копию. Это не команда обновления существующей настройки.** Старые копии автоматически не удаляются. При ошибке скрипт останавливается, но не откатывает уже выполненные установки.

Для восстановления закройте Neovim, переместите новую конфигурацию в отдельный каталог и верните нужные `.bak-*` каталоги на прежние места. Это не отменяет установку системных пакетов и изменение версий mise/rustup.

## Проверка

В терминале:

```bash
nvim --version
rustc --version
cargo --version
rust-analyzer --version
go version
gopls version
python3 --version
basedpyright --version
ruff --version
node --version
npm --version
tsc --version
prettier --version
```

В Neovim:

```vim
:Mason
:checkhealth
:checkhealth vim.lsp
```

Откройте файл внутри проекта перед проверкой LSP. Первое открытие файлов нового языка может запустить установку Tree-sitter-парсеров. Для иконок желательно установить Nerd Font **на машине, где работает терминал**. Шрифт скрипт не устанавливает.

## Что нужно сделать в проектах

Скрипт не изменяет ваши проекты и не создаёт в них конфигурацию линтеров.

### Rust

```bash
cargo new hello-rust
cd hello-rust
cargo check
cargo fmt
cargo clippy
nvim .
```

Если в проекте закреплена другая toolchain, установите компоненты и для неё:

```bash
# Выполнять в каталоге проекта с rust-toolchain.toml:
rustup component add rust-analyzer rustfmt clippy
```

### Go

```bash
mkdir hello-go && cd hello-go
go mod init example.com/hello-go
nvim .
```

В существующем проекте не создавайте новый `go.mod`.

### Python

```bash
cd your-python-project
python3 -m venv .venv
source .venv/bin/activate
# Если проект использует requirements.txt:
python -m pip install -r requirements.txt
nvim .
```

Для выбора окружения в LazyVim можно использовать `:VenvSelect`.

### TypeScript

Для **нового** проекта:

```bash
mkdir hello-ts && cd hello-ts
npm init -y
npm install -D typescript prettier eslint @eslint/js typescript-eslint
npx tsc --init
nvim .
```

Для существующего проекта используйте его менеджер пакетов, lockfile и конфигурацию. Например, `npm ci` для проекта с `package-lock.json`.

ESLint language server не заменяет локальную зависимость `eslint` и файл её конфигурации. Минимальный `eslint.config.mjs` для нового TS-проекта:

```js
import js from "@eslint/js";
import tseslint from "typescript-eslint";

export default [
  js.configs.recommended,
  ...tseslint.configs.recommended,
];
```

## Обновление

- Neovim: отдельно обновить официальный релиз; повторный запуск всего установщика сбросит конфигурацию в резервную копию.
- Плагины: `:Lazy update`.
- Mason-инструменты: `:Mason`, затем обновление выбранных пакетов. `:MasonUpdate` обновляет **реестр**, не сами пакеты.
- Rust: `rustup update stable`.
- Go / Node.js: `mise use --global go@latest node@lts`.
- TypeScript / Tree-sitter CLI: `npm install --global --allow-scripts=tree-sitter-cli typescript tree-sitter-cli` (после смены Node.js глобальные npm-пакеты могут потребовать переустановки).

## Результат тестирования и известные ограничения

Установка и повторный запуск проверены в Ubuntu 24.04 x86_64; сборка тестовых проектов и подключение основных LSP прошли успешно. Fedora, Arch и aarch64 не проверялись.

**Важно:** npm-аудит сообщил о ReDoS в цепочке зависимостей установленного ESLint language server. Подробности, границы проверки и остальные результаты находятся в [TESTING.md](TESTING.md). Скрипт не выполняет небезопасное автоматическое исправление через `npm audit fix --force`.

## Проверки разработки

```bash
bash -n install.sh
bash -n tests/smoke.sh
shellcheck install.sh tests/smoke.sh
```

После установки можно выполнить:

```bash
bash tests/smoke.sh
```

Тест создаёт временные проекты, проверяет Rust/Go/TypeScript/C/C++ сборку, Python venv и компиляцию байткода, а также инициализацию языковых серверов Rust, Go, Python и TypeScript в Neovim. TS-проверка скачивает локальную зависимость `typescript` из npm. Временные проекты удаляются после проверки.

Полный установочный тест необходимо запускать в отдельной Linux-машине или одноразовом контейнере, от непривилегированного пользователя с `sudo`. Не запускайте установщик на рабочей машине только ради тестирования.
