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
*   ✅ **Tmux Integration:** Connect `gemini` and `qwen` CLIs to Neovim from a Tmux session.

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
    --   win = {
    --     preset = "floating",
    --     width = 0.8,
    --     height = 0.8,
    --   }
    -- })
    require("gemini").setup()
  end,
  keys = {
    { "<leader>gg", "<cmd>GeminiToggle<cr>", desc = "Toggle Gemini CLI"},
    { "<leader>gc", "<cmd>GeminiClose<cr>", desc = "Close Gemini CLI process"},
    { "<leader>gD", "<cmd>GeminiSendFileDiagnostic<cr>", desc = "Send File Diagnostics"},
    { "<leader>gd", "<cmd>GeminiSendLineDiagnostic<cr>", desc = "Send Line Diagnostics"},
    { "<leader>gs", "<cmd>GeminiSwitchSidebarStyle<cr>", desc = "Switch Sidebar Style"},
    { "<leader>gS", "<cmd>GeminiSend<cr>", mode = "v", desc = "Send Selected Text to AI Agent"},
  }
}
```

## Configuration

The following options are available in the `setup` function:

*   `cmds`: A list of commands to run for the CLI agents. Defaults to `{ "gemini", "qwen" }`.
    *   The plugin checks if each agent is installed in the system `PATH` and only enables it if found.
    *   If you want to use only one agent, you can set it as a single command string, e.g., `cmd = "gemini"`.
*   `win`: This option configures the window for the sidebar. 

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

### Health Check

The plugin includes a health check to help you diagnose issues with your setup. It verifies:
*   The status of the background IDE server.
*   The detection of `gemini` and `qwen` binaries in your `PATH`.
*   The installation status of the CLI integration wrappers.

To run the health check, use the following command in Neovim:

```
:checkhealth gemini
```

### Tmux Integration

Connect the `gemini` and `qwen` CLIs to your running Neovim instance directly from a terminal within a **Tmux** window. This allows the CLIs to seamlessly open files, apply diffs, and interact with your editor.

**Installation**

To enable this integration, you need to install wrapper scripts. The plugin provides commands to do this automatically.

1.  **Install the wrappers:**
    ```
    :GeminiInstallMuxWrappers
    ```
    This command will create wrapper scripts in `~/.local/bin` by default.

2.  **Ensure `~/.local/bin` is in your `PATH`:**
    For the wrappers to be used, the installation directory must be in your shell's `PATH`. Make sure you add it to your `.bashrc`, `.zshrc`, or other shell configuration file.

    ```sh
    export PATH="$HOME/.local/bin:$PATH"
    ```

**How it Works**

The installer creates scripts that intercept calls to `gemini` and `qwen`. When you run these commands from a Tmux pane, the script looks for a running Neovim instance. If found, it connects to the plugin's server; otherwise, it runs the original CLI command as a fallback.

**Uninstallation**

To remove the wrapper scripts, you can run:
```
:GeminiRemoveMuxWrappers
```

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
