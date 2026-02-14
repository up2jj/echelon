defmodule EchelonTest do
  use ExUnit.Case
  doctest Echelon

  test "info/2 sends log entry" do
    # Should not raise an error
    assert Echelon.info("test message") == :ok
  end

  test "debug/2 sends log entry" do
    assert Echelon.debug("debug message", key: "value") == :ok
  end

  test "warn/2 sends log entry" do
    assert Echelon.warn("warning message") == :ok
  end

  test "error/2 sends log entry" do
    assert Echelon.error("error message", reason: :test) == :ok
  end

  test "lazy evaluation works" do
    assert Echelon.info(fn -> "lazy message" end) == :ok
  end

  test "accepts map as metadata" do
    metadata = %{user_id: 123, role: :admin, count: 42}
    assert Echelon.info("test with map", metadata) == :ok
  end

  test "accepts nested map as metadata" do
    metadata = %{
      user: %{id: 123, name: "Alice"},
      request: %{method: "POST", path: "/api/users"},
      metrics: %{duration_ms: 45, db_queries: 3}
    }
    assert Echelon.debug("complex data", metadata) == :ok
  end

  test "accepts list in metadata value" do
    metadata = %{
      tags: ["important", "user", "auth"],
      ids: [1, 2, 3, 4, 5]
    }
    assert Echelon.warn("with lists", metadata) == :ok
  end

  test "accepts struct in metadata" do
    # Using DateTime as an example struct
    now = DateTime.utc_now()
    metadata = %{timestamp: now, user_id: 123}
    assert Echelon.info("with struct", metadata) == :ok
  end

  describe "on/off functionality" do
    test "enabled?/0 returns true by default" do
      assert Echelon.enabled?() == true
    end

    test "off/0 disables logging" do
      Echelon.off()
      assert Echelon.enabled?() == false
      Echelon.on()  # Cleanup
    end

    test "on/0 enables logging" do
      Echelon.off()
      Echelon.on()
      assert Echelon.enabled?() == true
    end

    test "on/0 returns :ok" do
      assert Echelon.on() == :ok
    end

    test "off/0 returns :ok" do
      assert Echelon.off() == :ok
    end

    test "logs are sent when enabled" do
      Echelon.on()
      assert Echelon.info("test message") == :ok
    end

    test "logs are dropped when disabled" do
      Echelon.off()
      assert Echelon.info("test message") == :ok
      Echelon.on()  # Cleanup
    end

    test "on/off/on cycle works correctly" do
      assert Echelon.enabled?() == true

      Echelon.off()
      assert Echelon.enabled?() == false

      Echelon.on()
      assert Echelon.enabled?() == true
    end

    test "on/off updates Application config" do
      Echelon.on()
      assert Application.get_env(:echelon, :enabled) == true

      Echelon.off()
      assert Application.get_env(:echelon, :enabled) == false

      Echelon.on()
      assert Application.get_env(:echelon, :enabled) == true
    end
  end

  describe "group/2" do
    test "returns function result" do
      result = Echelon.group("test", fn -> 42 end)
      assert result == 42
    end

    test "returns :ok for successful group with logs" do
      assert Echelon.group("transaction", fn ->
        Echelon.info("step 1")
        Echelon.debug("step 2")
        :ok
      end) == :ok
    end

    test "preserves string return values" do
      result = Echelon.group("test", fn -> "hello" end)
      assert result == "hello"
    end

    test "preserves map return values" do
      result = Echelon.group("test", fn -> %{status: :ok, data: 123} end)
      assert result == %{status: :ok, data: 123}
    end

    test "nested groups work correctly" do
      result = Echelon.group("outer", fn ->
        Echelon.info("outer message")

        inner_result = Echelon.group("inner", fn ->
          Echelon.debug("inner message")
          :inner_result
        end)

        assert inner_result == :inner_result
        :outer_result
      end)

      assert result == :outer_result
    end

    test "deeply nested groups (3 levels)" do
      result = Echelon.group("level1", fn ->
        Echelon.group("level2", fn ->
          Echelon.group("level3", fn ->
            Echelon.info("deeply nested")
            :deep
          end)
        end)
      end)

      assert result == :deep
    end

    test "cleans up stack on error" do
      # Ensure group stack is empty before test
      Process.delete(:echelon_group_stack)

      assert_raise RuntimeError, "test error", fn ->
        Echelon.group("failing", fn ->
          Echelon.info("before error")
          raise "test error"
        end)
      end

      # Verify stack was cleaned up
      assert Process.get(:echelon_group_stack, []) == []
    end

    test "cleans up stack on nested group error" do
      Process.delete(:echelon_group_stack)

      assert_raise RuntimeError, "nested error", fn ->
        Echelon.group("outer", fn ->
          Echelon.info("outer message")

          Echelon.group("inner", fn ->
            Echelon.info("about to fail")
            raise "nested error"
          end)
        end)
      end

      # Verify stack was cleaned up
      assert Process.get(:echelon_group_stack, []) == []
    end

    test "group state doesn't leak between processes" do
      parent = self()

      # Start group in parent
      Echelon.group("parent_group", fn ->
        Echelon.info("in parent")

        # Spawn child process
        Task.async(fn ->
          # Child should have empty group stack
          stack = Process.get(:echelon_group_stack, [])
          send(parent, {:child_stack, stack})

          Echelon.info("child message")
        end)
        |> Task.await()

        # Parent should still have group
        parent_stack = Process.get(:echelon_group_stack, [])
        send(parent, {:parent_stack, parent_stack})
      end)

      assert_receive {:child_stack, []}
      assert_receive {:parent_stack, ["parent_group"]}
    end

    test "multiple sequential groups work" do
      result1 = Echelon.group("group1", fn ->
        Echelon.info("in group1")
        :result1
      end)

      # Stack should be clean between groups
      assert Process.get(:echelon_group_stack, []) == []

      result2 = Echelon.group("group2", fn ->
        Echelon.info("in group2")
        :result2
      end)

      # Stack should be clean after all groups
      assert Process.get(:echelon_group_stack, []) == []

      assert result1 == :result1
      assert result2 == :result2
    end

    test "empty group works" do
      result = Echelon.group("empty", fn -> nil end)
      assert result == nil
      assert Process.get(:echelon_group_stack, []) == []
    end

    test "group with only metadata logs" do
      result = Echelon.group("metadata_test", fn ->
        Echelon.info("test", %{key: "value", count: 42})
        :done
      end)

      assert result == :done
    end

    test "group preserves lazy message evaluation" do
      result = Echelon.group("lazy_test", fn ->
        Echelon.debug(fn -> "lazy message" end)
        :lazy_done
      end)

      assert result == :lazy_done
    end
  end
end
