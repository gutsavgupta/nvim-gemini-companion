# nvim-gemini-companion

🚀 Now with Dual Agent Support (++Qwen-Code)! 🤖

`nvim-gemini-companion` brings Gemini CLI + Qwen-Code directly into Neovim! 🚀 Enjoy diff views, agent management, and smart file modifications while keeping your workflow blazing fast. 🌟 Get 3000 free daily requests (1000 from Gemini + 2000 from Qwen) with their subscription-free model - no middleware needed!

![Gemini](https://raw.githubusercontent.com/gutsavgupta/nvim-gemini-companion/dev/assets/Gemini-20250928.png)
-------
![Qwen](https://raw.githubusercontent.com/gutsavgupta/nvim-gemini-companion/dev/assets/Qwen-20250928.png)
-------

## Demo
https://github.com/user-attachments/assets/48324de2-1c7c-4a00-966a-23836aecd29e

## Features

*   ✅ **Diff Control:** Auto diff views, accept or reject suggestions directly from vim using `:wq` or `:q`.
*   ✅ **CLI Agent:** Dedicated terminal session for interacting with AI agents
*   ✅ **Multi-Agent Support:** Run both `gemini` and `qwen-code` agents simultaneously 
*   ✅ **Tab-based Switching:** Effortlessly switch between AI terminals with `<Tab>`
*   ✅ **Context Management:** Tracks open files, cursor position, and selections for AI context
*   ✅ **LSP Diagnostics:** Send file/line diagnostics to AI agents for enhanced debugging
*   ✅ **Send Selection:** Send selected text + prompt directly to AI agents using `:GeminiSend` command
*   ✅ **Switchable Sidebar:** Choose between `right-fixed`, `left-fixed`, `bottom-fixed`, or `floating` styles
*   ✅ **Highly Customizable:** Configure commands, window styles, and key bindings to your liking

## Prerequisites

Install `gemini` and/or `qwen-code` CLIs to your system PATH for plugin functionality. 

*   [gemini-cli](https://github.com/google-gemini/gemini-cli) 
*   [qwen-code](https://github.com/QwenLM/qwen-code)

## Installation

You can install the plugin using `lazy.nvim`:

```lua
{
  "gutsavgupta/nvim-gemini-companion",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "folke/snacks.nvim",
  },
  event = "VeryLazy",
  config = function()
    -- You can configure the plugin by passing a table to the setup function
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
    { "<leader>ga", "<cmd>GeminiAccept<cr>", desc = "Accept Gemini suggested changes"},
    { "<leader>gr", "<cmd>GeminiReject<cr>", desc = "Reject Gemini suggested changes"},
    { "<leader>gD", "<cmd>GeminiSendFileDiagnostic<cr>", desc = "Send File Diagnostics"},
    { "<leader>gd", "<cmd>GeminiSendLineDiagnostic<cr>", desc = "Send Line Diagnostics"},
    { "<leader>gs", "<cmd>GeminiSwitchSidebarStyle<cr>", desc = "Switch Sidebar Style"},
  }
}
```

## Configuration

The following options are available in the `setup` function:

*   `cmds`: A list of commands to run for the CLI agents. Defaults to `{ "gemini", "qwen" }`.
    *   The plugin checks if the agent is installed in the system PATH and only enables it if found.
    *   If you want to use only one agent, you can set it as a single command string, e.g., `cmd = "gemini"`.
*   `win`: This option configures the window for the Gemini sidebar. It respects the `snacks.win` options from the [`folke/snacks.nvim`](https://github.com/folke/snacks.nvim) library. For more information on the available options, please refer to the [snacks.win documentation](https://github.com/folke/snacks.nvim/blob/main/docs/win.md).

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

The plugin comes with a few preset styles for the sidebar. You can set a preset using the `preset` key within the `win` option. The available presets are:
*   `right-fixed` (default)
*   `left-fixed`
*   `bottom-fixed`
*   `floating`

You can also override any of the preset's options by specifying them in the `win` table. For example, to use the `floating` preset but with a custom width and height:
```lua
require("gemini").setup({
  win = {
    preset = "floating",
    width = 0.8,
    height = 0.8,
  }
})
```

You can also switch between presets on the fly to find the one that best suits your needs using the `GeminiSwitchSidebarStyle` command.

## For Developers: Running Tests

To run the tests, you'll need to have `plenary.nvim` and `snacks.nvim` available. The test setup assumes a standard `lazy.nvim` directory structure.

Execute the following command from the root of the repository

```bash
XDG_CONFIG_HOME=$(pwd)/tests nvim --headless -c "PlenaryBustedDirectory tests"
```
This command will run all tests in the `tests` directory. To test a single file try: `-c "PlenaryBustedFile tests/ideMcpServer_spec.lua"`

### Important Notes

*   The test environment requires `plenary.nvim` and `snacks.nvim`. The test configuration file (`tests/nvim/init.lua`) assumes that these plugins are located at `~/.local/share/nvim/lazy/plenary.nvim` and `~/.local/share/nvim/lazy/snacks.nvim`. If your setup is different, you may need to adjust this path in the `init.lua` file.

## Roadmap

*   **ACP Protocol:** Implement ACP protocol support for deeper integration.
