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
end
