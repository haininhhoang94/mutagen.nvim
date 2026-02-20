local M = {}

local function run_sync_command(action, name, wait_timeout)
  if not name or name == "" then
    return false
  end

  local handle = vim.system({ "mutagen", "sync", action, name }, {}, function() end)
  if wait_timeout then
    handle:wait(wait_timeout)
  end
  return true
end

function M.parse_sync_list(lines)
  local name = nil
  local sessions = {}
  local url_beta = nil
  local url_alpha = nil
  local con_beta = nil
  local con_alpha = nil
  local ident = nil
  local is_beta = false

  for _, line in ipairs(lines) do
    local n = line:match("^Name: (.*)")
    if n then
      name = n
    end
    local i = line:find("^Identifier: (.*)")
    if i then
      ident = i
    end
    local b = line:find("^Beta:")
    if b then
      is_beta = true
    end
    local u = line:match("URL: (.*)")
    if u then
      if is_beta then
        url_beta = u
      else
        url_alpha = u
      end
    end
    local c = line:match("Connected: (.*)")
    if c then
      if is_beta then
        con_beta = c
      else
        con_alpha = c
      end
    end
    local s = line:match("^Status: (.*)")
    if s then
      table.insert(sessions, {
        name = name,
        identifier = ident,
        status = s,
        alpha = {
          url = url_alpha,
          connected = con_alpha,
        },
        beta = {
          url = url_beta,
          connected = con_beta,
        }
      })
      is_beta = false
    end
  end
  return sessions
end

function M.sync_list()
  local lines = vim.fn.systemlist("mutagen sync list")
  return M.parse_sync_list(lines)
end

function M.sync_connected(sync)
  return sync['beta']['connected'] == "Yes" and sync['alpha']['connected'] == "Yes"
end

function M.setup(opts)
  _ = opts
  vim.api.nvim_create_autocmd({ "BufWritePost" }, {
    callback = function(opt)
      _ = opt
      local path = vim.fn.expand('%:p')
      local sync_done = function(res)
        local lines = vim.split(res.stdout, "\n")
        local sessions = M.parse_sync_list(lines)
        for _, session in ipairs(sessions) do
          if vim.startswith(path, session.alpha.url) or vim.startswith(path, session.beta.url) then
            M.sync_flush(session.name)
          end
        end
      end
      vim.system({ "mutagen", "sync", "list" }, {}, sync_done)
    end,
  })
end

function M.sync_flush(name, wait_timeout)
  return run_sync_command("flush", name, wait_timeout)
end

function M.sync_terminate(name, wait_timeout)
  return run_sync_command("terminate", name, wait_timeout)
end

function M.sync_find()
  local sessions = M.sync_list()
  local path = vim.fn.getcwd()
  for _, session in ipairs(sessions) do
    if vim.startswith(path, session.alpha.url) or vim.startswith(path, session.beta.url) then
      return session
    end
  end
  return nil
end


return M
