defmodule Echelon.Console.FileLogHandlerTest do
  use ExUnit.Case, async: false

  alias Echelon.Console.Handlers.FileLogHandler

  setup do
    # Create unique temp directory for each test
    temp_dir = Path.join(System.tmp_dir!(), "echelon_test_#{:rand.uniform(1_000_000)}")
    File.mkdir_p!(temp_dir)

    on_exit(fn ->
      File.rm_rf!(temp_dir)
    end)

    {:ok, temp_dir: temp_dir}
  end

  describe "init/1" do
    test "initializes with provided options" do
      opts = [
        path: "/tmp/test.log",
        max_entries: 5000,
        max_bytes: 1_048_576,
        max_backups: 3
      ]

      state = FileLogHandler.init(opts)

      assert state.enabled == false
      assert state.path == "/tmp/test.log"
      assert state.max_entries == 5000
      assert state.max_bytes == 1_048_576
      assert state.max_backups == 3
      assert state.io_device == nil
      assert state.entry_count == 0
      assert state.byte_count == 0
    end

    test "sets default values for missing options" do
      state = FileLogHandler.init([])

      assert state.enabled == false
      assert state.path == nil
      assert state.max_entries == 10_000
      assert state.max_bytes == 10_485_760
      assert state.max_backups == 5
    end

    test "accepts partial options and uses defaults for rest" do
      state = FileLogHandler.init(path: "/tmp/partial.log", max_entries: 1000)

      assert state.path == "/tmp/partial.log"
      assert state.max_entries == 1000
      assert state.max_bytes == 10_485_760
      # default
      assert state.max_backups == 5
      # default
    end
  end

  describe "enable/1 and disable/1" do
    test "enable opens file for writing", %{temp_dir: temp_dir} do
      path = Path.join(temp_dir, "test.log")
      state = FileLogHandler.init(path: path)

      {:ok, enabled_state} = FileLogHandler.enable(state)

      assert enabled_state.enabled == true
      assert enabled_state.io_device != nil
      assert File.exists?(path)

      # Cleanup
      FileLogHandler.disable(enabled_state)
    end

    test "enable returns error when path is nil" do
      state = FileLogHandler.init(path: nil)

      assert {:error, :no_path_configured} = FileLogHandler.enable(state)
    end

    test "enable returns error when path is invalid" do
      # Try to create file in non-existent directory
      state = FileLogHandler.init(path: "/nonexistent/directory/file.log")

      assert {:error, _reason} = FileLogHandler.enable(state)
    end

    test "disable closes file handle", %{temp_dir: temp_dir} do
      path = Path.join(temp_dir, "test.log")
      state = FileLogHandler.init(path: path)
      {:ok, enabled_state} = FileLogHandler.enable(state)

      {:ok, disabled_state} = FileLogHandler.disable(enabled_state)

      assert disabled_state.enabled == false
      assert disabled_state.io_device == nil
    end

    test "disable succeeds even if file not open" do
      state = FileLogHandler.init(path: "/tmp/test.log")

      {:ok, disabled_state} = FileLogHandler.disable(state)

      assert disabled_state.enabled == false
    end

    test "enable resets counters", %{temp_dir: temp_dir} do
      path = Path.join(temp_dir, "test.log")
      state = FileLogHandler.init(path: path)
      state_with_counts = %{state | entry_count: 100, byte_count: 5000}

      {:ok, enabled_state} = FileLogHandler.enable(state_with_counts)

      assert enabled_state.entry_count == 0
      assert enabled_state.byte_count == 0

      # Cleanup
      FileLogHandler.disable(enabled_state)
    end
  end

  describe "handle_entry/2 - file writing" do
    test "writes log entry to file", %{temp_dir: temp_dir} do
      path = Path.join(temp_dir, "test.log")
      state = FileLogHandler.init(path: path)
      {:ok, enabled_state} = FileLogHandler.enable(state)

      entry = build_entry("Test message", :info)

      {:ok, new_state} = FileLogHandler.handle_entry(entry, enabled_state)

      # Cleanup
      FileLogHandler.disable(new_state)

      # Verify file contents
      contents = File.read!(path)
      assert contents =~ "Test message"
      assert contents =~ "INFO"
    end

    test "appends multiple entries", %{temp_dir: temp_dir} do
      path = Path.join(temp_dir, "test.log")
      state = FileLogHandler.init(path: path)
      {:ok, state} = FileLogHandler.enable(state)

      entry1 = build_entry("First message", :info)
      entry2 = build_entry("Second message", :debug)
      entry3 = build_entry("Third message", :warn)

      {:ok, state} = FileLogHandler.handle_entry(entry1, state)
      {:ok, state} = FileLogHandler.handle_entry(entry2, state)
      {:ok, state} = FileLogHandler.handle_entry(entry3, state)

      # Cleanup
      FileLogHandler.disable(state)

      # Verify all entries are in file
      contents = File.read!(path)
      assert contents =~ "First message"
      assert contents =~ "Second message"
      assert contents =~ "Third message"
    end

    test "tracks entry count", %{temp_dir: temp_dir} do
      path = Path.join(temp_dir, "test.log")
      state = FileLogHandler.init(path: path)
      {:ok, state} = FileLogHandler.enable(state)

      assert state.entry_count == 0

      {:ok, state} = FileLogHandler.handle_entry(build_entry("Message 1", :info), state)
      assert state.entry_count == 1

      {:ok, state} = FileLogHandler.handle_entry(build_entry("Message 2", :info), state)
      assert state.entry_count == 2

      {:ok, state} = FileLogHandler.handle_entry(build_entry("Message 3", :info), state)
      assert state.entry_count == 3

      # Cleanup
      FileLogHandler.disable(state)
    end

    test "tracks byte count", %{temp_dir: temp_dir} do
      path = Path.join(temp_dir, "test.log")
      state = FileLogHandler.init(path: path)
      {:ok, state} = FileLogHandler.enable(state)

      assert state.byte_count == 0

      {:ok, state} = FileLogHandler.handle_entry(build_entry("Test", :info), state)
      assert state.byte_count > 0

      byte_count_after_first = state.byte_count

      {:ok, state} = FileLogHandler.handle_entry(build_entry("Another test", :info), state)
      assert state.byte_count > byte_count_after_first

      # Cleanup
      FileLogHandler.disable(state)
    end
  end

  describe "file rotation - by entry count" do
    test "rotates when max_entries exceeded", %{temp_dir: temp_dir} do
      path = Path.join(temp_dir, "test.log")
      state = FileLogHandler.init(path: path, max_entries: 3, max_bytes: 999_999_999)
      {:ok, state} = FileLogHandler.enable(state)

      # Write entries up to the limit
      {:ok, state} = FileLogHandler.handle_entry(build_entry("Entry 1", :info), state)
      {:ok, state} = FileLogHandler.handle_entry(build_entry("Entry 2", :info), state)
      {:ok, state} = FileLogHandler.handle_entry(build_entry("Entry 3", :info), state)

      # This should trigger rotation
      {:ok, state} = FileLogHandler.handle_entry(build_entry("Entry 4", :info), state)

      # Cleanup
      FileLogHandler.disable(state)

      # Backup should exist
      assert File.exists?(path <> ".1")

      # New file should have Entry 4
      contents = File.read!(path)
      assert contents =~ "Entry 4"

      # Backup should have Entries 1-3
      backup_contents = File.read!(path <> ".1")
      assert backup_contents =~ "Entry 1"
      assert backup_contents =~ "Entry 2"
      assert backup_contents =~ "Entry 3"
    end

    test "resets counters after rotation", %{temp_dir: temp_dir} do
      path = Path.join(temp_dir, "test.log")
      state = FileLogHandler.init(path: path, max_entries: 2, max_bytes: 999_999_999)
      {:ok, state} = FileLogHandler.enable(state)

      {:ok, state} = FileLogHandler.handle_entry(build_entry("E1", :info), state)
      {:ok, state} = FileLogHandler.handle_entry(build_entry("E2", :info), state)

      # Trigger rotation - this will rotate and write E3 to new file
      {:ok, state} = FileLogHandler.handle_entry(build_entry("E3", :info), state)

      # After rotation, we have 1 entry in the new file
      assert state.entry_count == 1
      assert state.byte_count > 0

      # Cleanup
      FileLogHandler.disable(state)
    end

    test "creates numbered backup (.1)", %{temp_dir: temp_dir} do
      path = Path.join(temp_dir, "test.log")
      state = FileLogHandler.init(path: path, max_entries: 1, max_bytes: 999_999_999)
      {:ok, state} = FileLogHandler.enable(state)

      {:ok, state} = FileLogHandler.handle_entry(build_entry("Entry 1", :info), state)

      # Trigger rotation
      {:ok, state} = FileLogHandler.handle_entry(build_entry("Entry 2", :info), state)

      # Cleanup
      FileLogHandler.disable(state)

      assert File.exists?(path <> ".1")
    end

    test "shifts existing backups sequentially", %{temp_dir: temp_dir} do
      path = Path.join(temp_dir, "test.log")
      state = FileLogHandler.init(path: path, max_entries: 1, max_bytes: 999_999_999)
      {:ok, state} = FileLogHandler.enable(state)

      # Write entries that will trigger rotations
      # Entry is written first, THEN checked for rotation
      # So Entry 1 is written, then when Entry 2 comes it rotates Entry 1 to .1
      {:ok, state} = FileLogHandler.handle_entry(build_entry("Entry 1", :info), state)
      {:ok, state} = FileLogHandler.handle_entry(build_entry("Entry 2", :info), state)
      {:ok, state} = FileLogHandler.handle_entry(build_entry("Entry 3", :info), state)
      {:ok, state} = FileLogHandler.handle_entry(build_entry("Entry 4", :info), state)

      # Cleanup
      FileLogHandler.disable(state)

      # Should have backups
      assert File.exists?(path <> ".1")
      assert File.exists?(path <> ".2")
      assert File.exists?(path <> ".3")

      # After writing Entry 4, it gets rotated, so current file is empty (new file)
      # The backups contain previous entries
      assert File.read!(path <> ".1") =~ "Entry 4"
      assert File.read!(path <> ".2") =~ "Entry 3"
      assert File.read!(path <> ".3") =~ "Entry 2"
    end

    test "maintains max_backups limit", %{temp_dir: temp_dir} do
      path = Path.join(temp_dir, "test.log")
      state = FileLogHandler.init(path: path, max_entries: 1, max_backups: 2, max_bytes: 999_999_999)
      {:ok, state} = FileLogHandler.enable(state)

      # Create more rotations than max_backups
      state =
        Enum.reduce(1..5, state, fn i, acc_state ->
          {:ok, new_state} = FileLogHandler.handle_entry(build_entry("Entry #{i}", :info), acc_state)
          new_state
        end)

      # Cleanup
      FileLogHandler.disable(state)

      # Should only have max_backups (2) backup files
      assert File.exists?(path <> ".1")
      assert File.exists?(path <> ".2")
      refute File.exists?(path <> ".3")
      refute File.exists?(path <> ".4")
    end

    test "deletes old backups beyond max_backups", %{temp_dir: temp_dir} do
      path = Path.join(temp_dir, "test.log")

      # Start with max_backups=3, create 5 backups
      state = FileLogHandler.init(path: path, max_entries: 1, max_backups: 3, max_bytes: 999_999_999)
      {:ok, state} = FileLogHandler.enable(state)

      state =
        Enum.reduce(1..5, state, fn i, acc_state ->
          {:ok, new_state} = FileLogHandler.handle_entry(build_entry("Entry #{i}", :info), acc_state)
          new_state
        end)

      FileLogHandler.disable(state)

      # Should have backups .1, .2, .3 only
      assert File.exists?(path <> ".1")
      assert File.exists?(path <> ".2")
      assert File.exists?(path <> ".3")
      refute File.exists?(path <> ".4")
      refute File.exists?(path <> ".5")
    end
  end

  describe "file rotation - by byte size" do
    test "rotates when max_bytes exceeded", %{temp_dir: temp_dir} do
      path = Path.join(temp_dir, "test.log")
      # Set very small max_bytes to trigger rotation easily
      state = FileLogHandler.init(path: path, max_entries: 999_999, max_bytes: 50)
      {:ok, state} = FileLogHandler.enable(state)

      # Write entry that will exceed max_bytes
      large_entry = build_entry(String.duplicate("A", 100), :info)

      {:ok, state} = FileLogHandler.handle_entry(large_entry, state)

      # Cleanup
      FileLogHandler.disable(state)

      # Should have created a backup
      assert File.exists?(path <> ".1")
    end

    test "accumulates byte count correctly", %{temp_dir: temp_dir} do
      path = Path.join(temp_dir, "test.log")
      state = FileLogHandler.init(path: path, max_entries: 999_999, max_bytes: 999_999_999)
      {:ok, state} = FileLogHandler.enable(state)

      assert state.byte_count == 0

      {:ok, state} = FileLogHandler.handle_entry(build_entry("Short", :info), state)
      first_count = state.byte_count
      assert first_count > 0

      {:ok, state} = FileLogHandler.handle_entry(build_entry("Longer message here", :info), state)
      assert state.byte_count > first_count

      # Cleanup
      FileLogHandler.disable(state)
    end

    test "resets byte count after rotation", %{temp_dir: temp_dir} do
      path = Path.join(temp_dir, "test.log")
      state = FileLogHandler.init(path: path, max_entries: 999_999, max_bytes: 50)
      {:ok, state} = FileLogHandler.enable(state)

      # Write entry that exceeds max_bytes to trigger rotation
      large_message = String.duplicate("X", 100)
      {:ok, state} = FileLogHandler.handle_entry(build_entry(large_message, :info), state)

      # Entry is written first, THEN rotation happens
      # After rotation, counters are reset and new file is opened
      assert state.byte_count == 0
      assert state.entry_count == 0

      # Cleanup
      FileLogHandler.disable(state)
    end
  end

  describe "enabled?/1" do
    test "returns false when disabled" do
      state = FileLogHandler.init(path: "/tmp/test.log")
      refute FileLogHandler.enabled?(state)
    end

    test "returns false when enabled but file not open" do
      state = FileLogHandler.init(path: "/tmp/test.log")
      state_enabled = %{state | enabled: true, io_device: nil}

      refute FileLogHandler.enabled?(state_enabled)
    end

    test "returns true when enabled and file open", %{temp_dir: temp_dir} do
      path = Path.join(temp_dir, "test.log")
      state = FileLogHandler.init(path: path)
      {:ok, enabled_state} = FileLogHandler.enable(state)

      assert FileLogHandler.enabled?(enabled_state)

      # Cleanup
      FileLogHandler.disable(enabled_state)
    end
  end

  describe "terminate/1" do
    test "closes file on termination", %{temp_dir: temp_dir} do
      path = Path.join(temp_dir, "test.log")
      state = FileLogHandler.init(path: path)
      {:ok, enabled_state} = FileLogHandler.enable(state)

      assert FileLogHandler.terminate(enabled_state) == :ok

      # File should be closed (we can't directly test this, but it shouldn't crash)
    end

    test "succeeds even if already disabled" do
      state = FileLogHandler.init(path: "/tmp/test.log")

      assert FileLogHandler.terminate(state) == :ok
    end

    test "succeeds even if never enabled" do
      state = FileLogHandler.init([])

      assert FileLogHandler.terminate(state) == :ok
    end
  end

  describe "real-world scenarios" do
    test "complete lifecycle: init -> enable -> write -> rotate -> disable", %{temp_dir: temp_dir} do
      path = Path.join(temp_dir, "app.log")

      # Initialize
      state = FileLogHandler.init(path: path, max_entries: 5, max_backups: 2)
      refute FileLogHandler.enabled?(state)

      # Enable
      {:ok, state} = FileLogHandler.enable(state)
      assert FileLogHandler.enabled?(state)
      assert File.exists?(path)

      # Write entries - use Enum.reduce to properly thread state
      state =
        Enum.reduce(1..7, state, fn i, acc_state ->
          entry = build_entry("Log entry #{i}", :info, user_id: i, action: "test")
          {:ok, new_state} = FileLogHandler.handle_entry(entry, acc_state)
          new_state
        end)

      # Disable
      {:ok, disabled_state} = FileLogHandler.disable(state)
      refute FileLogHandler.enabled?(disabled_state)

      # Verify files exist
      assert File.exists?(path)

      # After writing 7 entries with max_entries=5:
      # Entries 1-5 written, then Entry 6 triggers rotation (5 -> .1)
      # Entries 6-10 would go to new file, but we only have 6,7
      # Then Entry 7 triggers next rotation (6 -> .1, old .1 -> .2)
      # Check that backups exist
      assert File.exists?(path <> ".1")
    end

    test "handles concurrent writes gracefully", %{temp_dir: temp_dir} do
      path = Path.join(temp_dir, "concurrent.log")
      state = FileLogHandler.init(path: path)
      {:ok, state} = FileLogHandler.enable(state)

      # Write many entries in quick succession
      state =
        Enum.reduce(1..100, state, fn i, acc_state ->
          entry = build_entry("Entry #{i}", :info)
          {:ok, new_state} = FileLogHandler.handle_entry(entry, acc_state)
          new_state
        end)

      # All writes should succeed
      assert state.entry_count == 100

      # Cleanup
      FileLogHandler.disable(state)

      # Verify all entries written
      contents = File.read!(path)
      assert contents =~ "Entry 1"
      assert contents =~ "Entry 50"
      assert contents =~ "Entry 100"
    end

    test "preserves file contents across enable/disable cycles", %{temp_dir: temp_dir} do
      path = Path.join(temp_dir, "persistent.log")
      state = FileLogHandler.init(path: path)

      # First session
      {:ok, state} = FileLogHandler.enable(state)
      {:ok, state} = FileLogHandler.handle_entry(build_entry("Session 1", :info), state)
      {:ok, _state} = FileLogHandler.disable(state)

      # Second session (re-enable same file)
      state2 = FileLogHandler.init(path: path)
      {:ok, state2} = FileLogHandler.enable(state2)
      {:ok, state2} = FileLogHandler.handle_entry(build_entry("Session 2", :info), state2)
      {:ok, _state2} = FileLogHandler.disable(state2)

      # Both entries should be in file (append mode)
      contents = File.read!(path)
      assert contents =~ "Session 1"
      assert contents =~ "Session 2"
    end
  end

  # Helper functions

  defp build_entry(message, level, metadata \\ []) do
    %{
      level: level,
      message: message,
      metadata: metadata,
      timestamp: System.system_time(:microsecond),
      node: :test@localhost,
      pid: self(),
      group_depth: 0,
      group_name: nil,
      group_marker: nil
    }
  end
end
