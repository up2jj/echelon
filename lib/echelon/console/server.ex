defmodule Echelon.Console.Server do
  @moduledoc false
  # Main console server that receives and displays log entries

  use GenServer

  @console_name :echelon_console

  ## Client API

  @doc """
  Starts the console server.

  If another node has already registered the console globally, this will
  fail silently - which is expected when multiple apps include Echelon.
  """
  def start_link(opts \\ []) do
    # Check if console is already registered before attempting to start
    case :global.whereis_name(@console_name) do
      :undefined ->
        # Not registered yet, try to start and register
        case GenServer.start_link(__MODULE__, opts, name: {:global, @console_name}) do
          {:ok, pid} ->
            {:ok, pid}
          {:error, {:already_started, _pid}} ->
            # Another node registered between check and start
            :ignore
        end
      _pid ->
        # Already registered by another node, skip starting
        :ignore
    end
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient  # Don't restart if terminated due to global conflicts
    }
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    display = Application.get_env(:echelon, :display, Echelon.Console.TerminalDisplay)

    # Initialize file handler
    file_handler_state = Echelon.Console.Handlers.FileLogHandler.init()

    # Auto-enable if configured with a path
    file_config = Application.get_env(:echelon, :file, [])
    file_enabled = Keyword.get(file_config, :enabled, false)

    file_handler_state =
      if file_enabled and file_handler_state.path do
        case Echelon.Console.Handlers.FileLogHandler.enable(file_handler_state) do
          {:ok, enabled_state} -> enabled_state
          {:error, _} -> %{file_handler_state | enabled: false}
        end
      else
        file_handler_state
      end

    state = %{
      display: display,
      connected_nodes: MapSet.new(),
      log_count: 0,
      handlers: %{
        file: {Echelon.Console.Handlers.FileLogHandler, file_handler_state}
      }
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:log_entry, entry}, state) do
    # Display the log entry to terminal
    state.display.show(entry)

    # Track connected nodes
    node_name = entry[:node] || :unknown
    connected_nodes = MapSet.put(state.connected_nodes, node_name)

    # Delegate to all enabled handlers
    handlers = process_handlers(entry, state.handlers)

    {:noreply, %{
      state
      | connected_nodes: connected_nodes,
        log_count: state.log_count + 1,
        handlers: handlers
    }}
  end

  @impl true
  def handle_call({:configure_file, path}, _from, state) do
    {module, handler_state} = state.handlers.file

    # Disable current handler
    {:ok, disabled_state} = module.disable(handler_state)

    # Update path and enable
    new_handler_state = %{disabled_state | path: path}

    case module.enable(new_handler_state) do
      {:ok, enabled_state} ->
        handlers = Map.put(state.handlers, :file, {module, enabled_state})
        {:reply, :ok, %{state | handlers: handlers}}

      {:error, reason} ->
        handlers = Map.put(state.handlers, :file, {module, new_handler_state})
        {:reply, {:error, reason}, %{state | handlers: handlers}}
    end
  end

  @impl true
  def handle_call(:disable_file, _from, state) do
    {module, handler_state} = state.handlers.file
    {:ok, disabled_state} = module.disable(handler_state)

    new_handler_state = %{disabled_state | path: nil}
    handlers = Map.put(state.handlers, :file, {module, new_handler_state})

    {:reply, :ok, %{state | handlers: handlers}}
  end

  @impl true
  def handle_call(:get_file_path, _from, state) do
    {_module, handler_state} = state.handlers.file
    {:reply, handler_state.path, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    # Terminate all handlers
    Enum.each(state.handlers, fn {_name, {module, handler_state}} ->
      if function_exported?(module, :terminate, 1) do
        module.terminate(handler_state)
      else
        module.disable(handler_state)
      end
    end)

    :ok
  end

  ## Private Functions - Handler Processing

  # Process log entry through all enabled handlers
  defp process_handlers(entry, handlers) do
    Enum.reduce(handlers, handlers, fn {name, {module, handler_state}}, acc ->
      if module.enabled?(handler_state) do
        case module.handle_entry(entry, handler_state) do
          {:ok, new_handler_state} ->
            Map.put(acc, name, {module, new_handler_state})

          {:error, reason} ->
            # Handler failed, disable it
            require Logger
            Logger.warning("Handler #{name} failed, disabling: #{inspect(reason)}")
            {:ok, disabled_state} = module.disable(handler_state)
            Map.put(acc, name, {module, disabled_state})
        end
      else
        acc
      end
    end)
  end
end
