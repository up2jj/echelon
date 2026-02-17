defmodule Echelon.Client do
  @moduledoc false
  # GenServer for buffering and sending log entries to the console

  use GenServer
  require Logger

  @default_buffer_size 1000
  @default_fallback :buffer

  ## Client API

  @doc """
  Starts the Echelon client GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Sends a log entry to the console (or buffers it if disconnected).
  """
  def send_log(entry) do
    GenServer.cast(__MODULE__, {:send_log, entry})
  end

  @doc """
  Enables logging. Returns :ok.
  """
  def enable do
    Application.put_env(:echelon, :enabled, true)
  end

  @doc """
  Disables logging. Returns :ok.
  """
  def disable do
    Application.put_env(:echelon, :enabled, false)
  end

  @doc """
  Returns whether logging is currently enabled.
  """
  def enabled? do
    Application.get_env(:echelon, :enabled, true)
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    state = %{
      console_pid: nil,
      buffer: [],
      buffer_size: Application.get_env(:echelon, :buffer_size, @default_buffer_size),
      fallback: Application.get_env(:echelon, :fallback, @default_fallback)
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:send_log, entry}, state) do
    # Check if logging is enabled in Application config
    enabled = Application.get_env(:echelon, :enabled, true)

    if not enabled do
      # Drop logs silently when disabled
      {:noreply, state}
    else
      # Special handling for ping entries - determine pong vs pang
      entry = if entry[:group_marker] == :ping do
        response = if state.console_pid, do: "pong", else: "pang"
        %{entry | message: response}
      else
        entry
      end

      case state.console_pid do
        nil ->
          # Console not connected - apply fallback strategy
          handle_disconnected(entry, state)

        pid ->
          # Send to console immediately
          GenServer.cast(pid, {:log_entry, entry})
          {:noreply, state}
      end
    end
  end

  @impl true
  def handle_info({:console_connected, pid}, state) do
    # Console connected - monitor it and flush buffer
    Process.monitor(pid)

    # Flush buffered logs in order (reverse because we prepend)
    state.buffer
    |> Enum.reverse()
    |> Enum.each(fn entry ->
      GenServer.cast(pid, {:log_entry, entry})
    end)

    {:noreply, %{state | console_pid: pid, buffer: []}}
  end

  @impl true
  def handle_info({:console_disconnected}, state) do
    # Console disconnected - clear the pid
    {:noreply, %{state | console_pid: nil}}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, %{console_pid: pid} = state) do
    # Console process died - clear the pid
    {:noreply, %{state | console_pid: nil}}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  ## Private Functions

  defp handle_disconnected(entry, state) do
    case state.fallback do
      :buffer ->
        # Buffer the log entry (FIFO with max size)
        buffer = buffer_log(entry, state.buffer, state.buffer_size)
        {:noreply, %{state | buffer: buffer}}

      :logger ->
        # Fall back to standard Logger
        Logger.log(entry.level, entry.message, entry.metadata)
        {:noreply, state}

      :silent ->
        # Drop silently
        {:noreply, state}

      _ ->
        # Unknown fallback, default to buffer
        buffer = buffer_log(entry, state.buffer, state.buffer_size)
        {:noreply, %{state | buffer: buffer}}
    end
  end

  defp buffer_log(entry, buffer, max_size) do
    # Prepend new entry and limit size (keeps most recent)
    new_buffer = [entry | buffer]

    if length(new_buffer) > max_size do
      Enum.take(new_buffer, max_size)
    else
      new_buffer
    end
  end
end
