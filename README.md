# LazyVim для Rust, Go, Python и TypeScript

Один установочный скрипт для **Linux Mint, Debian/Ubuntu, Fedora и Arch Linux** (x86_64 / aarch64, glibc). Linux Mint определяется явно по `ID=linuxmint` и использует APT; LMDE также направляется в APT-ветку. Настройка окружения рассчитана на Bash и Zsh. Для Alpine/musl, NixOS и Fish скрипт не предназначен.

## Запуск

Нужны интернет, `sudo` и несколько гигабайт свободного места. Запускайте **от обычного пользователя**, не через `sudo bash`.

```bash
git clone https://github.com/whiterabbit1983/lazyvim-linux-setup.git
cd lazyvim-linux-setup
bash install.sh
```

Репозиторий приватный: для клонирования нужна авторизация GitHub. Можно скачать `install.sh` через сайт или использовать `gh repo clone whiterabbit1983/lazyvim-linux-setup`.

**Если Git ещё нет**, откройте `install.sh` на GitHub после входа в аккаунт и скачайте файл через кнопку скачивания исходника. Затем выполните `bash install.sh` в каталоге скачивания. Клонировать репозиторий для этого не нужно: скрипт сам установит Git, если команда `git` отсутствует.

По умолчанию скрипт **не скачивает и не собирает новый Python**: используется имеющийся интерпретатор. Системные пакеты Python, pip и venv устанавливаются/проверяются как зависимости; это не установка нового upstream-релиза. Ruff, BasedPyright и Python-дополнение LazyVim включены всегда.

Для запуска без подтверждения:

```bash
bash install.sh --yes
```

Последний стабильный Python из официальных исходников устанавливается **только по флагу**:

```bash
bash install.sh --with-python
# Или без подтверждения:
bash install.sh --yes --with-python
```

Сборка Python занимает несколько минут или дольше. По умолчанию используются 2 параллельных задания; можно изменить их число: `PYTHON_BUILD_JOBS=4 bash install.sh --with-python`. Установленный таким образом Python становится пользовательским стандартным интерпретатором через mise, но не подменяет `/usr/bin/python3`.

Без `--with-python` настройка Python в mise не изменяется. Если вы уже используете pyenv/mise/venv, скрипт не переключает вас принудительно на системный Python.

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
| Git | CLI Git при отсутствии, `vim-fugitive`, настроенный `gitsigns.nvim` |
| Rust | `rustup`, `rustc`, `cargo`, `rust-analyzer`, `rustfmt`, Clippy |
| Go | Go, `gofmt`, `gopls`, `goimports`, `gofumpt`, `golangci-lint` |
| Python | Имеющийся Python, pip/venv, `basedpyright`, `ruff`; новый Python — только с `--with-python` |
| TypeScript / JavaScript | Последний стабильный Node.js Current, npm, TypeScript (`tsc`), `vtsls`, Prettier, ESLint language server |
| Сборка зависимостей | C/C++ compiler, make, OpenSSL headers, pkg-config |
| Neovim-плагины | Tree-sitter CLI, `stylua`, `shfmt`, Lua/JSON language servers |
| Rust debugger | `codelldb` (его запрашивает Rust-дополнение LazyVim) |
| Поиск и буфер обмена | `ripgrep`, `fd`, `xclip`; `wl-clipboard` в Wayland-сессии |

### Откуда берутся версии и файлы

- **Rust:** последний `stable` через официальный rustup; явно выполняется `rustup update stable`.
- **Go:** последний стабильный релиз из `https://go.dev/dl/?mode=json`; mise устанавливает соответствующую официальную сборку Go.
- **Node.js:** последний стабильный релиз из `https://nodejs.org/dist/index.json`; mise устанавливает официальную сборку. Это **Current, не обязательно LTS**. Nightly/RC исключаются.
- **Python, только `--with-python`:** версия определяется по `https://www.python.org/downloads/source/`. Mise использует python-build с `MISE_PYTHON_COMPILE=true` и `PYTHON_BUILD_SKIP_MIRROR=1`: новые установки собираются из исходников python.org, а не из сторонних standalone-сборок. Если выбранная версия уже установлена в mise, она переиспользуется.
- **TypeScript:** официальный пакет `typescript@latest` из `https://registry.npmjs.org`; не `next` и не nightly.
- **C/C++ и библиотеки сборки:** пакеты Linux-дистрибутива, как и остальные системные зависимости.

При изменении формата upstream-данных скрипт останавливается с ошибкой вместо молчаливого выбора старой версии. Последние версии не зафиксированы и со временем меняются; совместимость конкретных проектов с новым major-релизом не гарантируется.

Остальные языковые инструменты устанавливаются через **Mason**. `sudo npm` и установка Python-пакетов в системное окружение не используются. TypeScript-компилятор доступен глобально для пользователя; проекты должны закреплять собственную версию TypeScript в зависимостях.

Включены дополнения:

- `lang.rust`
- `lang.go`
- `lang.python`
- `lang.typescript`
- `formatting.prettier`
- `linting.eslint`

Включено форматирование при сохранении. Python использует Ruff для форматирования и организации импортов, BasedPyright — для типов и навигации.

## Git в Neovim

Установщик проверяет `command -v git` **до клонирования плагинов**. Если Git отсутствует, устанавливает его через APT (Mint/Debian/Ubuntu), DNF или Pacman. Существующая команда Git переиспользуется; отдельная установка пакета Git пропускается. Общее обновление Arch всё равно может обновить уже установленные пакеты.

Конфигурация создаётся в `${XDG_CONFIG_HOME:-~/.config}/nvim/lua/plugins/git.lua`:

- **vim-fugitive:** статус, staging, коммиты, история, diff и blame внутри Neovim. Отдельная программа `lazygit` не требуется.
- **gitsigns.nvim:** уже входит в LazyVim; включены отметки изменений в колонке знаков. Постоянный blame изначально выключен, задержка его показа после включения — 400 мс.
- **which-key:** группа `Fugitive` с подсказками клавиш. Стандартные Git-клавиши LazyVim не переназначаются.

### Добавить Git в уже установленный LazyVim без переустановки

Конфигурация доступна отдельно: [`config/git.lua`](config/git.lua) и модуль [`config/git_repos.lua`](config/git_repos.lua). Нужны **оба файла**. На Linux, из каталога этого репозитория:

```bash
git pull
nvim_config="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
mkdir -p "$nvim_config/lua/plugins" "$nvim_config/lua/config"
cp --backup=numbered config/git.lua "$nvim_config/lua/plugins/git.lua"
cp --backup=numbered config/git_repos.lua "$nvim_config/lua/config/git_repos.lua"
nvim
```

В Neovim выполните `:Lazy sync`, дождитесь установки и перезапустите редактор. Команда `cp` сохраняет прежние Lua-файлы с нумерованными суффиксами, если они существуют. Ваш `git-repos.json` не перезаписывается. Другие настройки и языковые инструменты не переустанавливаются. Полный `install.sh` для такого обновления запускать не нужно.

### Клавиши

Откройте файл внутри Git-репозитория. `<leader>` в этой конфигурации — **пробел**, `F` — заглавная:

| Клавиши | Действие |
|---|---|
| `Space g F s` | Git status: `:Git` |
| `Space g F c` | Начать коммит: `:Git commit` |
| `Space g F d` | Diff текущего отслеживаемого файла с индексом: `:Gvdiffsplit` |
| `Space g F b` | Blame текущего файла: `:Git blame` |
| `Space g F l` | Последние 50 коммитов |
| `Space g F t` | Включить/выключить blame текущей строки |
| `Space g F a` | Общий список репозиториев, без обращения к серверам |
| `Space g F u` | Обновить upstream через fetch и перечитать список |
| `Space g F r` | Настроить папки поиска репозиториев |

В окне `:Git`: `s` добавляет файл/фрагмент в индекс, `u` убирает из индекса, `cc` начинает коммит. Сохраните сообщение коммита и закройте его буфер, чтобы завершить коммит. Справка: `:help fugitive`.

Стандартные команды Gitsigns также доступны: `]h` / `[h` — следующий/предыдущий фрагмент изменений, `Space g h p` — предпросмотр, `Space g h s` — добавить фрагмент в индекс.

Установщик **не задаёт имя, email, remote, токены или SSH-ключи**, не создаёт коммиты в ваших проектах и не выполняет push. Перед первым коммитом настройте автора самостоятельно, например только для текущего репозитория:

```bash
git config user.name "Ваше имя"
git config user.email "your-email@example.com"
```

## Обзор нескольких репозиториев

Модуль проверяет **рабочие файлы и текущую ветку каждого репозитория**. Он не проверяет все локальные ветки, теги или состояние CI на GitHub.

### Один раз укажите свои папки

Выполните `:GitReposRoots` (`Space g F r`). Откроется `${XDG_CONFIG_HOME:-~/.config}/nvim/git-repos.json`. Если файла ещё нет, модуль создаст его с такими значениями:

```json
{
  "roots": ["~/work", "~/projects"],
  "max_depth": 4,
  "max_repos": 100,
  "max_dirs": 10000
}
```

Замените `roots` своими абсолютными путями или путями `~/…`, сохраните файл. Можно указать как родительские папки, так и отдельные репозитории. Настройка хранится на вашей Linux-машине и не загружается в GitHub.

Затем откройте **`:GitRepos`** (`Space g F a`). Для каждого репозитория показаны:

- `CLEAN`, `DIRTY` или `CONFLICT` — состояние файлов.
- `S` — файлы в индексе; `W` — изменения вне индекса; `?` — неотслеживаемые файлы; `!` — конфликты. Один файл может учитываться и в S, и в W. Игнорируемые файлы не считаются незакоммиченными.
- Имя текущей ветки и её upstream, например `main -> origin/main`.
- `ahead` — коммиты текущей ветки, которых нет в известном upstream; `behind` — коммиты upstream, которых нет локально.
- Состояние сравнения: `UNPUSHED`, `BEHIND`, `DIVERGED`, `SYNC (upstream snapshot)` и предупреждения.
- Время последнего fetch в текущем сеансе Neovim либо явная отметка `CACHED ONLY`/ошибка fetch.

**`CLEAN` не означает «всё отправлено».** Это только отсутствие незакоммиченных изменений. Для обычной настройки с одинаковым upstream и адресом push отсутствие неотправленных коммитов показывает `ahead:0`. `behind:0` дополнительно означает, что в известном upstream нет новых коммитов.

### Обновление данных с сервера — только вручную

В списке:

- **`r`** — перечитать локальные данные, без сети.
- **`f`** — выполнить fetch upstream текущей ветки для каждого найденного репозитория и обновить список. То же действие: `:GitReposFetch` / `Space g F u`.
- **`Enter`** — открыть выбранный репозиторий в Fugitive в новой вкладке. Рабочий каталог меняется только для этой вкладки.
- **`e`** — открыть настройки папок.
- **`q`** — закрыть список и отменить оставшуюся работу.

При открытии списка fetch **не выполняется автоматически**. Операции Git идут последовательно и асинхронно; Neovim остаётся доступен. Локальная команда ограничена 10 секундами, один fetch — 30 секундами. Повторное обновление отменяет предыдущую незавершённую операцию.

Fetch обновляет только remote-tracking ref upstream текущей ветки. Модуль **не выполняет commit, push, pull, merge, reset, checkout или prune**, не изменяет рабочие файлы и не обновляет подмодули. Вызовы dashboard отключают Git hooks и fsmonitor hook. Если fetch уже обновил remote-tracking ref до отмены, это обновление не откатывается.

Даже после успешного fetch статус является снимком **на указанное время**, а не постоянной гарантией состояния сервера. После изменения сервера выполните fetch ещё раз. Метки времени не сохраняются между сеансами: после перезапуска данные вновь отмечаются как локальные.

### Когда нельзя сделать вывод «коммиты отправлены»

- `NO UPSTREAM` — ветка ни за чем не отслеживает. Настройте upstream самостоятельно, например `git branch --set-upstream-to=origin/main main`, **если это нужная существующая ветка**. Установщик не выбирает remote за вас и не делает push для настройки upstream.
- `NO COMMITS`, `DETACHED HEAD`, `LOCAL UPSTREAM` — нет подходящей текущей ветки с серверным upstream.
- `UPSTREAM MISSING` — отсутствует нужный remote-tracking ref.
- `FETCH ERROR` — нет сети, доступа, серверной ветки либо произошла другая ошибка. Старые счётчики могут отображаться, но модуль не помечает результат как успешно проверенный.
- `PUSH TARGET UNKNOWN`, `PUSH TARGET != UPSTREAM` или `PUSH URL != FETCH URL` — направление push не определено либо отличается от проверенного upstream. Это учитывает, например, отдельный fork для push или отдельный `pushurl`. Модуль не утверждает, что коммиты есть на другом сервере. Даже разные URL одного физического репозитория дают консервативное предупреждение.
- Нестандартные refspec, в которых fetch изменяет не `refs/remotes/...`, требуют ручного fetch. Dashboard не меняет локальные ветки ради проверки.

Доступ к серверам должен быть настроен отдельно. HTTPS использует существующий credential helper; интерактивный ввод паролей отключён. SSH использует `ssh -oBatchMode=yes -oStrictHostKeyChecking=yes -oConnectTimeout=10`, `~/.ssh/config` и агент. Пользовательский `core.sshCommand`/`GIT_SSH_COMMAND` в этом batch-fetch заменяется указанной командой: перенесите нужные ключи/параметры в SSH config либо выполните fetch вручную. Новые host keys не принимаются автоматически, токены и ключи установщик не создаёт.

### Границы поиска

Рабочие копии, связанные worktree и подмодули распознаются по файлу/каталогу `.git`. Bare-репозитории не показываются. Дубликаты корней устраняются; вложенные символьные ссылки не обходятся, но ссылку можно явно указать в `roots`.

Поиск ограничен глубиной и числом каталогов/репозиториев. При достижении лимита появляется предупреждение о неполных результатах. По умолчанию пропускаются `.git`, `node_modules`, `.venv`, `venv`, `target`, `vendor`, `dist`, `build`, `.cache`. Если репозиторий находится внутри пропускаемой папки, укажите его корень отдельно. Недоступные корни и некорректный JSON показываются как ошибки, а не как «все репозитории чистые».

## Изменения и резервные копии

Скрипт:

1. Устанавливает системные пакеты. **На Arch команда `pacman -Syu` также обновляет всю систему** — частичные обновления Arch не поддерживаются.
2. Выбирает последние стабильные Go и Node.js Current как глобальные версии mise для пользователя, Rust stable — как стандартную toolchain rustup. Только с `--with-python` также выбирает новый Python в mise. Уже настроенные менеджеры версий могут конфликтовать по `PATH`.
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
git --version
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
- Go / Node.js: `mise use --global go@latest node@latest`.
- Системный Python: обычное обновление пакетов дистрибутива. Для отдельно установленного через mise Python: `MISE_PYTHON_COMPILE=true PYTHON_BUILD_SKIP_MIRROR=1 MAKE_OPTS=-j2 mise use --global python@latest` (нужны библиотеки сборки).
- TypeScript / Tree-sitter CLI: `npm install --global --registry=https://registry.npmjs.org --allow-scripts=tree-sitter-cli typescript@latest tree-sitter-cli` (после смены Node.js глобальные npm-пакеты могут потребовать переустановки).

## Результат тестирования и известные ограничения

Обзор репозиториев проверен в Ubuntu 24.04 с Neovim 0.12.6: **106 автоматических проверок** с временными локальными Git-серверами, включая dirty/ahead/behind/diverged, ошибки fetch, разные направления push, worktree и подмодули. В настоящем LazyVim проверены команды, 9 клавиш, список репозиториев и переход из него в Fugitive. Прошли ShellCheck и 10 Python unit-тестов. Полный установщик языковых окружений после добавления обзора заново не запускался; реальные SSH/HTTPS-доступы пользователя не проверялись.

В версии `9f7b048` отдельно проверялись установка отсутствующего Git, повторное использование существующего, Fugitive status/stage/commit/blame/diff/log и Gitsigns.

В предыдущей версии `dde9c8f` оба режима — по умолчанию и `--with-python` — прошли полную установку и smoke-тесты в `linuxmintd/mint22-amd64` с пакетными репозиториями Mint 22 / Ubuntu Noble. Это контейнер для сборки пакетов на Ubuntu-базе, **не полноценная настольная установка Mint**. Определение `ID=linuxmint` дополнительно покрыто unit-тестом. Сборка проектов и подключение основных LSP прошли успешно; системный Python после установки отдельного Python не подменён.

Первоначальная версия также проверена в Ubuntu 24.04 x86_64. Mint 21, полноценная LMDE, Fedora, Arch и aarch64 не проверялись; подробности — в [TESTING.md](TESTING.md).

**Важно:** npm-аудит сообщил о ReDoS в цепочке зависимостей установленного ESLint language server. Подробности, границы проверки и остальные результаты находятся в [TESTING.md](TESTING.md). Скрипт не выполняет небезопасное автоматическое исправление через `npm audit fix --force`.

## Проверки разработки

```bash
bash -n install.sh
bash -n tests/smoke.sh
bash -n tests/git-smoke.sh
shellcheck install.sh tests/smoke.sh tests/git-smoke.sh
python3 tests/upstream_versions.py
```

После установки можно выполнить:

```bash
bash tests/smoke.sh
# Если установщик был запущен с --with-python:
bash tests/smoke.sh --with-python
```

Тест создаёт временные проекты, проверяет Rust/Go/TypeScript/C/C++ сборку, Python venv и компиляцию байткода, а также инициализацию языковых серверов Rust, Go, Python и TypeScript в Neovim. TS-проверка скачивает локальную зависимость `typescript` из npm. Временные проекты удаляются после проверки.

Он также запускает `tests/git-smoke.sh`, который можно выполнить отдельно. Git-тест создаёт временный локальный репозиторий, проверяет Fugitive status/stage/commit/blame/diff/log, клавиши, Gitsigns и переход из списка репозиториев в Fugitive. Папка поиска подменяется только в памяти; пользовательский `git-repos.json` не меняется. Имя и email задаются **только внутри тестового репозитория**; push не выполняется.

Отдельный `bash tests/repos-smoke.sh` проверяет модуль обзора без LazyVim — нужен только Git и современный Neovim с `vim.system`. Этот тест также включён в общий smoke-тест и GitHub Actions. Он создаёт временные bare-репозитории и делает fetch/push **исключительно между этими локальными каталогами**, чтобы проверить разные состояния веток. К внешним Git-серверам не обращается; настройки Neovim и Git изолированы во временном окружении. После проверки оно удаляется.

Полный установочный тест необходимо запускать в отдельной Linux-машине или одноразовом контейнере, от непривилегированного пользователя с `sudo`. Не запускайте установщик на рабочей машине только ради тестирования.
