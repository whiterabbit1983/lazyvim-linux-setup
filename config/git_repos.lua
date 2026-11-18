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
