# Production Deployment Guide

This guide explains how to deploy Echelon in production environments, including performance characteristics, configuration options, and best practices.

## Table of Contents

- [Runtime Overhead](#runtime-overhead)
- [Production Configuration](#production-configuration)
- [Performance Guarantees](#performance-guarantees)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)

## Runtime Overhead

### When Logging is Enabled

When Echelon logging is enabled (the default), each log call has the following overhead:

```
Approximate cost per log call: < 10 microseconds

Breakdown:
- Function call and enabled check: ~100ns
- Lazy evaluation (if applicable): varies
- Group stack retrieval: ~50ns (Process.get)
- Timestamp generation: ~100ns (System.system_time)
- Node/PID metadata: ~50ns
- Map construction: ~200ns
- GenServer.cast: ~1-2μs
- Async processing in GenServer: non-blocking
```

**Key points:**
- The call is **non-blocking** - uses `GenServer.cast` for async delivery
- Logging does not block your application code
- Buffering happens automatically when console is disconnected

### When Logging is Disabled

When Echelon logging is disabled, the overhead is **minimal**:

```
Approximate cost per log call: < 100 nanoseconds

Breakdown:
- Function call: ~20ns
- Enabled check (Application.get_env): ~30-50ns
- Early return: ~10ns
```

**Optimization Details:**

Echelon uses an **early enabled check** in the logging function:

```elixir
defp log(level, message, metadata) do
  unless Application.get_env(:echelon, :enabled, true) do
    :ok
  else
    # ... metadata collection and processing ...
  end
end
```

This means when disabled:
- ✅ **Lazy functions are NOT evaluated** - expensive computations are skipped
- ✅ **No metadata collection** - no timestamps, PIDs, or system calls
- ✅ **No map construction** - no memory allocation
- ✅ **No GenServer communication** - no message passing overhead
- ✅ **Immediate return** - < 100ns total overhead

### Benchmark Results

Run the benchmark yourself to measure on your hardware:

```bash
mix deps.get
mix run bench/runtime_overhead.exs
```

**Expected results on modern hardware:**

| Scenario | Enabled | Disabled |
|----------|---------|----------|
| Simple message | ~2-5μs | ~50-100ns |
| With metadata | ~3-7μs | ~50-100ns |
| Complex metadata | ~5-10μs | ~50-100ns |
| Lazy evaluation | ~2-5μs + fn cost | ~50-100ns (fn NOT called) |
| Group with logs | ~10-20μs | ~100-200ns |

**Impact on a typical web request:**

Assuming 100 log calls per request:
- **Enabled:** ~500μs (0.5ms) total overhead
- **Disabled:** ~5-10μs (0.005-0.01ms) total overhead

This is negligible compared to typical request processing time (10-100ms+).

## Production Configuration

### Recommended Production Setup

Create or update `config/prod.exs`:

```elixir
import Config

# Disable Echelon in production for minimal overhead
config :echelon,
  enabled: false

# Optional: Configure fallback behavior
config :echelon,
  enabled: false,
  fallback: :silent,  # :buffer | :logger | :silent
  buffer_size: 1000
```

### Configuration Options

#### `enabled`
- **Type:** `boolean`
- **Default:** `true`
- **Description:** Master switch for all Echelon logging
- **Production recommendation:** `false` for minimal overhead

#### `fallback`
- **Type:** `:buffer | :logger | :silent`
- **Default:** `:buffer`
- **Description:** Behavior when console is unavailable
  - `:buffer` - Buffer logs in memory (default)
  - `:logger` - Fall back to standard Logger
  - `:silent` - Drop logs silently
- **Production recommendation:** `:silent` when `enabled: false`

#### `buffer_size`
- **Type:** `integer`
- **Default:** `1000`
- **Description:** Maximum number of buffered log entries
- **Production recommendation:** `100-500` to limit memory usage

#### `cookie`
- **Type:** `atom`
- **Default:** `:echelon`
- **Description:** Erlang distribution cookie
- **Production note:** Should match across nodes if using distributed Erlang

### Environment-Specific Configuration

```elixir
# config/dev.exs
import Config

config :echelon,
  enabled: true,
  fallback: :buffer,
  buffer_size: 1000

# config/test.exs
import Config

config :echelon,
  enabled: false,  # Disable in tests for speed
  fallback: :silent

# config/prod.exs
import Config

config :echelon,
  enabled: false,  # Disable in production
  fallback: :silent
```

### Runtime Control

You can enable/disable logging at runtime for production debugging:

```elixir
# In production IEx console
iex> Echelon.off()
:ok

iex> Echelon.on()
:ok

iex> Echelon.enabled?()
true
```

**Use case:** Enable temporarily in production to debug a specific issue, then disable again.

**Warning:** Runtime changes are not persisted and will reset on application restart.

**Performance:** `on/0`, `off/0`, and `enabled?/0` are direct `Application` env reads/writes (ETS). They do not go through a GenServer, so they are safe to call from any process without scheduler contention.

## Performance Guarantees

### Production Runtime Guarantees

When `enabled: false` in production:

| Guarantee | Description |
|-----------|-------------|
| **Overhead** | < 100 nanoseconds per log call |
| **Lazy evaluation** | Functions are NOT evaluated (zero cost) |
| **Memory** | No allocations for log entries |
| **Blocking** | Non-blocking (immediate return) |
| **Side effects** | No system calls, no Process dictionary access |

### Comparison with Standard Logger

| Feature | Echelon (disabled) | Logger (compile-time disabled) | Logger (runtime disabled) |
|---------|-------------------|-------------------------------|--------------------------|
| Overhead | ~100ns | 0ns (eliminated) | ~50ns (macro check) |
| Dynamic enable/disable | ✅ Yes | ❌ No (requires recompile) | ✅ Yes |
| Code elimination | ❌ No | ✅ Yes | ❌ No |
| Lazy evaluation | ✅ Skipped | ✅ Eliminated | ⚠️ Sometimes evaluated |

**Trade-off:** Echelon prioritizes runtime flexibility over absolute zero overhead. For most applications, < 100ns per call is negligible.

## Best Practices

### 1. Use Lazy Evaluation for Expensive Operations

```elixir
# ❌ BAD: Expensive computation happens even when disabled
Echelon.debug("Result: #{expensive_calculation()}")

# ✅ GOOD: Function only evaluated when enabled
Echelon.debug(fn -> "Result: #{expensive_calculation()}" end)
```

### 2. Disable in Production by Default

```elixir
# config/prod.exs
config :echelon, enabled: false
```

### 3. Use Appropriate Log Levels

```elixir
# Development/debugging
Echelon.debug("Detailed execution trace", step: 5, state: inspect(state))

# Important events
Echelon.info("User logged in", user_id: user.id)

# Problems that need attention
Echelon.warn("Slow query detected", duration_ms: 1250, query: sql)

# Errors requiring immediate action
Echelon.error("Payment processing failed", reason: error, amount: amount)
```

### 4. Use Groups for Complex Operations

Groups help organize related log entries, but they add overhead. Use judiciously:

```elixir
# Good use of groups
Echelon.group("transaction", fn ->
  Echelon.info("Starting payment processing")
  process_payment(params)
  Echelon.info("Payment completed")
end)

# Overkill - don't group simple operations
# ❌ Echelon.group("addition", fn -> 1 + 1 end)
```

### 5. Avoid Logging in Hot Paths

Even with < 100ns overhead when disabled, avoid logging in extremely hot code paths:

```elixir
# ❌ BAD: Logging in tight loop
Enum.each(1..1_000_000, fn i ->
  Echelon.debug("Processing item", index: i)  # 1M calls!
end)

# ✅ GOOD: Log at higher level
Echelon.debug("Processing batch", count: 1_000_000)
Enum.each(1..1_000_000, fn i -> process_item(i) end)
Echelon.debug("Batch complete")
```

### 6. Monitor Buffer Size

If running with `fallback: :buffer` in production:

```elixir
# Check buffer size periodically
buffer_size = :sys.get_state(Echelon.Client).buffer |> length()

if buffer_size > 500 do
  Logger.warn("Echelon buffer growing: #{buffer_size} entries")
end
```

## Troubleshooting

### High Memory Usage

**Symptom:** Application memory grows when Echelon console is disconnected

**Cause:** Buffer accumulating log entries

**Solutions:**
1. Set `enabled: false` in production
2. Use `fallback: :silent` to drop logs instead of buffering
3. Reduce `buffer_size` to limit memory growth

```elixir
# config/prod.exs
config :echelon,
  enabled: false,
  fallback: :silent,
  buffer_size: 100
```

### Performance Degradation

**Symptom:** Requests are slower than expected

**Diagnosis:**
1. Check if Echelon is enabled: `Echelon.enabled?()`
2. Count log calls per request
3. Run benchmarks: `mix run bench/runtime_overhead.exs`

**Solutions:**
1. Disable Echelon: `Echelon.off()`
2. Use lazy evaluation for expensive messages
3. Reduce number of log calls in hot paths

### Cannot Disable Logging

**Symptom:** `Echelon.off()` doesn't seem to work

**Check:**
```elixir
iex> Echelon.off()
:ok
iex> Echelon.enabled?()
false  # Should be false
iex> Application.get_env(:echelon, :enabled)
false  # Should be false
```

If still seeing overhead, verify the optimization is in place:
```bash
grep -A 3 "defp log(level, message, metadata)" lib/echelon.ex
```

Should see the early enabled check.

### Logs Still Appearing When Disabled

**Note:** Disabling Echelon only affects Echelon logs, not standard Logger logs.

```elixir
# This is disabled by Echelon.off()
Echelon.info("This won't appear")

# This is NOT affected by Echelon.off()
Logger.info("This will still appear")
```

They are independent systems.

## Migration from Development to Production

### Step 1: Audit Log Calls

Search for expensive operations in log calls:

```bash
# Find potential expensive operations
grep -r "Echelon\." lib/ | grep -E "(inspect|Enum|calculate|process)"
```

Convert to lazy evaluation:
```elixir
# Before
Echelon.debug("State: #{inspect(large_state)}")

# After
Echelon.debug(fn -> "State: #{inspect(large_state)}" end)
```

### Step 2: Configure Production Environment

Update `config/prod.exs`:
```elixir
config :echelon,
  enabled: false,
  fallback: :silent
```

### Step 3: Run Benchmarks

Verify overhead is acceptable:
```bash
MIX_ENV=prod mix run bench/runtime_overhead.exs
```

### Step 4: Deploy and Monitor

After deployment:
1. Monitor memory usage
2. Monitor request latency
3. Verify Echelon is disabled: `Application.get_env(:echelon, :enabled)`

### Step 5: Emergency Re-enable (if needed)

If you need to debug production issues:
```elixir
# Via IEx remote console
iex(prod@host)> Echelon.on()
:ok

# Reproduce issue with logging enabled
# ...

# Disable again
iex(prod@host)> Echelon.off()
:ok
```

## Conclusion

Echelon is designed to be **production-safe** when properly configured:

- ✅ **Minimal overhead** when disabled (< 100ns per call)
- ✅ **Runtime control** for production debugging
- ✅ **Lazy evaluation** prevents expensive computations
- ✅ **No blocking** - all operations are async
- ✅ **Configurable** fallback and buffer behavior

**Recommended configuration for production:**
```elixir
# config/prod.exs
config :echelon,
  enabled: false,
  fallback: :silent
```

This provides peace of mind that debug/trace logging left in code has negligible impact on production performance.

For questions or issues, please file an issue on GitHub.
