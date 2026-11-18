local expected = vim.split(assert(vim.env.EXPECTED_LSP), ",", { plain = true })
local function ready()
  local clients = vim.lsp.get_clients({ bufnr = 0 })
  for _, name in ipairs(expected) do
    local found = false
    for _, client in ipairs(clients) do
      if client.name == name and client.initialized then
        found = true
      end
    end
    if not found then
      return false
    end
  end
  return true
end

if not vim.wait(90000, ready, 100) then
  vim.api.nvim_err_writeln("LSP timeout: expected " .. table.concat(expected, ", "))
  vim.api.nvim_err_writeln(vim.inspect(vim.lsp.get_clients({ bufnr = 0 })))
  vim.cmd("cquit 1")
else
  print("PASS: initialized LSP clients: " .. table.concat(expected, ", "))
  vim.cmd("qa!")
end
