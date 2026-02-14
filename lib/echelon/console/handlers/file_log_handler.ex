defmodule Echelon.Console.Handlers.FileLogHandler do
  @moduledoc """
  Handler for writing log entries to files with automatic rotation.

  This handler manages file I/O operations including opening, writing,
  rotating, and cleaning up log files. Files are rotated when they exceed
  configured size or entry count limits.

  ## Configuration

  Configure via Application environment:

      config :echelon,
        file: [
          enabled: false,           # Start disabled, enable via API
          path: nil,                # File path (nil = not configured)
          max_entries: 10_000,      # Rotate after N entries
          max_bytes: 10_485_760,    # Rotate after 10MB
          max_backups: 5            # Keep 5 backup files
        ]

  ## State Structure

  The handler maintains state with these fields:

  - `enabled` - Boolean indicating if handler is active
  - `path` - String path to the log file
  - `io_device` - File handle (IO.device) or nil
  - `entry_count` - Integer count of entries since last rotation
  - `byte_count` - Integer bytes written since last rotation
  - `max_entries` - Integer threshold for rotation by entry count
  - `max_bytes` - Integer threshold for rotation by size
  - `max_backups` - Integer number of backup files to keep

  """

  @behaviour Echelon.Console.LogHandler

  require Logger

  @impl true
  def init do
    config = Application.get_env(:echelon, :file, [])

    %{
      enabled: false,
      path: Keyword.get(config, :path),
      io_device: nil,
      entry_count: 0,
      byte_count: 0,
      max_entries: Keyword.get(config, :max_entries, 10_000),
      max_bytes: Keyword.get(config, :max_bytes, 10_485_760),
      max_backups: Keyword.get(config, :max_backups, 5)
    }
  end

  @impl true
  def enable(state) do
    if state.path do
      case open_log_file(state.path) do
        {:ok, io_device} ->
          {:ok, %{
            state
            | enabled: true,
              io_device: io_device,
              entry_count: 0,
              byte_count: 0
          }}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :no_path_configured}
    end
  end

  @impl true
  def disable(state) do
    state = close_file_if_open(state)
    {:ok, %{state | enabled: false}}
  end

  @impl true
  def handle_entry(entry, state) do
    formatted = Echelon.Console.FileDisplay.format_entry(entry)
    byte_size = byte_size(formatted)

    case IO.write(state.io_device, formatted) do
      :ok ->
        new_count = state.entry_count + 1
        new_bytes = state.byte_count + byte_size

        state = %{
          state
          | entry_count: new_count,
            byte_count: new_bytes
        }

        # Check if rotation is needed
        if should_rotate?(state) do
          case rotate_file(state) do
            {:ok, rotated_state} -> {:ok, rotated_state}
            {:error, reason} -> {:error, reason}
          end
        else
          {:ok, state}
        end

      {:error, reason} ->
        Logger.error("Echelon file write failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def enabled?(state) do
    state.enabled and state.io_device != nil
  end

  @impl true
  def terminate(state) do
    close_file_if_open(state)
    :ok
  end

  ## Private Functions - File Operations

  # Open a log file for writing
  defp open_log_file(path) do
    File.open(path, [:write, :utf8, :append])
  end

  # Close file if it's open
  defp close_file_if_open(state) do
    if state.io_device do
      File.close(state.io_device)
    end

    %{state | io_device: nil}
  end

  # Check if file rotation is needed
  defp should_rotate?(state) do
    entry_limit_exceeded? =
      state.max_entries && state.entry_count >= state.max_entries

    size_limit_exceeded? =
      state.max_bytes && state.byte_count >= state.max_bytes

    entry_limit_exceeded? or size_limit_exceeded?
  end

  # Rotate the log file
  defp rotate_file(state) do
    # Close current file
    if state.io_device do
      File.close(state.io_device)
    end

    # Shift existing backups: .4 -> .5, .3 -> .4, etc.
    for i <- (state.max_backups - 1)..1//-1 do
      old_backup = "#{state.path}.#{i}"
      new_backup = "#{state.path}.#{i + 1}"

      if File.exists?(old_backup) do
        File.rename(old_backup, new_backup)
      end
    end

    # Rename current file to .1
    if File.exists?(state.path) do
      File.rename(state.path, "#{state.path}.1")
    end

    # Delete backups beyond max_backups
    cleanup_old_backups(state.path, state.max_backups)

    # Open new file
    case open_log_file(state.path) do
      {:ok, io_device} ->
        {:ok, %{
          state
          | io_device: io_device,
            entry_count: 0,
            byte_count: 0
        }}

      {:error, reason} ->
        Logger.error("Echelon file rotation failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Remove backup files beyond the maximum number to keep
  defp cleanup_old_backups(base_path, max_backups) do
    # Delete files numbered beyond max_backups
    for i <- (max_backups + 1)..100 do
      backup_path = "#{base_path}.#{i}"

      if File.exists?(backup_path) do
        File.rm(backup_path)
      end
    end
  end
end
