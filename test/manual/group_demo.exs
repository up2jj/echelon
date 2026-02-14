# Manual test script for Echelon.group/2
# Run this in IEx to test the group functionality visually
#
# Usage:
#   iex --sname test -S mix
#   c "test/manual/group_demo.exs"

IO.puts("\n" <> IO.ANSI.bright() <> "=== Echelon Group Demo ===" <> IO.ANSI.reset() <> "\n")

# Test 1: Basic group
IO.puts(IO.ANSI.cyan() <> "Test 1: Basic group" <> IO.ANSI.reset())
Echelon.group("database", fn ->
  Echelon.info("Query started")
  Echelon.debug("SELECT * FROM users", rows: 42)
  Echelon.info("Query completed")
end)

Process.sleep(100)

# Test 2: Nested groups (2 levels)
IO.puts("\n" <> IO.ANSI.cyan() <> "Test 2: Nested groups" <> IO.ANSI.reset())
Echelon.group("api_request", fn ->
  Echelon.info("Received POST /api/users")

  Echelon.group("validation", fn ->
    Echelon.debug("Checking required fields")
    Echelon.debug("Validation passed")
  end)

  Echelon.group("database", fn ->
    Echelon.info("Inserting user record")
  end)

  Echelon.info("Response sent", status: 201)
end)

Process.sleep(100)

# Test 3: Deeply nested (3 levels)
IO.puts("\n" <> IO.ANSI.cyan() <> "Test 3: Deeply nested groups" <> IO.ANSI.reset())
Echelon.group("level1", fn ->
  Echelon.info("Level 1 message")

  Echelon.group("level2", fn ->
    Echelon.info("Level 2 message")

    Echelon.group("level3", fn ->
      Echelon.info("Level 3 message - deepest")
    end)

    Echelon.info("Back to level 2")
  end)

  Echelon.info("Back to level 1")
end)

Process.sleep(100)

# Test 4: Error handling
IO.puts("\n" <> IO.ANSI.cyan() <> "Test 4: Error handling" <> IO.ANSI.reset())

try do
  Echelon.group("failing_operation", fn ->
    Echelon.info("About to fail")
    raise "test error"
  end)
rescue
  _ -> :ok
end

Echelon.info("After error - should be unindented")

Process.sleep(100)

# Test 5: Mix of grouped and ungrouped
IO.puts("\n" <> IO.ANSI.cyan() <> "Test 5: Mix of grouped and ungrouped" <> IO.ANSI.reset())
Echelon.info("Ungrouped message 1")

Echelon.group("grouped_section", fn ->
  Echelon.info("Grouped message 1")
  Echelon.debug("Grouped message 2", key: "value")
end)

Echelon.info("Ungrouped message 2")

Process.sleep(100)

# Test 6: Empty group
IO.puts("\n" <> IO.ANSI.cyan() <> "Test 6: Empty group" <> IO.ANSI.reset())
Echelon.group("empty_group", fn ->
  nil
end)

Process.sleep(100)

# Test 7: Group with complex metadata
IO.puts("\n" <> IO.ANSI.cyan() <> "Test 7: Group with complex metadata" <> IO.ANSI.reset())
Echelon.group("transaction", fn ->
  Echelon.info("Starting transaction", %{
    user_id: 123,
    transaction_type: :payment,
    metadata: %{
      amount: 99.99,
      currency: "USD",
      items: [1, 2, 3]
    }
  })

  Echelon.debug("Processing payment")
  Echelon.info("Transaction completed")
end)

Process.sleep(100)

# Test 8: Return value preservation
IO.puts("\n" <> IO.ANSI.cyan() <> "Test 8: Return value preservation" <> IO.ANSI.reset())

result = Echelon.group("computation", fn ->
  Echelon.debug("Computing...")
  42
end)

Echelon.info("Result from group: #{result}")
IO.puts("Actual result value: #{inspect(result)}")

Process.sleep(100)

# Test 9: Using helpers (egroup)
IO.puts("\n" <> IO.ANSI.cyan() <> "Test 9: Using helper egroup/2" <> IO.ANSI.reset())
import Echelon.Helpers

egroup("helper_test", fn ->
  einfo("Using einfo inside egroup")
  edebug("Using edebug with metadata", test: true)
end)

Process.sleep(100)

IO.puts("\n" <> IO.ANSI.bright() <> IO.ANSI.green() <> "=== Demo Complete ===" <> IO.ANSI.reset() <> "\n")
IO.puts("Check the Echelon console to verify:")
IO.puts("  ✓ Group markers show colorful '▶ name ▶' (start) and '◀ name ◀' (end)")
IO.puts("  ✓ Markers appear in bright magenta with cyan group names")
IO.puts("  ✓ Entries inside groups are indented (2 spaces per level)")
IO.puts("  ✓ Metadata maintains extra indentation (4 spaces total)")
IO.puts("  ✓ Nested groups show proper hierarchy")
IO.puts("  ✓ Groups are properly closed even on errors")
IO.puts("  ✓ Return values are preserved")
