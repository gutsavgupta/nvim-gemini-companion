# nvim-gemini-companion

`nvim-gemini-companion` is a Neovim plugin that integrates the Gemini CLI for a streamlined development experience. It allows you to use the Gemini CLI's features directly within Neovim, including diff views for suggested changes, a sidebar for managing the CLI agent, and automatic handling of file modifications. This plugin is designed for ease of use and can be customized to fit your workflow.

![Watch the video](https://raw.githubusercontent.com/gutsavgupta/nvim-gemini-companion/dev/assets/Screenshot_20250925-192514.png)

## Demo
https://github.com/user-attachments/assets/bcce8fce-78d8-4f5a-8945-365ce636adf7

## Features

*   **Diff View:** Open a diff view to compare your local file with the content suggested by the Gemini CLI. You can accept or reject the changes, and the plugin will handle the file updates for you.
*   **CLI Agent:** The plugin provides a sidebar that hosts the Gemini CLI, allowing you to interact with it in a dedicated terminal session.
*   **Context Management:** The plugin tracks your workspace state, including open files, cursor position, and selected text, and provides this context to the Gemini CLI.
*   **Customizable:** The plugin is highly customizable, allowing you to configure the sidebar width, the Gemini CLI command, and key bindings to your liking.

## Prerequisites

This plugin requires the `gemini` to be installed and available in your system's PATH. If you need to use a different command or path for the `gemini`, you can configure it using the `command` option in the plugin's setup.

For installation instructions for the gemini-cli, please refer to the official GitHub page: [gemini-cli](https://github.com/google-gemini/gemini-cli)

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
    -- You can configure the plugin by passing a table to the setup function
    -- Example:
    -- require("gemini").setup({
    --   width = 100,
    --   command = "gemini",
    -- })
    require("gemini").setup()
  end,
  keys = {
    { "<leader>gg", "<cmd>GeminiToggle<cr>", desc = "Toggle Gemini CLI"},
    { "<leader>gc", "<cmd>GeminiClose<cr>", desc = "Close Gemini CLI process"},
    { "<leader>ga", "<cmd>GeminiAccept<cr>", desc = "Accept Gemini suggested changes"},
    { "<leader>gr", "<cmd>GeminiReject<cr>", desc = "Reject Gemini suggested changes"},
  }
}
```

## Configuration

The following options are available in the `setup` function:

*   `width`: The width of the sidebar. Defaults to `80`.
*   `command`: The command to run for the Gemini CLI. Defaults to `gemini`.

## For Developers: Running Tests

To run the tests, you'll need to have `plenary.nvim` available. The test setup assumes a standard `lazy.nvim` directory structure.

Execute the following command from the root of the repository

```bash
XDG_CONFIG_HOME=$(pwd)/tests nvim --headless -c "PlenaryBustedDirectory tests"
```
This command will run all tests in the `tests` directory. To test a single file try: `-c "PlenaryBustedFile tests/ideMcpServer_spec.lua"`

### Important Notes

*   The test environment requires `plenary.nvim`. The test configuration file (`tests/nvim/init.lua`) assumes that `plenary.nvim` is located at `~/.local/share/nvim/lazy/plenary.nvim`. If your setup is different, you may need to adjust this path in the `init.lua` file.

## Roadmap

*   **LSP Diagnostics:** Send LSP diagnostic information to the Gemini CLI for enhanced debugging.
*   **ACP Protocol:** Implement ACP protocol support for deeper integration.
