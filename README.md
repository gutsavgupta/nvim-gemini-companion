# nvim-gemini-companion

Gemini CLI companion now speaks Qwen! 🚀

`nvim-gemini-companion` is a Neovim plugin that integrates the Gemini CLI + Qwen-Code for a streamlined development experience. It allows you to use the Gemini/Qwen CLI's features directly within Neovim, including diff views for suggested changes, a sidebar for managing the CLI agent, and automatic handling of file modifications. This plugin is designed for ease of use and can be customized to fit your workflow.

![Floating Sidebar](https://raw.githubusercontent.com/gutsavgupta/nvim-gemini-companion/dev/assets/gemini-20250926-floating.png)
-------
![Right Fixed Sidebar](https://raw.githubusercontent.com/gutsavgupta/nvim-gemini-companion/dev/assets/gemini-20250926-right-fixed.png)
-------

## Demo
https://github.com/user-attachments/assets/bcce8fce-78d8-4f5a-8945-365ce636adf7

## Features

*   **Diff View:** Open a diff view to compare your local file with the content suggested by the Gemini CLI. You can accept or reject the changes, and the plugin will handle the file updates for you.
*   **CLI Agent:** The plugin provides a sidebar that hosts the Gemini CLI, allowing you to interact with it in a dedicated terminal session.
*   **Multi-Agent Support:** The plugin now supports both `gemini` and `qwen-code` CLI agents. You can run them simultaneously and switch between them seamlessly.
*   **Tab-based Switching:** When multiple agents are configured, you can easily switch between their terminals by pressing the `<Tab>` key.
*   **Context Management:** The plugin tracks your workspace state, including open files, cursor position, and selected text, and provides this context to the Gemini CLI.
*   **LSP Diagnostics:** Send LSP diagnostics for the current file or line to the Gemini CLI for enhanced debugging.
*   **Switchable Sidebar Style:** Switch between different sidebar styles (e.g., `right-fixed`, `floating`) to find the one that best suits your workflow.
*   **Customizable:** The plugin is highly customizable, allowing you to configure the sidebar, the Gemini CLI command, and key bindings to your liking.

## Prerequisites

This plugin requires the `gemini` and/or `qwen-code` to be installed and available in your system's PATH. If you need to use a different command or path for the CLIs, you can configure it using the `cmds` option in the plugin's setup.

For installation instructions for the gemini-cli, please refer to the official GitHub page: [gemini-cli](https://github.com/google-gemini/gemini-cli)
For qwen-code, please refer to: [qwen-code](https://github.com/qwen-team/qwen-code)

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
    *   If you want to use only one agent, you can set it as a single command string, e.g., `cmd = "gemini"`.
*   `win`: This option configures the window for the Gemini sidebar. It respects the `snacks.win` options from the [`folke/snacks.nvim`](https://github.com/folke/snacks.nvim) library. For more information on the available options, please refer to the [snacks.win documentation](https://github.com/folke/snacks.nvim/blob/main/docs/win.md).

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
