local M = {}

local DEFAULTS = {
  auto_flush_debounce_ms = 400,
  notifications = {
    success = false,
    failure = true,
    recovery = true,
    failure_cooldown_ms = 60000,
    persistent_failure_reminder_ms = 300000,
  },
}

local config = vim.deepcopy(DEFAULTS)
local auto_state = {
  last_auto_flush_at = 0,
  sessions = {},
}

local function now_ms()
  return vim.uv.now()
end

local function get_session_state(session)
  if not auto_state.sessions[session] then
    auto_state.sessions[session] = {
      failing = false,
      last_error = nil,
      last_notify_at = 0,
      last_reminder_at = 0,
      suppressed = 0,
    }
  end
  return auto_state.sessions[session]
end

local function should_notify_failure(state, reason)
  local now = now_ms()
  local same_reason = state.last_error == reason

  if not state.failing then
    state.failing = true
    state.last_error = reason
    state.last_notify_at = now
    state.last_reminder_at = now
    return true
  end

  if not same_reason then
    state.last_error = reason
    state.last_notify_at = now
    state.last_reminder_at = now
    return true
  end

  if now - state.last_notify_at >= config.notifications.failure_cooldown_ms then
    state.last_notify_at = now
    state.last_reminder_at = now
    return true
  end

  if now - state.last_reminder_at >= config.notifications.persistent_failure_reminder_ms then
    state.last_notify_at = now
    state.last_reminder_at = now
    return true
  end

  state.suppressed = state.suppressed + 1
  return false
end

local function notify_result(notify_opts, res)
  if not notify_opts or not notify_opts.enabled then
    return
  end

  local action = notify_opts.action or "sync"
  local session = notify_opts.session or "unknown"
  local reason = (res.stderr and vim.trim(res.stderr) ~= "") and vim.trim(res.stderr)
    or (res.stdout and vim.trim(res.stdout) ~= "" and vim.trim(res.stdout))
    or ("exit code " .. tostring(res.code))

  if not notify_opts.auto then
    if res.code == 0 then
      vim.notify(string.format("[mutagen] %s: %sed", session, action), vim.log.levels.INFO)
      return
    end
    vim.notify(string.format("[mutagen] %s: %s failed: %s", session, action, reason), vim.log.levels.WARN)
    return
  end

  local state = get_session_state(session)

  if res.code == 0 then
    if state.failing and config.notifications.recovery then
      local suffix = state.suppressed > 0 and string.format(" (+%d suppressed)", state.suppressed) or ""
      vim.notify(string.format("[mutagen] %s: recovered%s", session, suffix), vim.log.levels.INFO)
    elseif config.notifications.success then
      vim.notify(string.format("[mutagen] %s: %sed", session, action), vim.log.levels.INFO)
    end
    state.failing = false
    state.last_error = nil
    state.last_notify_at = 0
    state.last_reminder_at = 0
    state.suppressed = 0
    return
  end

  if not config.notifications.failure then
    return
  end

  if should_notify_failure(state, reason) then
    local suffix = state.suppressed > 0 and string.format(" (+%d suppressed)", state.suppressed) or ""
    vim.notify(string.format("[mutagen] %s: %s failed: %s%s", session, action, reason, suffix), vim.log.levels.WARN)
    state.suppressed = 0
  end
end

local function run_sync_command(action, name, wait_timeout, notify_opts)
  if not name or name == "" then
    return false
  end

  local handle = vim.system({ "mutagen", "sync", action, name }, { text = true }, function(res)
    notify_result(notify_opts, res)
  end)
  if wait_timeout then
    handle:wait(wait_timeout)
  end
  return true
end

function M.get_git_root(path)
  if not path or path == "" then
    return nil
  end

  local start = vim.fs.dirname(path)
  if not start or start == "" then
    return nil
  end

  local git_entries = vim.fs.find(".git", { path = start, upward = true, limit = 1, type = "file" })
  if #git_entries == 0 then
    git_entries = vim.fs.find(".git", { path = start, upward = true, limit = 1, type = "directory" })
  end

  if #git_entries == 0 then
    return nil
  end

  return vim.fs.dirname(git_entries[1])
end

function M.has_mutagen_config(root)
  if not root or root == "" then
    return false
  end
  return vim.uv.fs_stat(root .. "/mutagen.yml") ~= nil
end

function M.auto_flush_allowed(path)
  local root = M.get_git_root(path)
  if not root then
    return false
  end
  return M.has_mutagen_config(root)
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
  config = vim.tbl_deep_extend("force", vim.deepcopy(DEFAULTS), opts or {})
  vim.api.nvim_create_autocmd({ "BufWritePost" }, {
    callback = function(opt)
      _ = opt
      local path = vim.fn.expand('%:p')
      if not M.auto_flush_allowed(path) then
        return
      end

      local now = now_ms()
      if now - auto_state.last_auto_flush_at < config.auto_flush_debounce_ms then
        return
      end
      auto_state.last_auto_flush_at = now

      local sync_done = function(res)
        local lines = vim.split(res.stdout, "\n")
        local sessions = M.parse_sync_list(lines)
        for _, session in ipairs(sessions) do
          if vim.startswith(path, session.alpha.url) or vim.startswith(path, session.beta.url) then
            M.sync_flush(session.name, nil, {
              enabled = true,
              action = "flush",
              session = session.name,
              auto = true,
            })
          end
        end
      end
      vim.system({ "mutagen", "sync", "list" }, {}, sync_done)
    end,
  })
end

function M.sync_flush(name, wait_timeout, notify_opts)
  return run_sync_command("flush", name, wait_timeout, notify_opts)
end

function M.sync_terminate(name, wait_timeout, notify_opts)
  return run_sync_command("terminate", name, wait_timeout, notify_opts)
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
