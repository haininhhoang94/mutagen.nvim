# mutagen.nvim
Small plugin that provides some utils to interact with [mutagen](https://mutagen.io/documentation/synchronization/) through neovim.  
It only covers the remote filesystem aspect of mutagen. Very useful for remote development.
## Features
- Auto flush sync after buffer write (only inside git repos whose root has `mutagen.yml`)
- Telescope integration
- Snacks picker integration
- Sync status indicator in e.g. lualine

Auto flush notifications are low-noise by default:
- no popup on normal success
- popup on first failure
- duplicate failure popups throttled (60s cooldown)
- one recovery popup after failures start succeeding again
## Install
```lua
  {
    "lothran/mutagen.nvim",
    opts = {
      auto_flush_debounce_ms = 400,
      notifications = {
        success = false,
        failure = true,
        recovery = true,
        failure_cooldown_ms = 60000,
        persistent_failure_reminder_ms = 300000,
      },
    }
  },
```
## Telescope
![alt text](./imgs/telescope.png)

```lua
  {
    "nvim-telescope/telescope.nvim",
    dependencies = {
      "lothran/mutagen.nvim",
    },
    keys = {
      { "<space>ml",  "<CMD>Telescope mutagen<CR>",                               mode = { "n", "v" } },
    },
    config = function()
      require('telescope').load_extension('mutagen')
    end
  },
```
- enter to flush a sync
- `<ctrl-t>` to terminate a sync (note this done by simple name matching, if two have the same name both will be terminated)

## Snacks
```lua
{
  "folke/snacks.nvim",
  keys = {
    {
      "<space>ml",
      function()
        require("mutagen.snacks").picker()
      end,
      mode = { "n", "v" },
      desc = "Mutagen: flush sync",
    },
    {
      "<space>mT",
      function()
        require("mutagen.snacks").picker_terminate()
      end,
      mode = { "n", "v" },
      desc = "Mutagen: terminate sync",
    },
  },
}
```
- `picker()` selects a sync and flushes it.
- `picker_terminate()` selects a sync and terminates it.

## Lualine
![alt text](./imgs/lualine.png)
```lua
-- Inserts a component in lualine_x at right section
local function ins_right(component)
  table.insert(config.sections.lualine_x, component)
end
ins_right {
  function()
    local mutagen = require("mutagen")
    local sync = mutagen.sync_find()
    local symbols = { ' ', ' ' }
    local status = 0
    if sync == nil then
      return "None"
    else
      if mutagen.sync_connected(sync) then
        status = 1
      else
        status = 2
      end
      return sync.name .. symbols[status]
    end
  end,
  icon = ' mutagen:',

}
```
