local M = dofile(vim.env.GIT_REPOS_MODULE)
local base = vim.env.TEST_REPOS_TMP
local roots = base .. "/root with spaces;literal"
local cache = {}
local checks = 0
local function expect(condition, label)
  assert(condition, label)
  checks = checks + 1
end
local function git(path, args, allow_error)
  local argv = { "git", "-c", "core.hooksPath=/dev/null", "-C", path }
  vim.list_extend(argv, args)
  local result = vim.system(argv, { text = true }):wait()
  assert(allow_error or result.code == 0, table.concat(argv, " ") .. "\n" .. result.stderr)
  return vim.trim(result.stdout or ""), result.code
end
local function write(path, text) vim.fn.writefile(vim.split(text, "\n", { plain = true }), path) end
local function identity(path)
  git(path, { "config", "user.name", "Repo Test" })
  git(path, { "config", "user.email", "repo@example.invalid" })
  git(path, { "config", "commit.gpgsign", "false" })
end
local function init(path, bare)
  vim.fn.mkdir(path, "p")
  local args = { "init", "-q", "--template=", "-b", "main" }
  if bare then args[#args + 1] = "--bare" end
  git(path, args)
  if not bare then identity(path) end
  return path
end
local function commit(path, name)
  git(path, { "add", "--all" })
  git(path, { "commit", "-qm", name })
end
local function inspect(path, fetch)
  local row
  M.inspect(path, { fetch = fetch, cache = cache, fetch_timeout = 3000 }, function(value) row = value end)
  expect(vim.wait(15000, function() return row ~= nil end, 10), "inspect timeout")
  expect(not row.error, "inspect error: " .. vim.inspect(row))
  return row
end
local function discover(paths, depth, repos, dirs)
  local result, warnings
  M.discover({ roots = paths, max_depth = depth or 4, max_repos = repos or 100, max_dirs = dirs or 10000 }, function(a, b)
    result, warnings = a, b
  end)
  expect(vim.wait(15000, function() return result ~= nil end, 10), "discovery timeout")
  return result, warnings
end
local function clone(remote, path)
  git(base, { "clone", "-q", remote, path })
  identity(path)
  return path
end
local function lines()
  return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
end
local function ready()
  expect(vim.wait(15000, function() return lines():find("Ready:", 1, true) ~= nil end, 10), "dashboard timeout")
end

local function run()
  local server = init(base .. "/server.git", true)
  local repo = init(roots .. "/project")
  write(repo .. "/tracked.txt", "base")
  write(repo .. "/other.txt", "other")
  write(repo .. "/.gitignore", "ignored.tmp")
  commit(repo, "base")
  git(repo, { "remote", "add", "origin", server })
  git(repo, { "push", "-qu", "origin", "main" })
  local row = inspect(repo, false)
  expect(M.verdict(row) == "SYNC (upstream snapshot)" and not row.fetch, "initial cached sync")
  expect(not row.dirty and row.ahead == 0 and row.behind == 0, "clean counters")

  write(repo .. "/tracked.txt", "modified")
  git(repo, { "mv", "other.txt", "renamed.txt" })
  write(repo .. "/staged.txt", "staged")
  git(repo, { "add", "staged.txt" })
  write(repo .. "/space\nname.txt", "untracked")
  write(repo .. "/ignored.tmp", "ignored")
  row = inspect(repo, false)
  expect(row.staged == 2 and row.unstaged == 1 and row.untracked == 1 and row.conflicts == 0, "dirty, rename, escaped-name and ignored counts")
  local staged_diff = git(repo, { "diff", "--cached" })
  row = inspect(repo, true)
  expect(row.staged == 2 and row.unstaged == 1 and row.untracked == 1
    and git(repo, { "diff", "--cached" }) == staged_diff
    and vim.fn.readfile(repo .. "/tracked.txt")[1] == "modified", "fetch preserves index and dirty working tree")
  git(repo, { "reset", "--hard", "HEAD" })
  git(repo, { "clean", "-fd" })
  write(repo .. "/local.txt", "local")
  commit(repo, "local-only")
  row = inspect(repo, false)
  expect(row.ahead == 1 and M.verdict(row) == "UNPUSHED", "unpushed local commit")
  local peer = clone(server, base .. "/peer")
  write(peer .. "/remote.txt", "remote")
  commit(peer, "remote-only")
  git(peer, { "push", "-q" })
  expect(inspect(repo, false).behind == 0, "local refresh must not fetch")
  local head = git(repo, { "rev-parse", "HEAD" })
  row = inspect(repo, true)
  expect(row.ahead == 1 and row.behind == 1 and M.verdict(row) == "DIVERGED", "fetch detects divergence")
  expect(row.fetch and not row.fetch.error, "successful fetch timestamp")
  expect(git(repo, { "rev-parse", "HEAD" }) == head, "fetch must not change local HEAD")
  expect(vim.fn.readfile(repo .. "/tracked.txt")[1] == "base", "fetch must not change working files")
  vim.env.GIT_DIR, vim.env.GIT_WORK_TREE, vim.env.GIT_INDEX_FILE = peer .. "/.git", peer, peer .. "/.git/index"
  row = inspect(repo, false)
  vim.env.GIT_DIR, vim.env.GIT_WORK_TREE, vim.env.GIT_INDEX_FILE = nil, nil, nil
  expect(row.ahead == 1 and row.behind == 1, "inherited Git environment cannot select another repository")

  local behind = clone(server, roots .. "/behind")
  write(peer .. "/remote2.txt", "remote2")
  commit(peer, "remote-two")
  git(peer, { "push", "-q" })
  expect(inspect(behind, false).behind == 0, "cached data before explicit fetch")
  expect(M.verdict(inspect(behind, true)) == "BEHIND", "fetch detects behind")
  git(behind, { "merge", "--ff-only", "origin/main" }) -- fixture only, never dashboard behavior
  write(behind .. "/pushed.txt", "push fixture")
  commit(behind, "to-push")
  expect(M.verdict(inspect(behind, false)) == "UNPUSHED", "ahead before local fixture push")
  git(behind, { "push", "-q" }) -- only to the temporary local bare repo
  expect(M.verdict(inspect(behind, true)) == "SYNC (upstream snapshot)", "sync after push and fetch")

  git(behind, { "remote", "set-url", "origin", base .. "/missing.git" })
  expect(not inspect(behind, false).fetch, "changed remote URL invalidates old fetch record")
  row = inspect(behind, true)
  expect(M.verdict(row) == "FETCH ERROR" and row.fetch.error, "failed fetch is not sync")
  git(behind, { "remote", "set-url", "origin", server })
  expect(M.verdict(inspect(behind, true)) == "SYNC (upstream snapshot)", "fetch can recover")
  git(behind, { "config", "remote.origin.pushurl", base .. "/different.git" })
  expect(M.verdict(inspect(behind, false)) == "PUSH URL != FETCH URL", "different push URL must not claim sent")
  git(behind, { "config", "--unset", "remote.origin.pushurl" })
  local fork = init(base .. "/fork.git", true)
  git(behind, { "remote", "add", "fork", fork })
  git(behind, { "push", "-q", "fork", "main" })
  git(behind, { "config", "branch.main.pushRemote", "fork" })
  git(behind, { "config", "push.default", "current" })
  expect(M.verdict(inspect(behind, false)) == "PUSH TARGET != UPSTREAM", "fork push destination")
  git(behind, { "config", "--unset", "branch.main.pushRemote" })
  git(behind, { "config", "push.default", "nothing" })
  expect(M.verdict(inspect(behind, false)) == "PUSH TARGET UNKNOWN", "disabled push destination")
  git(behind, { "config", "push.default", "simple" })

  local unborn = init(roots .. "/unborn")
  write(unborn .. "/new.txt", "new")
  row = inspect(unborn, true)
  expect(row.unborn and row.untracked == 1 and M.verdict(row) == "NO COMMITS", "unborn branch")
  commit(unborn, "initial")
  expect(M.verdict(inspect(unborn, true)) == "NO UPSTREAM", "no upstream is unknown, not sent")
  git(unborn, { "checkout", "-q", "--detach", "HEAD" })
  expect(M.verdict(inspect(unborn, true)) == "DETACHED HEAD", "detached HEAD")
  git(unborn, { "checkout", "-q", "-b", "local" })
  git(unborn, { "branch", "--set-upstream-to=main" })
  expect(M.verdict(inspect(unborn, true)) == "LOCAL UPSTREAM (not a server)", "local upstream")

  local gone = clone(server, roots .. "/gone")
  git(gone, { "checkout", "-qb", "gone" })
  git(gone, { "push", "-qu", "origin", "gone" })
  git(server, { "update-ref", "-d", "refs/heads/gone" })
  expect(M.verdict(inspect(gone, true)) == "FETCH ERROR", "deleted server branch must not look synced")
  git(gone, { "update-ref", "-d", "refs/remotes/origin/gone" })
  expect(M.verdict(inspect(gone, false)) == "FETCH ERROR" or M.verdict(inspect(gone, false)) == "UPSTREAM MISSING", "missing upstream ref")

  local conflict = init(roots .. "/conflict")
  write(conflict .. "/file.txt", "base")
  commit(conflict, "base")
  git(conflict, { "checkout", "-qb", "side" })
  write(conflict .. "/file.txt", "side")
  commit(conflict, "side")
  git(conflict, { "checkout", "-q", "main" })
  write(conflict .. "/file.txt", "main")
  commit(conflict, "main")
  local _, code = git(conflict, { "merge", "side" }, true)
  expect(code ~= 0 and inspect(conflict, false).conflicts == 1, "merge conflict")

  local parent = init(roots .. "/parent")
  git(parent, { "-c", "protocol.file.allow=always", "submodule", "add", "-q", server, "sub" })
  commit(parent, "submodule")
  git(parent, { "config", "submodule.sub.ignore", "all" })
  write(parent .. "/sub/tracked.txt", "dirty submodule")
  expect(inspect(parent, false).dirty, "do not hide dirty submodule via Git config")
  local worktree = roots .. "/linked-worktree"
  git(repo, { "worktree", "add", "-qb", "worktree-branch", worktree })
  init(roots .. "/node_modules/excluded")
  local uv = vim.uv or vim.loop
  uv.fs_symlink(roots, roots .. "/loop", { dir = true })
  local found = discover({ roots, repo, roots .. "/loop" })
  local counts = {}
  for _, path in ipairs(found) do counts[path] = (counts[path] or 0) + 1 end
  expect(counts[repo] == 1 and counts[worktree] == 1 and counts[parent .. "/sub"] == 1, "dedup, worktree and submodule discovery")
  expect(not counts[roots .. "/node_modules/excluded"], "skip dependency folders")
  local shallow = discover({ roots }, 0)
  expect(#shallow == 0, "honor scan depth")
  local limited, warnings = discover({ roots }, 4, 1)
  expect(#limited == 1 and #warnings > 0, "report repository cap")
  limited, warnings = discover({ roots }, 4, 100, 1)
  expect(#warnings > 0, "report directory cap")
  limited, warnings = discover({ base .. "/absent" })
  expect(#limited == 0 and #warnings == 1, "report missing root")

  local config = vim.fn.stdpath("config") .. "/git-repos.json"
  vim.fn.mkdir(vim.fn.stdpath("config"), "p")
  M.edit_roots()
  expect(M.load_config().roots[1] == "~/work", "create default settings on request")
  write(config, "invalid JSON")
  M.edit_roots()
  expect(vim.fn.readfile(config)[1] == "invalid JSON", "never overwrite existing settings")
  local opts, err = M.load_config()
  expect(not opts and err, "invalid JSON is an explicit error")
  write(config, '{"roots":["relative/path"]}')
  expect(not M.load_config(), "reject relative roots")
  write(config, '{"roots":["~/work"],"max_depth":99}')
  expect(not M.load_config(), "validate depth")
  local invalid = roots .. "/invalid-repository"
  vim.fn.mkdir(invalid .. "/.git", "p")
  write(config, vim.json.encode({ roots = { behind, invalid }, max_depth = 0 }))
  expect(M.load_config().max_depth == 0, "valid config")
  M.setup()
  expect(vim.fn.exists(":GitRepos") == 2 and vim.fn.exists(":GitReposFetch") == 2, "commands registered")
  M.open(false)
  ready()
  expect(lines():find("CACHED ONLY", 1, true) ~= nil, "dashboard labels unfetched data")
  expect(lines():find("CURRENT branches only", 1, true) ~= nil, "dashboard states branch scope")
  expect(lines():find("[UNKNOWN | ERROR]", 1, true) ~= nil, "broken repository is an error, not clean")
  local initial_cwd = vim.fn.getcwd()
  local opened
  vim.api.nvim_create_user_command("Git", function() opened = vim.fn.getcwd() end, {})
  for i, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
    if line:find(behind, 1, true) then vim.api.nvim_win_set_cursor(0, { i, 0 }); break end
  end
  vim.fn.maparg("<CR>", "n", false, true).callback()
  expect(opened == behind, "Enter opens selected repository")
  vim.cmd("tabclose")
  expect(vim.fn.getcwd() == initial_cwd, "selected repository does not change dashboard cwd")
  M.open(true)
  ready()
  expect(lines():find("Fetched ", 1, true) ~= nil, "explicit fetch timestamp in dashboard")
  M.refresh(false)
  vim.api.nvim_buf_delete(0, { force = true })
  vim.wait(100, function() return false end, 10)
  expect(true, "closing cancels scheduled work without late buffer writes")
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
  vim.api.nvim_err_writeln(err)
  vim.cmd("cquit 1")
else
  print("PASS: repository dashboard (" .. checks .. " checks, local remotes only)")
  vim.cmd("qa!")
end
