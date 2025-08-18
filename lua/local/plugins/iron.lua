-- iron.lua
-- Lazy.nvim plugin spec that installs and configures whichpy.nvim + iron.nvim,
-- provides a Telescope picker to choose python/ipython interpreters, and
return {
  {
    'neolooong/whichpy.nvim',
    dependencies = { 'nvim-telescope/telescope.nvim', 'nvim-lua/plenary.nvim' },
    opts = {
      picker = { name = 'telescope', telescope = { prompt_title = 'WhichPy: Select Interpreter' } },
    },
    config = function(_, opts)
      -- safe setup (whichpy is optional — we still provide fallbacks)
      local ok, whichpy = pcall(require, 'whichpy')
      if ok then
        whichpy.setup(opts)
      end
    end,
  },

  {
    'Vigemus/iron.nvim',
    dependencies = { 'neolooong/whichpy.nvim' },
    config = function()
      local ok, iron = pcall(require, 'iron.core')
      if not ok then
        vim.notify('iron.nvim not found', vim.log.levels.WARN)
        return
      end

      -- Module state
      local state = {
        selected_python = nil, -- cached selection if whichpy isn't available
      }

      -- Utility: find a venv directory by walking parents up to $HOME
      local uv = vim.loop
      local function find_venv_dir(start)
        local cur = start or vim.fn.getcwd()
        local home = uv.os_homedir()
        while cur and cur ~= '' do
          for _, name in ipairs { 'venv', '.venv', 'env', '.env' } do
            local candidate = cur .. '/' .. name
            if vim.fn.isdirectory(candidate) == 1 then
              return candidate
            end
          end
          if cur == home or cur == '/' then
            break
          end
          local parent = vim.fn.fnamemodify(cur, ':h')
          if parent == cur or parent == '' then
            break
          end
          cur = parent
        end
        return nil
      end

      -- Helper to get python binary inside venv (cross-platform-ish)
      local function python_from_venv(venv_dir)
        if not venv_dir then
          return nil
        end
        local candidates = {
          venv_dir .. '/bin/ipython',
          venv_dir .. '/bin/ipython3',
          venv_dir .. '/bin/python',
          venv_dir .. '/bin/python3',
        }
        for _, p in ipairs(candidates) do
          if vim.fn.executable(p) == 1 then
            return p
          end
        end
        return nil
      end

      -- Try to get the currently selected interpreter from whichpy (if installed)
      local function get_whichpy_selected()
        local ok_envs, envs = pcall(require, 'whichpy.envs')
        if ok_envs and envs and type(envs.current_selected) == 'function' then
          local success, res = pcall(envs.current_selected)
          if success and res and res ~= vim.NIL and res ~= '' then
            if type(res) == 'string' then
              return res
            end
            if type(res) == 'table' and res.python then
              return res.python
            end
          end
        end
        return nil
      end

      -- Fallback lookup for common interpreters (ipython/python) using PATH and defaults
      local function discover_interpreters()
        local list_map = {}
        local function add(path)
          if path and path ~= '' and vim.fn.executable(path) == 1 then
            list_map[path] = true
          end
        end
        local venv = find_venv_dir()
        if venv then
          add(python_from_venv(venv))
        end
        for _, name in ipairs { 'ipython3', 'ipython', 'python3', 'python' } do
          local p = vim.fn.exepath(name)
          add(p)
        end
        for _, p in ipairs { '/usr/bin/ipython3', '/usr/bin/ipython', '/usr/bin/python3', '/usr/bin/python' } do
          add(p)
        end
        local out = {}
        for k, _ in pairs(list_map) do
          table.insert(out, k)
        end
        table.sort(out)
        return out
      end

      -- Telescope picker fallback: show discovered interpreters and call WhichPy select <path> if available
      local function pick_interpreter_with_telescope()
        local has_telescope, pickers = pcall(require, 'telescope.pickers')
        if not has_telescope then
          vim.notify('Telescope not installed', vim.log.levels.WARN)
          return
        end
        local finders = require 'telescope.finders'
        local conf = require('telescope.config').values
        local actions = require 'telescope.actions'
        local action_state = require 'telescope.actions.state'
        local candidates = discover_interpreters()
        if #candidates == 0 then
          vim.notify('No python/ipython interpreters found', vim.log.levels.WARN)
          return
        end
        pickers
          .new({}, {
            prompt_title = 'Select Python / IPython interpreter',
            finder = finders.new_table { results = candidates },
            sorter = conf.generic_sorter {},
            attach_mappings = function(prompt_bufnr, map)
              actions.select_default:replace(function()
                local selection = action_state.get_selected_entry()
                actions.close(prompt_bufnr)
                if not selection or not selection[1] then
                  return
                end
                local path = selection[1]
                if pcall(vim.cmd, 'WhichPy') then
                  vim.cmd('WhichPy select ' .. vim.fn.shellescape(path))
                else
                  state.selected_python = path
                  vim.notify('Selected interpreter (cached): ' .. path)
                end
              end)
              return true
            end,
          })
          :find()
      end

      -- small helper to get the best python for the repl (whichpy -> cached -> venv -> PATH -> 'python')
      local function resolve_python_for_repl()
        local py = get_whichpy_selected()
        if py and py ~= '' then
          return py
        end
        if state.selected_python then
          return state.selected_python
        end
        local venv = find_venv_dir()
        local pv = python_from_venv(venv)
        if pv then
          return pv
        end
        for _, name in ipairs { 'ipython', 'python3', 'python' } do
          local p = vim.fn.exepath(name)
          if p and p ~= '' then
            return p
          end
        end
        return 'python'
      end

      -- Interrupt (send Ctrl-C) to REPL using the official iron.nvim API
      local function interrupt_repl()
        require('iron.core').send(nil, { string.char(3) })
      end

      -- Clear the REPL screen using the official iron.nvim API
      local function clear_repl_terminal()
        -- Note: This sends the "clear" command. It clears the visible screen
        -- but not the terminal's scrollback buffer. This is the most robust method.
        require('iron.core').send(nil, { 'clear' })
      end

      -- Small convenience: send selected visual lines (used by a mapping below)
      local function send_visual_selection()
        require('iron.core').visual_send()
        -- local iron_core = require 'iron.core'
        -- local start_line = vim.fn.line "'<"
        -- local end_line = vim.fn.line "'>"
        -- local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
        -- local text = table.concat(lines, '\n')
        -- iron_core.send(nil, { text })
      end
      -- Setup iron.nvim now with a dynamic python command
      local view = require 'iron.view'

      -- Build a 25% botright vertical split opener we can wrap
      local open25 = view.split.vertical.botright('25%', { winfixwidth = false })

      -- Keep track of REPL windows we open so we can resize them later
      local iron_repl_winids = {}

      -- Wrapper: open the REPL, then mark the window as "dynamic 25%"
      local function open_repl_25pct(bufnr)
        open25(bufnr)
        local win = vim.api.nvim_get_current_win()
        -- Tag window so our autocmd can find it
        pcall(vim.api.nvim_win_set_var, win, 'iron_dynamic_25pct', true)
        iron_repl_winids[win] = true
        return win
      end

      -- Autocmd: whenever the UI size changes, re-apply 25% width
      local aug = vim.api.nvim_create_augroup('IronDynamic25pct', { clear = true })
      vim.api.nvim_create_autocmd('VimResized', {
        group = aug,
        callback = function()
          local target = math.floor(vim.o.columns * 0.25)
          for _, win in ipairs(vim.api.nvim_list_wins()) do
            local ok_var, tag = pcall(vim.api.nvim_win_get_var, win, 'iron_dynamic_25pct')
            if ok_var and tag and vim.api.nvim_win_is_valid(win) then
              pcall(vim.api.nvim_win_set_width, win, target)
            end
          end
        end,
      })
      iron.setup {
        config = {
          scratch_repl = true,
          repl_definition = {
            python = {
              command = function()
                local py = resolve_python_for_repl()
                return { py, '--no-autoindent' }
              end,
              block_dividers = { '# %%', '#%%' },
              format = require('iron.fts.common').bracketed_paste,
            },
          },
          repl_open_cmd = open_repl_25pct,
        },
        highlight = { italic = true },
        ignore_blank_lines = true,
      }

      -- Keymaps (register them here so the helper functions are visible)
      vim.keymap.set({ 'n', 'v', 'i' }, '<leader>jpi', function() -- open WhichPy/Telescope picker OR fallback
        if pcall(vim.cmd, 'WhichPy') then
          vim.cmd 'WhichPy select'
        else
          pick_interpreter_with_telescope()
        end
      end, { desc = 'Pick Python interpreter (WhichPy/Telescope)' })

      vim.keymap.set({ 'n', 'v' }, '<leader>ji', '<cmd>IronRepl<cr>', { desc = '[J]upiter [I]nit REPL' })
      vim.keymap.set({ 'n', 'v' }, '<leader>jr', '<cmd>IronRestart<cr>', { desc = '[J]upiter [R]estart REPL' })
      vim.keymap.set({ 'n', 'v' }, '<leader>jf', '<cmd>IronFocus<cr>', { desc = '[J]upiter [F]ocus REPL' })
      vim.keymap.set({ 'n', 'v' }, '<leader>jh', '<cmd>IronHide<cr>', { desc = '[J]upiter [H]ide REPL' })

      -- Use the new, correct functions for interrupt and clear
      vim.keymap.set('n', '<leader>jI', interrupt_repl, { desc = '[J]upiter [I]nterrupt' })
      vim.keymap.set('n', '<leader>jc', clear_repl_terminal, { desc = '[J]upiter [C]lear REPL Terminal' })
      vim.keymap.set('n', '<leader>jq', '<cmd>IronHide<cr>', { desc = '[J]upiter [Q]uit (hide) REPL' })

      -- Send children
      vim.keymap.set({ 'n', 'v' }, '<leader>jF', function()
        require('iron.core').send_file()
      end, { desc = '[J]upiter ▸ Send [F]ile' })
      vim.keymap.set({ 'n', 'v' }, '<leader>jb', function()
        require('iron.core').send_code_block(false)
      end, { desc = '[J]upiter ▸ Send [B]lock' })
      vim.keymap.set({ 'n', 'v' }, '<leader>ju', function()
        require('iron.core').send_until_cursor()
      end, { desc = '[J]upiter ▸ Send [U]ntil Cursor' })
      vim.keymap.set({ 'n', 'v' }, '<leader>jl', function()
        require('iron.core').send_line()
      end, { desc = '[J]upiter Send [L]ine' })

      vim.keymap.set('v', '<leader>jm', send_visual_selection, { desc = '[J]upiter ▸ Send [M]arked Text' })
      vim.keymap.set('n', '<leader>jn', function()
        require('iron.core').send_code_block(true)
      end, { desc = '[J]upiter ▸ Send Block and [N]ext/Move' })
      vim.keymap.set('n', '<leader>jps', function()
        if pcall(require, 'whichpy') then
          vim.cmd 'WhichPy rescan'
          vim.notify('WhichPy rescanned interpreters', vim.log.levels.INFO)
        else
          vim.notify('whichpy not installed', vim.log.levels.WARN)
        end
      end, { desc = 'Rescan interpreters (WhichPy)' })
    end,
  },
}
