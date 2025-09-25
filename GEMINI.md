# nvim-gemini-companion

This file outlines the project structure and coding guidelines for the `nvim-gemini-companion` Neovim plugin.

## Directory Structure

*   `lua/`: Contains the Lua modules for the plugin.
*   `tests/`: Contains the test files for the plugin.
*   `README.md`: The main documentation for the plugin.

## Coding Guidelines

*   **Testing:** Use Lua for tests to ensure testability and a stable release process.
*   **Formatting:** Auto-format all code with `lua-format` before committing.
*   **Naming:** Use camelCase for all naming (variables, files, etc.).
*   **Modern Lua:** Keep Lua modules modern and isolated. Use `require` for dependencies and avoid global variables.
*   **No License Headers:** Do not add license headers to new files to keep them simple and minimal.
*   **Function Documentation:** Add a comment on top of each function describing its inputs, outputs, and intent. Keep these comments updated when the function's interface or implementation changes.

## Commit Messages

All commit messages should follow the [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) specification. This creates a more readable and structured commit history.

### Format

Each commit message consists of a **header**, a **body**, and a **footer**.

```
<type>[optional scope]: <description>

[optional body]

[optional footer]
```

*   **type**: Must be one of the following:
    *   `feat`: A new feature
    *   `fix`: A bug fix
    *   `docs`: Documentation only changes
    *   `style`: Changes that do not affect the meaning of the code (white-space, formatting, missing semi-colons, etc)
    *   `refactor`: A code change that neither fixes a bug nor adds a feature
    *   `perf`: A code change that improves performance
    *   `test`: Adding missing tests or correcting existing tests
    *   `chore`: Changes to the build process or auxiliary tools and libraries such as documentation generation
*   **scope**: (Optional) A noun specifying the part of the codebase affected by the change (e.g., `sidebar`, `diff`, `mcp`).
*   **description**: A concise description of the change in the present tense.
*   **body**: (Optional) A longer description of the change, providing more context.
*   **footer**: (Optional) Contains any information about breaking changes or references to issues.

### Example

```
feat(sidebar): Add toggle functionality

The new `toggle` function allows the user to open and close the sidebar
with a single command. This improves user experience by reducing the
number of commands needed to manage the sidebar.
```