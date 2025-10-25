# nvim-gemini-companion

🚀 Now with Dual Agent Support (Gemini & Qwen)! 🤖

`nvim-gemini-companion` brings the power of AI agents like Gemini and Qwen directly into your Neovim workflow. 🌟 Enjoy seamless diff views, agent management, and smart file modifications without leaving your editor.

![Gemini](https://raw.githubusercontent.com/gutsavgupta/nvim-gemini-companion/main/assets/Gemini-20250928.png)
-------
![Qwen](https://raw.githubusercontent.com/gutsavgupta/nvim-gemini-companion/main/assets/Qwen-20250928.png)
-------

## Demo
https://github.com/user-attachments/assets/48324de2-1c7c-4a00-966a-23836aecd29e

## Features

*   ✅**Diff Control:** Auto diff views, accept or reject suggestions directly from vim using `:wq` or `:q`.
*   ✅ **CLI Agent:** Dedicated terminal session for interacting with AI agents
*   ✅ **Multi-Agent Support:** Run both `gemini` and `qwen-code` agents simultaneously 
*   ✅ **Tab-based Switching:** Effortlessly switch between AI terminals with `<Tab>`
*   ✅ **Context Management:** Tracks open files, cursor position, and selections for AI context
*   ✅ **LSP Diagnostics:** Send file/line diagnostics to AI agents for enhanced debugging
*   ✅ **Send Selection:** Send selected text + prompt directly to AI agents using `:GeminiSend` command
*   ✅ **Switchable Sidebar:** Choose between `right-fixed`, `left-fixed`, `bottom-fixed`, or `floating` styles
*   ✅ **Highly Customizable:** Configure commands, window styles, and key bindings to your liking

## Prerequisites

Install the `gemini` and/or `qwen` CLIs and ensure they are in your system's `PATH`.

*   [gemini-cli](https://github.com/google-gemini/gemini-cli) 
*   [qwen-code](https://github.com/QwenLM/qwen-code)

## Installation

You can install the plugin using `lazy.nvim`:

```lua
{
  "gutsavgupta/nvim-gemini-companion",
  dependencies = {
    "nvim-lua/plenary.nvim",
  },
  event = "VeryLazy",
  config = function()
    -- You can configure the plugin by passing a table to the setup function.
    -- Example:
    -- require("gemini").setup({
    --   cmds = {"gemini"},
    --   env = {},
    --   win = {
    --     preset = "floating",
    --     width = 0.8,
    --     height = 0.8,
    --     wo = {},
    --   }
    -- })
    require("gemini").setup()
  end,
  keys = {
    { "<leader>gs", "<cmd>GeminiSwitchSidebarStyle<cr>", desc = "Switch Sidebar Style"},
    { "<leader>gg", "<cmd>GeminiToggle<cr>", desc = "Toggle cli agents in sidebar"},
    { "<leader>gt", "<cmd>GeminiSwitchToCli<cr>", desc = "Spawn or switch to a tmux/sidebar cli session"},
    { "<leader>gc", "<cmd>GeminiClose<cr>", desc = "Close sidebar process"},
    { "<leader>gD", "<cmd>GeminiSendFileDiagnostic<cr>", desc = "Send File Diagnostics to an active session"},
    { "<leader>gd", "<cmd>GeminiSendLineDiagnostic<cr>", desc = "Send Line Diagnostics to an active session"},
    { "<leader>gS",
        function() 
            vim.cmd('normal! gv')
            vim.cmd("'<,'>GeminiSend")
        end,
        mode = { 'x' },
        desc = 'Send selected to a cli session in visual mode',
  }
}
```

## Configuration

The following options are available in the `setup` function:

*   `cmds`: A list of commands to run for the CLI agents. Defaults to `{ "gemini", "qwen" }`.
    *   The plugin checks if each agent is installed in the system `PATH` and only enables it if found.
    *   If you want to use only one agent, you can set it as a single command string, e.g., `cmd = "gemini"`.
*   `win`: This option configures the window for the sidebar. 
*   `env`: Table of environment variables to pass to the CLI agents

## Commands

The plugin provides the following commands:

*   `:GeminiToggle` - Toggle the Gemini sidebar
*   `:GeminiClose` - Close the Gemini CLI process
*   `:GeminiSendFileDiagnostic` - Send file diagnostics to AI agent
*   `:GeminiSendLineDiagnostic` - Send line diagnostics to AI agent 
*   `:GeminiSwitchSidebarStyle` - Switch between sidebar styles
*   `:GeminiSend [text]` - Send (if selected) text to AI agent (in visual mode)
*   `:GeminiAccept` - Accept changes in diff view
*   `:GeminiReject` - Reject changes in diff view
*   `:GeminiAnnouncement [arg]` - Show plugin announcements; if no argument is provided, shows the latest announcement; if an argument is provided, shows the specific announcement version (e.g., `:GeminiAnnouncement v0.5_release`)
*   `:GeminiSwitchToCli [type command]` - Switch to or spawn a CLI in either tmux or sidebar. If no arguments are provided, prompts for selection. When arguments are provided in the format `<type> <command>` (e.g., `tmux gemini` or `sidebar qwen`), it will spawn the specified command in the specified type. This allows you to run your AI agents in separate tmux windows or sidebar for better workflow management and session persistence.

## Tmux Support

The plugin now includes built-in support for running AI agent sessions in separate tmux windows. This allows for better workflow management and session persistence. Key features include:

*   **Session Persistence**: CLI connections maintain state across nvim sessions with port reuse
*   **Easy Switching**: Use `:GeminiSwitchToCli` to spawn or switch to existing tmux windows and sidebar terminals
*   **Multiple Agent Support**: Each agent (gemini, qwen) gets its own tmux window or sidebar terminal with unique naming
*   **Automatic Session Management**: Plugin tracks both sidebar and tmux sessions for unified experience
*   **Unified Interface**: All CLI sessions (tmux and sidebar) are accessible through the same commands

To use tmux functionality, you must be running neovim inside an active tmux session.

## Enhanced CLI Switching with GeminiSwitchToCli

The `:GeminiSwitchToCli` command offers advanced session management capabilities:

### Usage
*   `:GeminiSwitchToCli` - Prompt for selection between available sessions
*   `:GeminiSwitchToCli tmux gemini` - Spawn or switch to gemini in a tmux window
*   `:GeminiSwitchToCli sidebar qwen` - Spawn or switch to qwen in the sidebar terminal
*   `:GeminiSwitchToCli tmux qwen` - Spawn or switch to qwen in a tmux window
*   `:GeminiSwitchToCli sidebar gemini` - Spawn or switch to gemini in the sidebar terminal

### Recommended Key Mappings
Add these shortcuts to your configuration for quick access to specific CLI types:

```lua
keys = {
  -- ... existing key mappings ...
  { "<leader>g1", "<cmd>GeminiSwitchToCli tmux gemini<cr>", desc = "Switch to tmux gemini session" },
  { "<leader>g2", "<cmd>GeminiSwitchToCli tmux qwen<cr>", desc = "Switch to tmux qwen session" },
  { "<leader>g3", "<cmd>GeminiSwitchToCli sidebar gemini<cr>", desc = "Switch to sidebar gemini session" },
  { "<leader>g4", "<cmd>GeminiSwitchToCli sidebar qwen<cr>", desc = "Switch to sidebar qwen session" },
}
```

These shortcuts provide quick access to your preferred AI agent setup without having to type the full command each time.

## Picker Configuration

The plugin uses `vim.ui.select` for interactive selection prompts (such as choosing between multiple active sessions). For a better selection experience, you can configure an enhanced picker like fzf-lua, telescope, or snacks.nvim.

<details>
<summary>Config I am using to shadow vim.ui.select with fzf-lua </summary>

To use fzf-lua as a replacement for the default `vim.ui.select`:

```lua
-- Add fzf-lua to your dependencies
{
  "gutsavgupta/nvim-gemini-companion",
  dependencies = {
    "nvim-lua/plenary.nvim",
    'ibhagwan/fzf-lua',
  },
  event = "VeryLazy",
  config = function(opts)
    require('gemini').setup({opts})
    
    -- Override vim.ui.select with fzf-lua
    vim.ui.select = function(items, opts, onChoice)
      require('fzf-lua').fzf_exec(items, {
        prompt = opts.prompt or 'select from items',
        actions = {
          ['default'] = function(selected) onChoice(selected[1]) end,
        },
        winopts = { height = math.min(0.2 + #items * 0.05, 0.6) },
      })
    end
  end
}
```

This configuration replaces the default selection UI with fzf-lua for a more powerful and visually appealing selection interface when choosing between AI sessions, commands, or other options.
Note: Similar implementations exist for other picker plugins like telescope and snacks.nvim, or you can use plugins that automatically enhance vim.ui.select.

</details>

### Accepting and Rejecting Diffs

When a diff view is presented, you have multiple ways to handle the suggested changes:

*   **Vim-style Commands:**
    *   `:w` or `:wq`: Write the buffer to accept the changes.
    *   `:q` or `:q!`: Quit the buffer without writing to reject the changes.
    This behavior is inspired by `vim.pack`.

*   **Plugin Commands:**
    *   `:GeminiAccept`: Accept the changes.
    *   `:GeminiReject`: Reject the changes.

These commands provide flexibility in how you manage the diffs, allowing you to use the method you find most comfortable.


### Sidebar Presets

The plugin includes several preset styles for the sidebar. You can set a preset using the `preset` key within the `win` option.

Available presets:
*   `right-fixed` (default)
*   `left-fixed`
*   `bottom-fixed`
*   `floating`

You can override any preset's options by specifying them in the `win` table. For example, to use the `floating` preset with a custom width and height:
```lua
require("gemini").setup({
  win = {
    preset = "floating",
    width = 0.8,
    height = 0.8,
  }
})
```

You can also cycle through presets on the fly using the `GeminiSwitchSidebarStyle` command to find the one that best suits your needs.

## For Developers: Running Tests

To run the tests, execute the following command from the root of the repository:

```bash
XDG_CONFIG_HOME=./tests nvim --headless -c "PlenaryBustedDirectory tests"
```
This command will run all tests in the `tests` directory. To test a single file, use: `-c "PlenaryBustedFile tests/ideMcpServer_spec.lua"`

The test setup includes automatic dependency management and will install `plenary.nvim` as needed.

### Important Notes

*   The test configuration now supports the `GEMINI_TEST_CMDS` environment variable to specify commands for testing (comma-separated), defaulting to `{'no-cli'}`.


## Roadmap

*   **ACP Protocol:** Implement ACP protocol support for deeper integration.
