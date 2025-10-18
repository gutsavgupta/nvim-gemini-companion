#!/bin/bash

# This script connects to a running nvim-gemini-companion instance from a tmux pane.
# If it can't find a running instance, it falls back to executing the original command.

print_usage() {
  echo "Usage: $(basename "$0") <gemini|qwen> [--path /path/to/executable] [args...]"
  echo "       $(basename "$0") --help"
  echo ""
  echo "This script connects to a running nvim-gemini-companion instance from a tmux pane."
  echo "If it can't find a running instance, it falls back to executing the original command."
}

find_nvim_session() {
  if [ -z "$TMUX" ]; then
    return 1
  fi

  local TMUX_PANE_PIDS
  TMUX_PANE_PIDS=$(tmux list-panes -F "#{pane_pid}")

  for pane_pid in $TMUX_PANE_PIDS; do
    local main_nvim_pid=""
    if [ "$(ps -p $pane_pid -o comm=)" = "nvim" ]; then
      main_nvim_pid=$pane_pid
    else
      local child_nvim_pid
      child_nvim_pid=$(pgrep -P $pane_pid nvim)
      if [ -n "$child_nvim_pid" ]; then
        main_nvim_pid=$child_nvim_pid
      fi
    fi

    if [ -n "$main_nvim_pid" ]; then
      local pids_to_check="$main_nvim_pid $(pgrep -P "$main_nvim_pid")"
      for nvim_pid in $pids_to_check; do
        local CONN_FILE="/tmp/nvim-gemini-companion-$nvim_pid.json"
        if [ -f "$CONN_FILE" ]; then
          export SCRIPT_PORT
          SCRIPT_PORT=$(jq -r .port "$CONN_FILE")
          export SCRIPT_WORKSPACE
          SCRIPT_WORKSPACE=$(jq -r .workspace "$CONN_FILE")
          if [ -n "$SCRIPT_PORT" ] && [ -n "$SCRIPT_WORKSPACE" ]; then
            return 0 # Success
          fi
        fi
      done
    fi
  done

  return 1 # Failure
}

# --- Main Script ---

if [[ "$1" == "--help" || "$1" == "-h" || "$1" == "help" ]]; then
  print_usage
  exit 0
fi

CLI_NAME=$1
shift

if [[ "$CLI_NAME" != "gemini" && "$CLI_NAME" != "qwen" ]]; then
  echo "Error: Invalid CLI name. Must be 'gemini' or 'qwen'." >&2
  print_usage
  exit 1
fi

ORIGINAL_CLI_PATH=""
if [[ "$1" == "--path" ]]; then
  ORIGINAL_CLI_PATH="$2"
  shift 2
fi

if [ -z "$ORIGINAL_CLI_PATH" ]; then
  ORIGINAL_CLI_PATH=$(which "$CLI_NAME")
  if [ -z "$ORIGINAL_CLI_PATH" ]; then
    echo "Error: Could not find '$CLI_NAME' in your PATH. Use --path to specify the location." >&2
    exit 1
  fi
fi

if find_nvim_session; then
  # Connected session found, variables are exported by the function
  if [ "$CLI_NAME" = "qwen" ]; then
    exec env TERM_PROGRAM=vscode QWEN_CODE_IDE_SERVER_PORT=$SCRIPT_PORT \
      QWEN_CODE_IDE_WORKSPACE_PATH=$SCRIPT_WORKSPACE "$ORIGINAL_CLI_PATH" "$@"
  else
    exec env TERM_PROGRAM=vscode GEMINI_CLI_IDE_SERVER_PORT=$SCRIPT_PORT \
      GEMINI_CLI_IDE_WORKSPACE_PATH=$SCRIPT_WORKSPACE "$ORIGINAL_CLI_PATH" "$@"
  fi
else
  # Fallback: Execute the original command
  exec "$ORIGINAL_CLI_PATH" "$@"
fi
