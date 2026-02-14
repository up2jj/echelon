# Benchmark script to measure runtime overhead of Echelon logging
#
# Run with: mix run bench/runtime_overhead.exs
#
# This benchmark compares the overhead of Echelon logging in different scenarios:
# - Enabled vs disabled
# - Simple messages vs complex metadata
# - Lazy evaluation when disabled
#
# The goal is to demonstrate that when disabled, Echelon has minimal overhead
# (< 100ns per call) due to the early enabled check optimization.

# Ensure Echelon is started
{:ok, _} = Application.ensure_all_started(:echelon)

# Helper to create expensive computation
defmodule BenchHelpers do
  def expensive_computation do
    # Simulate expensive work
    Enum.reduce(1..100, 0, fn x, acc -> acc + x end)
    "expensive result"
  end

  def complex_metadata do
    %{
      user: %{id: 12345, name: "John Doe", email: "john@example.com", role: :admin},
      request: %{
        method: "POST",
        path: "/api/v1/users/create",
        headers: %{"content-type" => "application/json", "authorization" => "Bearer token"},
        params: %{name: "New User", email: "new@example.com"}
      },
      metrics: %{
        duration_ms: 145,
        db_queries: 5,
        cache_hits: 12,
        cache_misses: 3,
        memory_mb: 45.6
      },
      timestamp: System.system_time(:microsecond),
      correlation_id: "abc-123-def-456",
      tags: ["important", "user-creation", "audit"]
    }
  end
end

IO.puts("\n" <> IO.ANSI.cyan() <> "═══════════════════════════════════════════════════════════" <> IO.ANSI.reset())
IO.puts(IO.ANSI.cyan() <> "  Echelon Runtime Overhead Benchmark" <> IO.ANSI.reset())
IO.puts(IO.ANSI.cyan() <> "═══════════════════════════════════════════════════════════" <> IO.ANSI.reset() <> "\n")

IO.puts("This benchmark measures the performance impact of Echelon logging calls")
IO.puts("in production scenarios where logging may be disabled.\n")

IO.puts(IO.ANSI.yellow() <> "Testing Configuration:" <> IO.ANSI.reset())
IO.puts("  • Early enabled check: #{IO.ANSI.green()}OPTIMIZED#{IO.ANSI.reset()}")
IO.puts("  • Benchmark warmup: 2 seconds")
IO.puts("  • Benchmark time: 5 seconds per scenario")
IO.puts("")

# Benchmark with logging DISABLED
IO.puts(IO.ANSI.magenta() <> "═══ Phase 1: Logging DISABLED (Production Mode) ═══" <> IO.ANSI.reset() <> "\n")
Echelon.off()

Benchee.run(
  %{
    "disabled - simple message" => fn ->
      Echelon.info("Simple log message")
    end,
    "disabled - with metadata" => fn ->
      Echelon.info("Log with metadata", user_id: 123, action: "login", duration_ms: 45)
    end,
    "disabled - complex metadata" => fn ->
      Echelon.info("Complex log", BenchHelpers.complex_metadata())
    end,
    "disabled - lazy evaluation" => fn ->
      Echelon.info(fn -> BenchHelpers.expensive_computation() end)
    end,
    "disabled - group with logs" => fn ->
      Echelon.group("benchmark_group", fn ->
        Echelon.info("Inside group")
        Echelon.debug("Debug message")
        :ok
      end)
    end
  },
  warmup: 2,
  time: 5,
  memory_time: 2,
  formatters: [
    {Benchee.Formatters.Console,
     extended_statistics: true}
  ],
  print: [
    fast_warning: false
  ]
)

IO.puts("\n" <> IO.ANSI.magenta() <> "═══ Phase 2: Logging ENABLED (Development Mode) ═══" <> IO.ANSI.reset() <> "\n")
Echelon.on()

Benchee.run(
  %{
    "enabled - simple message" => fn ->
      Echelon.info("Simple log message")
    end,
    "enabled - with metadata" => fn ->
      Echelon.info("Log with metadata", user_id: 123, action: "login", duration_ms: 45)
    end,
    "enabled - complex metadata" => fn ->
      Echelon.info("Complex log", BenchHelpers.complex_metadata())
    end,
    "enabled - lazy evaluation" => fn ->
      Echelon.info(fn -> BenchHelpers.expensive_computation() end)
    end
  },
  warmup: 2,
  time: 5,
  memory_time: 2,
  formatters: [
    {Benchee.Formatters.Console,
     extended_statistics: true}
  ],
  print: [
    fast_warning: false
  ]
)

IO.puts("\n" <> IO.ANSI.cyan() <> "═══════════════════════════════════════════════════════════" <> IO.ANSI.reset())
IO.puts(IO.ANSI.cyan() <> "  Benchmark Complete" <> IO.ANSI.reset())
IO.puts(IO.ANSI.cyan() <> "═══════════════════════════════════════════════════════════" <> IO.ANSI.reset() <> "\n")

IO.puts(IO.ANSI.green() <> "Key Findings:" <> IO.ANSI.reset())
IO.puts("  • When DISABLED: Overhead should be < 100ns per call")
IO.puts("  • Lazy functions should NOT be evaluated when disabled (no expensive computation)")
IO.puts("  • Complex metadata should have similar overhead to simple messages when disabled")
IO.puts("  • When ENABLED: Normal overhead for message processing and delivery")
IO.puts("")
IO.puts(IO.ANSI.yellow() <> "Production Recommendation:" <> IO.ANSI.reset())
IO.puts("  Set #{IO.ANSI.cyan()}config :echelon, enabled: false#{IO.ANSI.reset()} in config/prod.exs")
IO.puts("  This ensures minimal overhead in production environments.")
IO.puts("")
