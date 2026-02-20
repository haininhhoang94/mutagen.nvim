local mutagen = require("mutagen")

local M = {}

local function get_picker_select()
  if _G.Snacks and _G.Snacks.picker and _G.Snacks.picker.select then
    return _G.Snacks.picker.select
  end

  local ok, snacks = pcall(require, "snacks")
  if ok and snacks and snacks.picker and snacks.picker.select then
    return snacks.picker.select
  end

  return nil
end

local function select_sync(prompt, on_choice)
  local picker_select = get_picker_select()
  if not picker_select then
    vim.notify("mutagen.nvim: snacks.nvim picker not available", vim.log.levels.WARN)
    return
  end

  local syncs = mutagen.sync_list()
  if #syncs == 0 then
    vim.notify("mutagen.nvim: no active sync sessions", vim.log.levels.INFO)
    return
  end

  picker_select(syncs, {
    prompt = prompt,
    format_item = function(item)
      return item.name .. " status: " .. item.status
    end,
  }, on_choice)
end

function M.picker(opts)
  local prompt = (opts and opts.prompt) or "Mutagen syncs"
  select_sync(prompt, function(sync)
    if not sync then
      return
    end
    mutagen.sync_flush(sync.name)
  end)
end

function M.picker_terminate(opts)
  local prompt = (opts and opts.prompt) or "Mutagen syncs (terminate)"
  select_sync(prompt, function(sync)
    if not sync then
      return
    end
    mutagen.sync_terminate(sync.name)
  end)
end

return M
