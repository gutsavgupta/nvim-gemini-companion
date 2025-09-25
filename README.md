# nvim-gemini-companion

`nvim-gemini-companion` is a Neovim plugin that seamlessly integrates the Gemini CLI into your development workflow. It provides a powerful set of features that allow you to interact with the Gemini CLI without leaving the comfort of your editor. With this plugin, you can open diff views to compare your local changes with the Gemini CLI's suggestions, manage a CLI agent in a sidebar, and handle file changes with ease.

## Demo

[![Watch the video](https://raw.githubusercontent.com/gutsavgupta/nvim-gemini-companion/dev/assets/Screenshot_20250925-192514.png)](https://raw.githubusercontent.com/gutsavgupta/nvim-gemini-companion/dev/assets/Screencast_20250925-190922.mp4)

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

Execute the following command from the root of the repository:

```bash
XDG_CONFIG_HOME=$(pwd)/tests nvim --headless -c "PlenaryBustedFile tests/mcpServer_spec.lua"
```

This command runs a specific test file. You can replace `tests/mcpServer_spec.lua` with the path to any other test file you wish to run, or you can give `-c "PlenaryBustedDirectory tests"` to run all

### Important Notes

*   The test environment requires `plenary.nvim`. The test configuration file (`tests/nvim/init.lua`) assumes that `plenary.nvim` is located at `~/.local/share/nvim/lazy/plenary.nvim`. If your setup is different, you may need to adjust this path in the `init.lua` file.
