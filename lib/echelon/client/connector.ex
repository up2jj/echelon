defmodule Echelon.Client.Connector do
  @moduledoc false
  # GenServer for auto-discovering and connecting to the Echelon console

  use GenServer
  require Logger

  @discovery_interval 5_000  # Try to connect every 5 seconds
  @console_name :echelon_console

  ## Client API

  @doc """
  Starts the connector GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    # Ensure we're running as a distributed node
    ensure_distributed_node()

    # Try immediate connection
    send(self(), :discover_console)

    state = %{
      console_pid: nil,
      retry_timer: nil
    }

    {:ok, state}
  end

  @impl true
  def handle_info(:discover_console, state) do
    # Cancel any existing retry timer
    if state.retry_timer, do: Process.cancel_timer(state.retry_timer)

    case discover_console() do
      {:ok, pid} ->
        # Successfully connected!
        Process.monitor(pid)
        notify_client_connected(pid)
        {:noreply, %{state | console_pid: pid, retry_timer: nil}}

      :error ->
        # Not found, retry later
        timer = Process.send_after(self(), :discover_console, @discovery_interval)
        {:noreply, %{state | retry_timer: timer}}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, %{console_pid: pid} = state) do
    # Console disconnected, start rediscovery
    notify_client_disconnected()
    send(self(), :discover_console)
    {:noreply, %{state | console_pid: nil}}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  ## Private Functions

  defp discover_console do
    # First try: lookup in global registry
    case :global.whereis_name(@console_name) do
      :undefined ->
        # Second try: connect to known node names and lookup again
        try_connect_to_known_nodes()

      pid when is_pid(pid) ->
        {:ok, pid}
    end
  end

  defp try_connect_to_known_nodes do
    # Generate possible node names based on current hostname
    known_node_names = generate_known_node_names()

    Enum.find_value(known_node_names, :error, fn node_name ->
      case Node.connect(node_name) do
        true ->
          # Connected! Now try to find the console
          case :global.whereis_name(@console_name) do
            :undefined -> false
            pid when is_pid(pid) -> {:ok, pid}
          end

        false ->
          # Connection failed
          false

        :ignored ->
          # Node is local or already connected, try to find console anyway
          case :global.whereis_name(@console_name) do
            :undefined -> false
            pid when is_pid(pid) -> {:ok, pid}
          end
      end
    end)
  end

  defp generate_known_node_names do
    # Get the current node's hostname
    current_host =
      case Node.self() do
        :nonode@nohost -> "localhost"
        node ->
          node
          |> Atom.to_string()
          |> String.split("@")
          |> List.last()
      end

    # Try multiple variations
    [
      :"echelon@#{current_host}",
      :"echelon@localhost"
    ]
    |> Enum.uniq()
  end

  defp ensure_distributed_node do
    cookie = Application.get_env(:echelon, :cookie, :echelon)

    case Node.alive?() do
      true ->
        # Already running as distributed node
        Node.set_cookie(cookie)
        :ok

      false ->
        # Not running as distributed node - won't be able to connect to console
        # This is okay, the app will still work, just without Echelon
        :ok
    end
  end

  defp notify_client_connected(pid) do
    send(Echelon.Client, {:console_connected, pid})
  end

  defp notify_client_disconnected do
    send(Echelon.Client, {:console_disconnected})
  end
end
