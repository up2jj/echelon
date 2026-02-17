defmodule Echelon.HelpersTest do
  use ExUnit.Case
  doctest Echelon.Helpers

  import Echelon.Helpers

  describe "edebug/1 and edebug/2" do
    test "edebug/1 sends log entry" do
      assert edebug("debug message") == :ok
    end

    test "edebug/2 with keyword metadata sends log entry" do
      assert edebug("debug message", key: "value") == :ok
    end

    test "edebug/2 with map metadata sends log entry" do
      assert edebug("debug message", %{key: "value", count: 42}) == :ok
    end

    test "edebug/1 with lazy evaluation works" do
      assert edebug(fn -> "lazy debug message" end) == :ok
    end
  end

  describe "einfo/1 and einfo/2" do
    test "einfo/1 sends log entry" do
      assert einfo("info message") == :ok
    end

    test "einfo/2 with keyword metadata sends log entry" do
      assert einfo("info message", user_id: 123) == :ok
    end

    test "einfo/2 with map metadata sends log entry" do
      metadata = %{
        user: %{id: 123, name: "Alice"},
        request: %{method: "POST", path: "/api/users"}
      }
      assert einfo("complex data", metadata) == :ok
    end

    test "einfo/1 with lazy evaluation works" do
      assert einfo(fn -> "lazy info message" end) == :ok
    end
  end

  describe "ewarn/1 and ewarn/2" do
    test "ewarn/1 sends log entry" do
      assert ewarn("warning message") == :ok
    end

    test "ewarn/2 with keyword metadata sends log entry" do
      assert ewarn("warning message", reason: :slow_query) == :ok
    end

    test "ewarn/2 with map metadata sends log entry" do
      assert ewarn("warning", %{duration_ms: 1500, threshold: 1000}) == :ok
    end

    test "ewarn/1 with lazy evaluation works" do
      assert ewarn(fn -> "lazy warn message" end) == :ok
    end
  end

  describe "eerror/1 and eerror/2" do
    test "eerror/1 sends log entry" do
      assert eerror("error message") == :ok
    end

    test "eerror/2 with keyword metadata sends log entry" do
      assert eerror("error message", reason: :timeout) == :ok
    end

    test "eerror/2 with map metadata sends log entry" do
      assert eerror("error", %{reason: :timeout, retry_count: 3}) == :ok
    end

    test "eerror/1 with lazy evaluation works" do
      assert eerror(fn -> "lazy error message" end) == :ok
    end
  end

  describe "edge cases" do
    test "accepts nested maps in metadata" do
      metadata = %{
        user: %{id: 123, name: "Alice"},
        request: %{method: "POST", path: "/api/users"},
        metrics: %{duration_ms: 45, db_queries: 3}
      }
      assert einfo("complex data", metadata) == :ok
    end

    test "accepts lists in metadata values" do
      metadata = %{
        tags: ["important", "user", "auth"],
        ids: [1, 2, 3, 4, 5]
      }
      assert ewarn("with lists", metadata) == :ok
    end

    test "accepts structs in metadata" do
      now = DateTime.utc_now()
      metadata = %{timestamp: now, user_id: 123}
      assert einfo("with struct", metadata) == :ok
    end
  end

  describe "on/off helper functions" do
    test "eon/0 enables logging" do
      eoff()
      eon()
      assert eenabled?() == true
    end

    test "eoff/0 disables logging" do
      eoff()
      assert eenabled?() == false
      eon()  # Cleanup
    end

    test "eenabled?/0 returns current state" do
      eon()
      assert eenabled?() == true

      eoff()
      assert eenabled?() == false

      eon()  # Cleanup
    end
  end

  describe "ebench/1 and ebench/2" do
    test "ebench/1 returns the function's return value" do
      assert ebench(fn -> 42 end) == 42
    end

    test "ebench/2 returns the function's return value" do
      assert ebench("label", fn -> :hello end) == :hello
    end

    test "ebench/1 reraises exceptions" do
      assert_raise RuntimeError, "boom", fn ->
        ebench(fn -> raise "boom" end)
      end
    end

    test "ebench/2 reraises exceptions" do
      assert_raise RuntimeError, "boom", fn ->
        ebench("labeled", fn -> raise "boom" end)
      end
    end

    test "ebench/1 rethrows thrown values" do
      assert catch_throw(ebench(fn -> throw(:abort) end)) == :abort
    end

    test "ebench/2 rethrows thrown values" do
      assert catch_throw(ebench("throw_test", fn -> throw(:stop) end)) == :stop
    end

    test "ebench/2 works inside egroup" do
      result =
        egroup("bench_group", fn ->
          ebench("inner", fn -> :done end)
        end)

      assert result == :done
    end
  end
end
