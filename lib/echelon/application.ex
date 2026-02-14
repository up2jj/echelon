defmodule Echelon.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    setup_distributed_node()

    # Base children that always start
    base_children = [
      # Client GenServer for buffering and sending logs
      Echelon.Client,
      # Connector GenServer for auto-discovering the console
      Echelon.Client.Connector
    ]

    # Only start Console.Server on nodes explicitly named "echelon"
    # This prevents conflicts when multiple apps include Echelon as a dependency
    children = if console_node?() do
      base_children ++ [Echelon.Console.Server]
    else
      base_children
    end

    opts = [strategy: :one_for_one, name: Echelon.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp console_node? do
    node_name = Node.self() |> to_string()
    String.starts_with?(node_name, "echelon@")
  end

  defp setup_distributed_node do
    cookie = Application.get_env(:echelon, :cookie, :echelon)

    if Node.alive?() do
      Node.set_cookie(cookie)
      IO.puts("\n" <> IO.ANSI.green() <> "✓ Echelon started on node: #{node()}" <> IO.ANSI.reset())

      if console_node?() do
        IO.puts(IO.ANSI.cyan() <> "🔍 Echelon Console Ready" <> IO.ANSI.reset())
        IO.puts("Waiting for log entries from connected applications...\n")
      end
    else
      IO.puts("\n" <> IO.ANSI.yellow() <> "⚠ Not running as distributed node." <> IO.ANSI.reset())
      IO.puts(IO.ANSI.yellow() <> "  Console features disabled. Start with: iex --sname <name> -S mix" <> IO.ANSI.reset() <> "\n")
    end
  end
end
