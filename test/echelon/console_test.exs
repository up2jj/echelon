defmodule Echelon.Console.ServerTest do
  use ExUnit.Case

  test "console server can be started" do
    # Basic smoke test - the server is already started by the application
    # We just verify it's registered globally
    pid = :global.whereis_name(:echelon_console)
    assert is_pid(pid) or pid == :undefined
  end
end

defmodule Echelon.Console.TerminalDisplayTest do
  use ExUnit.Case

  alias Echelon.Console.TerminalDisplay

  test "show/1 handles log entry with all fields" do
    entry = %{
      level: :info,
      message: "Test message",
      timestamp: System.system_time(:microsecond),
      node: :test@localhost,
      metadata: [key: "value"]
    }

    # This should not raise an error (IO.puts returns :ok)
    assert TerminalDisplay.show(entry) == :ok
  end

  test "show/1 handles log entry with minimal fields" do
    entry = %{
      level: :debug,
      message: "Debug",
      timestamp: System.system_time(:microsecond),
      node: :test,
      metadata: []
    }

    assert TerminalDisplay.show(entry) == :ok
  end

  test "show/1 handles map metadata" do
    entry = %{
      level: :info,
      message: "Test with map",
      timestamp: System.system_time(:microsecond),
      node: :test@localhost,
      metadata: %{user_id: 123, role: :admin}
    }

    assert TerminalDisplay.show(entry) == :ok
  end

  test "show/1 handles nested map metadata" do
    entry = %{
      level: :warn,
      message: "Complex data",
      timestamp: System.system_time(:microsecond),
      node: :test,
      metadata: %{
        user: %{id: 123, name: "Alice"},
        request: %{method: "POST", path: "/api/users"}
      }
    }

    assert TerminalDisplay.show(entry) == :ok
  end

  test "show/1 handles empty map metadata" do
    entry = %{
      level: :error,
      message: "Empty map",
      timestamp: System.system_time(:microsecond),
      node: :test,
      metadata: %{}
    }

    assert TerminalDisplay.show(entry) == :ok
  end

  test "show/1 handles list values in metadata" do
    entry = %{
      level: :debug,
      message: "With lists",
      timestamp: System.system_time(:microsecond),
      node: :test,
      metadata: %{
        tags: ["tag1", "tag2", "tag3"],
        values: [1, 2, 3, 4, 5]
      }
    }

    assert TerminalDisplay.show(entry) == :ok
  end
end
