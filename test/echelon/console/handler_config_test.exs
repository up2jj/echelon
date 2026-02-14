defmodule Echelon.Console.HandlerConfigTest do
  use ExUnit.Case, async: false

  # Test handler for custom handler scenarios
  defmodule TestHandler do
    @behaviour Echelon.Console.LogHandler

    @impl true
    def init(opts \\ []) do
      %{
        enabled: false,
        count: 0,
        opts: opts,
        custom_option: Keyword.get(opts, :custom_option, "default")
      }
    end

    @impl true
    def enable(state) do
      {:ok, %{state | enabled: true}}
    end

    @impl true
    def disable(state) do
      {:ok, %{state | enabled: false}}
    end

    @impl true
    def handle_entry(_entry, state) do
      {:ok, %{state | count: state.count + 1}}
    end

    @impl true
    def enabled?(state) do
      state.enabled
    end
  end

  setup do
    # Clear any existing config
    Application.delete_env(:echelon, :handlers)

    on_exit(fn ->
      # Clean up
      Application.delete_env(:echelon, :handlers)
    end)

    :ok
  end

  describe "zero config initialization" do
    test "initializes with default file handler (disabled)" do
      {:ok, pid} = Echelon.Console.Server.start_link([])

      handlers = GenServer.call(pid, :list_handlers)

      assert Map.has_key?(handlers, :file)
      assert handlers.file.module == Echelon.Console.Handlers.FileLogHandler
      assert handlers.file.enabled == false

      GenServer.stop(pid)
    end
  end

  describe "single handler configuration" do
    test "initializes file handler with custom config" do
      Application.put_env(:echelon, :handlers, [
        {:file, Echelon.Console.Handlers.FileLogHandler,
         [enabled: false, path: "test.log", max_entries: 5000]}
      ])

      {:ok, pid} = Echelon.Console.Server.start_link([])

      handlers = GenServer.call(pid, :list_handlers)

      assert Map.has_key?(handlers, :file)
      assert handlers.file.module == Echelon.Console.Handlers.FileLogHandler
      assert handlers.file.enabled == false

      # Check that the config was passed to init
      state = :sys.get_state(pid)
      {_module, file_state} = state.handlers.file
      assert file_state.path == "test.log"
      assert file_state.max_entries == 5000

      GenServer.stop(pid)
    end

    test "file handler can be auto-enabled with path" do
      # Create a temp file path
      temp_path = Path.join(System.tmp_dir!(), "echelon_test_#{:rand.uniform(10000)}.log")

      Application.put_env(:echelon, :handlers, [
        {:file, Echelon.Console.Handlers.FileLogHandler, [enabled: true, path: temp_path]}
      ])

      {:ok, pid} = Echelon.Console.Server.start_link([])

      handlers = GenServer.call(pid, :list_handlers)
      assert handlers.file.enabled == true

      GenServer.stop(pid)
      File.rm(temp_path)
    end
  end

  describe "multiple handlers configuration" do
    test "initializes multiple handlers with different configs" do
      Application.put_env(:echelon, :handlers, [
        {:file, Echelon.Console.Handlers.FileLogHandler, [enabled: false, path: nil]},
        {:test, TestHandler, [enabled: false, custom_option: "test_value"]}
      ])

      {:ok, pid} = Echelon.Console.Server.start_link([])

      handlers = GenServer.call(pid, :list_handlers)

      assert Map.has_key?(handlers, :file)
      assert Map.has_key?(handlers, :test)

      assert handlers.file.module == Echelon.Console.Handlers.FileLogHandler
      assert handlers.test.module == TestHandler

      # Check that custom opts were passed
      state = :sys.get_state(pid)
      {_module, test_state} = state.handlers.test
      assert test_state.custom_option == "test_value"

      GenServer.stop(pid)
    end

    test "custom handler without file handler still gets file handler added" do
      Application.put_env(:echelon, :handlers, [
        {:test, TestHandler, [enabled: false]}
      ])

      {:ok, pid} = Echelon.Console.Server.start_link([])

      handlers = GenServer.call(pid, :list_handlers)

      # File handler should be automatically added
      assert Map.has_key?(handlers, :file)
      assert Map.has_key?(handlers, :test)

      GenServer.stop(pid)
    end
  end

  describe "auto-enable functionality" do
    test "handlers with enabled: true are auto-enabled" do
      Application.put_env(:echelon, :handlers, [
        {:test, TestHandler, [enabled: true, custom_option: "enabled"]}
      ])

      {:ok, pid} = Echelon.Console.Server.start_link([])

      handlers = GenServer.call(pid, :list_handlers)
      assert handlers.test.enabled == true

      GenServer.stop(pid)
    end

    test "handlers with enabled: false remain disabled" do
      Application.put_env(:echelon, :handlers, [
        {:test, TestHandler, [enabled: false]}
      ])

      {:ok, pid} = Echelon.Console.Server.start_link([])

      handlers = GenServer.call(pid, :list_handlers)
      assert handlers.test.enabled == false

      GenServer.stop(pid)
    end

    test "handlers without enabled option default to disabled" do
      Application.put_env(:echelon, :handlers, [
        {:test, TestHandler, [custom_option: "no_enabled"]}
      ])

      {:ok, pid} = Echelon.Console.Server.start_link([])

      handlers = GenServer.call(pid, :list_handlers)
      assert handlers.test.enabled == false

      GenServer.stop(pid)
    end
  end

  describe "handler receives correct opts" do
    test "handler init/1 receives all configured options" do
      Application.put_env(:echelon, :handlers, [
        {:test, TestHandler,
         [enabled: false, custom_option: "value1", another_option: 123, third: :atom]}
      ])

      {:ok, pid} = Echelon.Console.Server.start_link([])

      state = :sys.get_state(pid)
      {_module, test_state} = state.handlers.test

      # Check that all opts were received
      assert Keyword.get(test_state.opts, :custom_option) == "value1"
      assert Keyword.get(test_state.opts, :another_option) == 123
      assert Keyword.get(test_state.opts, :third) == :atom

      GenServer.stop(pid)
    end

    test "handler init/1 receives empty list when no opts" do
      Application.put_env(:echelon, :handlers, [
        {:test, TestHandler, []}
      ])

      {:ok, pid} = Echelon.Console.Server.start_link([])

      state = :sys.get_state(pid)
      {_module, test_state} = state.handlers.test

      assert test_state.opts == []
      assert test_state.custom_option == "default"

      GenServer.stop(pid)
    end
  end

  describe "runtime handler management" do
    test "enable_handler/1 enables a disabled handler" do
      Application.put_env(:echelon, :handlers, [
        {:test, TestHandler, [enabled: false]}
      ])

      {:ok, pid} = Echelon.Console.Server.start_link([])

      # Initially disabled
      handlers = GenServer.call(pid, :list_handlers)
      assert handlers.test.enabled == false

      # Enable it
      assert :ok == GenServer.call(pid, {:enable_handler, :test})

      # Now enabled
      handlers = GenServer.call(pid, :list_handlers)
      assert handlers.test.enabled == true

      GenServer.stop(pid)
    end

    test "disable_handler/1 disables an enabled handler" do
      Application.put_env(:echelon, :handlers, [
        {:test, TestHandler, [enabled: true]}
      ])

      {:ok, pid} = Echelon.Console.Server.start_link([])

      # Initially enabled
      handlers = GenServer.call(pid, :list_handlers)
      assert handlers.test.enabled == true

      # Disable it
      assert :ok == GenServer.call(pid, {:disable_handler, :test})

      # Now disabled
      handlers = GenServer.call(pid, :list_handlers)
      assert handlers.test.enabled == false

      GenServer.stop(pid)
    end

    test "enable_handler/1 returns error for non-existent handler" do
      {:ok, pid} = Echelon.Console.Server.start_link([])

      assert {:error, :handler_not_found} ==
               GenServer.call(pid, {:enable_handler, :nonexistent})

      GenServer.stop(pid)
    end

    test "disable_handler/1 returns error for non-existent handler" do
      {:ok, pid} = Echelon.Console.Server.start_link([])

      assert {:error, :handler_not_found} ==
               GenServer.call(pid, {:disable_handler, :nonexistent})

      GenServer.stop(pid)
    end
  end

  describe "handler state persistence" do
    test "handler maintains state across multiple handle_entry calls" do
      Application.put_env(:echelon, :handlers, [
        {:test, TestHandler, [enabled: true, custom_option: "persist"]}
      ])

      {:ok, pid} = Echelon.Console.Server.start_link([])

      # Get initial state
      state = :sys.get_state(pid)
      {_module, handler_state} = state.handlers.test
      assert handler_state.count == 0

      # Send multiple log entries
      entry1 = build_log_entry("Message 1")
      entry2 = build_log_entry("Message 2")
      entry3 = build_log_entry("Message 3")

      GenServer.cast(pid, {:log_entry, entry1})
      GenServer.cast(pid, {:log_entry, entry2})
      GenServer.cast(pid, {:log_entry, entry3})

      # Wait for async processing
      Process.sleep(50)

      # Check that state was persisted and count incremented
      state = :sys.get_state(pid)
      {_module, handler_state} = state.handlers.test
      assert handler_state.count == 3
      assert handler_state.custom_option == "persist"

      GenServer.stop(pid)
    end

    test "handler state updated correctly after enable/disable cycles" do
      Application.put_env(:echelon, :handlers, [
        {:test, TestHandler, [enabled: false]}
      ])

      {:ok, pid} = Echelon.Console.Server.start_link([])

      # Enable handler
      assert :ok == GenServer.call(pid, {:enable_handler, :test})

      # Send some entries
      entry = build_log_entry("Test message")
      GenServer.cast(pid, {:log_entry, entry})
      GenServer.cast(pid, {:log_entry, entry})
      Process.sleep(50)

      # Get count
      state = :sys.get_state(pid)
      {_module, handler_state} = state.handlers.test
      count_before_disable = handler_state.count
      assert count_before_disable == 2

      # Disable handler
      assert :ok == GenServer.call(pid, {:disable_handler, :test})

      # Send more entries (should not be counted)
      GenServer.cast(pid, {:log_entry, entry})
      GenServer.cast(pid, {:log_entry, entry})
      Process.sleep(50)

      # Count should remain the same
      state = :sys.get_state(pid)
      {_module, handler_state} = state.handlers.test
      assert handler_state.count == count_before_disable

      # Re-enable handler
      assert :ok == GenServer.call(pid, {:enable_handler, :test})

      # Send more entries (should be counted again)
      GenServer.cast(pid, {:log_entry, entry})
      Process.sleep(50)

      # Count should increment
      state = :sys.get_state(pid)
      {_module, handler_state} = state.handlers.test
      assert handler_state.count == count_before_disable + 1

      GenServer.stop(pid)
    end

    test "multiple handlers maintain independent state" do
      # Define a second test handler module
      defmodule SecondTestHandler do
        @behaviour Echelon.Console.LogHandler

        def init(opts \\ []) do
          %{
            enabled: false,
            value: Keyword.get(opts, :value, 0)
          }
        end

        def enable(state), do: {:ok, %{state | enabled: true}}
        def disable(state), do: {:ok, %{state | enabled: false}}

        def handle_entry(_entry, state) do
          {:ok, %{state | value: state.value + 10}}
        end

        def enabled?(state), do: state.enabled
      end

      Application.put_env(:echelon, :handlers, [
        {:test1, TestHandler, [enabled: true, custom_option: "handler1"]},
        {:test2, SecondTestHandler, [enabled: true, value: 100]}
      ])

      {:ok, pid} = Echelon.Console.Server.start_link([])

      # Send log entries
      entry = build_log_entry("Test")
      GenServer.cast(pid, {:log_entry, entry})
      GenServer.cast(pid, {:log_entry, entry})
      Process.sleep(50)

      # Check that each handler maintained its own state
      state = :sys.get_state(pid)

      {_mod1, handler1_state} = state.handlers.test1
      assert handler1_state.count == 2
      assert handler1_state.custom_option == "handler1"

      {_mod2, handler2_state} = state.handlers.test2
      assert handler2_state.value == 120
      # 100 + 10 + 10

      GenServer.stop(pid)
    end
  end

  describe "handler options edge cases" do
    test "handler with empty options list" do
      Application.put_env(:echelon, :handlers, [
        {:test, TestHandler, []}
      ])

      {:ok, pid} = Echelon.Console.Server.start_link([])

      state = :sys.get_state(pid)
      {_module, handler_state} = state.handlers.test

      # Should use defaults
      assert handler_state.custom_option == "default"
      assert handler_state.opts == []

      GenServer.stop(pid)
    end

    test "handler with unknown options is ignored gracefully" do
      Application.put_env(:echelon, :handlers, [
        {:test, TestHandler, [
          enabled: false,
          custom_option: "value",
          unknown_option: "ignored",
          another_unknown: 123
        ]}
      ])

      {:ok, pid} = Echelon.Console.Server.start_link([])

      state = :sys.get_state(pid)
      {_module, handler_state} = state.handlers.test

      # Handler should initialize successfully
      assert handler_state.custom_option == "value"

      # Unknown options are in opts but don't cause errors
      assert Keyword.has_key?(handler_state.opts, :unknown_option)
      assert Keyword.has_key?(handler_state.opts, :another_unknown)

      GenServer.stop(pid)
    end

    test "handler options override defaults correctly" do
      # First handler with defaults
      Application.put_env(:echelon, :handlers, [
        {:test1, TestHandler, []}
      ])

      {:ok, pid1} = Echelon.Console.Server.start_link([])
      state1 = :sys.get_state(pid1)
      {_mod1, handler1_state} = state1.handlers.test1
      assert handler1_state.custom_option == "default"
      GenServer.stop(pid1)

      # Second handler with custom option
      Application.put_env(:echelon, :handlers, [
        {:test2, TestHandler, [custom_option: "overridden"]}
      ])

      {:ok, pid2} = Echelon.Console.Server.start_link([])
      state2 = :sys.get_state(pid2)
      {_mod2, handler2_state} = state2.handlers.test2
      assert handler2_state.custom_option == "overridden"
      GenServer.stop(pid2)
    end

    test "handler with nil values in options" do
      Application.put_env(:echelon, :handlers, [
        {:test, TestHandler, [custom_option: nil, enabled: false]}
      ])

      {:ok, pid} = Echelon.Console.Server.start_link([])

      state = :sys.get_state(pid)
      {_module, handler_state} = state.handlers.test

      # nil should be accepted as a value
      assert handler_state.custom_option == nil

      GenServer.stop(pid)
    end
  end

  # Helper function for building log entries
  defp build_log_entry(message) do
    %{
      level: :info,
      message: message,
      metadata: [],
      timestamp: System.system_time(:microsecond),
      node: node(),
      pid: self(),
      group_depth: 0,
      group_name: nil,
      group_marker: nil
    }
  end
end
