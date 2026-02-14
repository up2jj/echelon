defmodule Echelon.Console.FileDisplayTest do
  use ExUnit.Case, async: true

  describe "format_entry/1 for regular entries" do
    test "formats entry with all fields" do
      entry = %{
        level: :info,
        message: "Test message",
        metadata: [user_id: 123, status: "active"],
        timestamp: 1_640_000_000_000_000,
        # 2021-12-20 13:33:20 UTC
        node: :myapp@localhost,
        pid: self(),
        group_depth: 0,
        group_name: nil,
        group_marker: nil
      }

      formatted = Echelon.Console.FileDisplay.format_entry(entry)

      # Should contain timestamp, level, node, message
      assert formatted =~ ~r/\[\d{2}:\d{2}:\d{2}\.\d{3}\]/
      assert formatted =~ "INFO"
      assert formatted =~ "myapp"
      assert formatted =~ "Test message"

      # Should contain metadata
      assert formatted =~ "user_id:"
      assert formatted =~ "123"
      assert formatted =~ "status:"
      assert formatted =~ "active"

      # Should end with newline
      assert String.ends_with?(formatted, "\n")
    end

    test "formats entry with minimal fields" do
      entry = %{
        level: :debug,
        message: "Debug message",
        metadata: [],
        timestamp: 1_640_000_000_000_000,
        node: :test@localhost,
        group_depth: 0
      }

      formatted = Echelon.Console.FileDisplay.format_entry(entry)

      assert formatted =~ "DEBUG"
      assert formatted =~ "test"
      assert formatted =~ "Debug message"

      # Should have single line (no metadata section)
      assert length(String.split(formatted, "\n", trim: true)) == 1
    end

    test "formats timestamp correctly" do
      # Using a known timestamp: 2021-12-20 13:33:20.123456 UTC
      entry = %{
        level: :info,
        message: "Test",
        metadata: [],
        timestamp: 1_640_000_000_123_456,
        node: :test@localhost,
        group_depth: 0
      }

      formatted = Echelon.Console.FileDisplay.format_entry(entry)

      # Should have HH:MM:SS.mmm format
      assert formatted =~ ~r/\[\d{2}:\d{2}:\d{2}\.\d{3}\]/
    end

    test "formats different log levels correctly" do
      levels = [:debug, :info, :warn, :error]

      Enum.each(levels, fn level ->
        entry = %{
          level: level,
          message: "Test",
          metadata: [],
          timestamp: System.system_time(:microsecond),
          node: :test@localhost,
          group_depth: 0
        }

        formatted = Echelon.Console.FileDisplay.format_entry(entry)

        case level do
          :debug -> assert formatted =~ "DEBUG"
          :info -> assert formatted =~ "INFO"
          :warn -> assert formatted =~ "WARN"
          :error -> assert formatted =~ "ERROR"
        end
      end)
    end

    test "formats node name correctly" do
      entry = %{
        level: :info,
        message: "Test",
        metadata: [],
        timestamp: System.system_time(:microsecond),
        node: :my_cool_app@server123,
        group_depth: 0
      }

      formatted = Echelon.Console.FileDisplay.format_entry(entry)

      # Should extract just the app name before @
      assert formatted =~ "my_cool_app"
      refute formatted =~ "@server123"
    end

    test "formats metadata as plain text without ANSI codes" do
      entry = %{
        level: :info,
        message: "Test",
        metadata: [key: "value", number: 42],
        timestamp: System.system_time(:microsecond),
        node: :test@localhost,
        group_depth: 0
      }

      formatted = Echelon.Console.FileDisplay.format_entry(entry)

      # Should NOT contain ANSI escape codes
      refute formatted =~ "\e["
      refute String.contains?(formatted, "\e[")

      # Should contain metadata keys and values
      assert formatted =~ "key:"
      assert formatted =~ ~s("value")
      assert formatted =~ "number:"
      assert formatted =~ "42"
    end

    test "handles empty metadata gracefully" do
      entry = %{
        level: :info,
        message: "Test",
        metadata: [],
        timestamp: System.system_time(:microsecond),
        node: :test@localhost,
        group_depth: 0
      }

      formatted = Echelon.Console.FileDisplay.format_entry(entry)

      # Should be a single line (no metadata section)
      lines = String.split(formatted, "\n", trim: true)
      assert length(lines) == 1
    end

    test "handles map metadata" do
      entry = %{
        level: :info,
        message: "Test",
        metadata: %{user: %{id: 123, name: "Alice"}, count: 5},
        timestamp: System.system_time(:microsecond),
        node: :test@localhost,
        group_depth: 0
      }

      formatted = Echelon.Console.FileDisplay.format_entry(entry)

      assert formatted =~ "user:"
      assert formatted =~ "id: 123"
      assert formatted =~ ~s(name: "Alice")
      assert formatted =~ "count:"
      assert formatted =~ "5"
    end

    test "handles keyword list metadata" do
      entry = %{
        level: :info,
        message: "Test",
        metadata: [foo: :bar, baz: "qux"],
        timestamp: System.system_time(:microsecond),
        node: :test@localhost,
        group_depth: 0
      }

      formatted = Echelon.Console.FileDisplay.format_entry(entry)

      assert formatted =~ "foo:"
      assert formatted =~ ":bar"
      assert formatted =~ "baz:"
      assert formatted =~ ~s("qux")
    end

    test "handles nil/missing optional fields" do
      entry = %{
        level: nil,
        message: nil,
        metadata: nil,
        timestamp: System.system_time(:microsecond),
        node: :test@localhost,
        group_depth: 0
      }

      formatted = Echelon.Console.FileDisplay.format_entry(entry)

      # Should not crash and produce valid output
      assert is_binary(formatted)
      assert formatted =~ "INFO"
      # Default level
    end
  end

  describe "format_entry/1 for group markers" do
    test "formats group start marker" do
      entry = %{
        group_marker: :start,
        group_name: "test_group",
        group_depth: 1,
        timestamp: System.system_time(:microsecond),
        node: :test@localhost
      }

      formatted = Echelon.Console.FileDisplay.format_entry(entry)

      assert formatted =~ "▶"
      assert formatted =~ "test_group"
      assert formatted =~ "▶"
      assert String.ends_with?(formatted, "\n")
    end

    test "formats group end marker" do
      entry = %{
        group_marker: :end,
        group_name: "test_group",
        group_depth: 1,
        timestamp: System.system_time(:microsecond),
        node: :test@localhost
      }

      formatted = Echelon.Console.FileDisplay.format_entry(entry)

      assert formatted =~ "◀"
      assert formatted =~ "test_group"
      assert formatted =~ "◀"
      assert String.ends_with?(formatted, "\n")
    end

    test "applies indentation based on depth" do
      # Depth 1 - no indentation (depth - 1 = 0)
      entry_depth1 = %{
        group_marker: :start,
        group_name: "outer",
        group_depth: 1,
        timestamp: System.system_time(:microsecond),
        node: :test@localhost
      }

      formatted1 = Echelon.Console.FileDisplay.format_entry(entry_depth1)
      refute String.starts_with?(formatted1, "  ")

      # Depth 2 - 2 spaces indentation
      entry_depth2 = %{
        group_marker: :start,
        group_name: "inner",
        group_depth: 2,
        timestamp: System.system_time(:microsecond),
        node: :test@localhost
      }

      formatted2 = Echelon.Console.FileDisplay.format_entry(entry_depth2)
      assert String.starts_with?(formatted2, "  ")

      # Depth 3 - 4 spaces indentation
      entry_depth3 = %{
        group_marker: :start,
        group_name: "deeply_nested",
        group_depth: 3,
        timestamp: System.system_time(:microsecond),
        node: :test@localhost
      }

      formatted3 = Echelon.Console.FileDisplay.format_entry(entry_depth3)
      assert String.starts_with?(formatted3, "    ")
    end

    test "includes group name in markers" do
      entry = %{
        group_marker: :start,
        group_name: "database_transaction",
        group_depth: 1,
        timestamp: System.system_time(:microsecond),
        node: :test@localhost
      }

      formatted = Echelon.Console.FileDisplay.format_entry(entry)

      assert formatted =~ "database_transaction"
    end

    test "handles missing group name" do
      entry = %{
        group_marker: :start,
        group_name: nil,
        group_depth: 1,
        timestamp: System.system_time(:microsecond),
        node: :test@localhost
      }

      formatted = Echelon.Console.FileDisplay.format_entry(entry)

      assert formatted =~ "unnamed"
    end
  end

  describe "indentation for regular entries" do
    test "no indentation at depth 0" do
      entry = %{
        level: :info,
        message: "Root level",
        metadata: [],
        timestamp: System.system_time(:microsecond),
        node: :test@localhost,
        group_depth: 0
      }

      formatted = Echelon.Console.FileDisplay.format_entry(entry)

      # Should start with [timestamp], not with spaces
      assert formatted =~ ~r/^\[/
    end

    test "indents nested group entries correctly" do
      # Depth 1 - 2 spaces
      entry1 = %{
        level: :info,
        message: "Depth 1",
        metadata: [],
        timestamp: System.system_time(:microsecond),
        node: :test@localhost,
        group_depth: 1
      }

      formatted1 = Echelon.Console.FileDisplay.format_entry(entry1)
      assert String.starts_with?(formatted1, "  [")

      # Depth 2 - 4 spaces
      entry2 = %{
        level: :info,
        message: "Depth 2",
        metadata: [],
        timestamp: System.system_time(:microsecond),
        node: :test@localhost,
        group_depth: 2
      }

      formatted2 = Echelon.Console.FileDisplay.format_entry(entry2)
      assert String.starts_with?(formatted2, "    [")

      # Depth 3 - 6 spaces
      entry3 = %{
        level: :info,
        message: "Depth 3",
        metadata: [],
        timestamp: System.system_time(:microsecond),
        node: :test@localhost,
        group_depth: 3
      }

      formatted3 = Echelon.Console.FileDisplay.format_entry(entry3)
      assert String.starts_with?(formatted3, "      [")
    end

    test "metadata is indented relative to entry depth" do
      entry = %{
        level: :info,
        message: "Nested",
        metadata: [key: "value"],
        timestamp: System.system_time(:microsecond),
        node: :test@localhost,
        group_depth: 2
      }

      formatted = Echelon.Console.FileDisplay.format_entry(entry)
      lines = String.split(formatted, "\n", trim: true)

      # First line (main entry) should start with 4 spaces (depth 2)
      assert String.starts_with?(List.first(lines), "    ")

      # Metadata line should have 6 spaces (depth 2 + 1 extra for metadata)
      assert String.starts_with?(List.last(lines), "      ")
    end

    test "handles deep nesting" do
      entry = %{
        level: :info,
        message: "Very deep",
        metadata: [],
        timestamp: System.system_time(:microsecond),
        node: :test@localhost,
        group_depth: 10
      }

      formatted = Echelon.Console.FileDisplay.format_entry(entry)

      # Should have 20 spaces (10 * 2)
      expected_indent = String.duplicate("  ", 10)
      assert String.starts_with?(formatted, expected_indent <> "[")
    end
  end

  describe "ANSI code verification" do
    test "does not include ANSI color codes in any output" do
      test_entries = [
        # Regular entry
        %{
          level: :info,
          message: "Test",
          metadata: [key: "value"],
          timestamp: System.system_time(:microsecond),
          node: :test@localhost,
          group_depth: 0
        },
        # Group start
        %{
          group_marker: :start,
          group_name: "group",
          group_depth: 1,
          timestamp: System.system_time(:microsecond),
          node: :test@localhost
        },
        # Group end
        %{
          group_marker: :end,
          group_name: "group",
          group_depth: 1,
          timestamp: System.system_time(:microsecond),
          node: :test@localhost
        },
        # Different log levels
        %{
          level: :debug,
          message: "Debug",
          metadata: [],
          timestamp: System.system_time(:microsecond),
          node: :test@localhost,
          group_depth: 0
        },
        %{
          level: :warn,
          message: "Warning",
          metadata: [],
          timestamp: System.system_time(:microsecond),
          node: :test@localhost,
          group_depth: 0
        },
        %{
          level: :error,
          message: "Error",
          metadata: [],
          timestamp: System.system_time(:microsecond),
          node: :test@localhost,
          group_depth: 0
        }
      ]

      Enum.each(test_entries, fn entry ->
        formatted = Echelon.Console.FileDisplay.format_entry(entry)

        # Check for common ANSI escape sequences
        refute formatted =~ "\e["
        refute String.contains?(formatted, "\e[")
        refute formatted =~ "\x1b["
        refute String.contains?(formatted, "\x1b[")

        # Verify it's printable plain text (String.printable? expects a string, not charlist)
        trimmed = String.trim(formatted)
        assert String.printable?(trimmed)
      end)
    end
  end
end
