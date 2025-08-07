return {
  'nvim-telescope/telescope-frecency.nvim',
  config = function()
    require('telescope').setup {
      extensions = {
        frecency = {
          show_scores = true, -- Default: false
          -- If `true`, it shows confirmation dialog before any entries are removed from the DB
          -- If you want not to be bothered with such things and to remove stale results silently
          -- set db_safe_mode=false and auto_validate=true
          --
          -- This fixes an issue I had in which I couldn't close the floating
          -- window because I couldn't focus it
          db_safe_mode = false, -- Default: true
          -- If `true`, it removes stale entries count over than db_validate_threshold
          auto_validate = true, -- Default: true
          -- It will remove entries when stale ones exist more than this count
          db_validate_threshold = 10, -- Default: 10
          -- Show the path of the active filter before file paths.
          -- So if I'm in the `dotfiles-latest` directory it will show me that
          -- before the name of the file
          show_filter_column = false, -- Default: true
        },
      },
    }
    require('telescope').load_extension 'frecency'
  end,
}
