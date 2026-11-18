local function wait_for(label, condition)
  assert(vim.wait(15000, condition, 100), "Timeout: " .. label)
end

local function run()
  local file = vim.api.nvim_buf_get_name(0)
  for _, suffix in ipairs({ "s", "c", "d", "b", "l", "t" }) do
    assert(vim.fn.maparg(" gF" .. suffix, "n") ~= "", "Missing Git keymap: " .. suffix)
  end
  wait_for("Gitsigns hunk", function()
    local ok, gs = pcall(require, "gitsigns")
    return ok and #(gs.get_hunks() or {}) > 0
  end)
  local config = require("gitsigns.config").config
  assert(config.signcolumn and not config.current_line_blame)
  assert(config.current_line_blame_opts.delay == 400)
  vim.cmd("Gitsigns toggle_current_line_blame")
  assert(require("gitsigns.config").config.current_line_blame)
  vim.cmd("Gitsigns toggle_current_line_blame")

  vim.cmd("Git")
  wait_for("Fugitive status", function()
    return vim.bo.filetype == "fugitive"
      and table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"):find("tracked.txt", 1, true)
  end)
  vim.cmd("Git add -- tracked.txt")
  wait_for("Fugitive stage", function()
    return vim.fn.system({ "git", "diff", "--cached", "--name-only" }):find("tracked.txt", 1, true) ~= nil
  end)
  vim.cmd("Git commit -m smoke-change")
  wait_for("Fugitive commit", function()
    return vim.trim(vim.fn.system({ "git", "rev-list", "--count", "HEAD" })) == "2"
  end)

  vim.cmd("edit " .. vim.fn.fnameescape(file))
  vim.cmd("Git blame")
  wait_for("Fugitive blame", function()
    return vim.bo.filetype == "fugitiveblame"
  end)
  -- Blame and diff scratch windows can set winfixbuf. Use a fresh tab.
  vim.cmd("tabnew " .. vim.fn.fnameescape(file))
  vim.fn.writefile({ "another change" }, file)
  vim.cmd("edit!")
  vim.cmd("Gvdiffsplit")
  wait_for("Fugitive diff", function()
    local count = 0
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if vim.wo[win].diff then
        count = count + 1
      end
    end
    return count >= 2
  end)
  vim.cmd("tabnew " .. vim.fn.fnameescape(file))
  vim.cmd("Git log --oneline --decorate -50")
  wait_for("Fugitive log", function()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(buf) then
        local lines = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
        if lines:find("smoke-change", 1, true) and lines:find("initial", 1, true) then
          return true
        end
      end
    end
    return false
  end)
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
  vim.api.nvim_err_writeln(err)
  vim.cmd("cquit 1")
else
  print("PASS: Fugitive and Gitsigns integration")
  vim.cmd("qa!")
end
