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

    state = %{
      display: display,
      connected_nodes: MapSet.new(),
      log_count: 0
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:log_entry, entry}, state) do
    # Display the log entry
    state.display.show(entry)

    # Track connected nodes
    node_name = entry[:node] || :unknown
    connected_nodes = MapSet.put(state.connected_nodes, node_name)

    {:noreply, %{state | connected_nodes: connected_nodes, log_count: state.log_count + 1}}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
