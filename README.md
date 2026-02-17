# Echelon

Zero-touch log filtering for Elixir applications with integrated console. Keep your IEx console clean while preserving important debugging output in a dedicated monitoring console.

## Table of Contents

- [Overview](#overview)
- [Features](#features)
  - [Client Features](#client-features)
  - [Console Features](#console-features)
- [Installation](#installation)
- [Usage](#usage)
  - [Basic Logging (Client API)](#basic-logging-client-api)
  - [Lazy Evaluation](#lazy-evaluation)
  - [Grouping Related Logs](#grouping-related-logs)
  - [Benchmarking Functions](#benchmarking-functions)
  - [Running the Console](#running-the-console)
  - [What You'll See](#what-youll-see)
  - [Color Scheme](#color-scheme)
- [Configuration (Optional)](#configuration-optional)
  - [Fallback Strategies](#fallback-strategies)
- [Custom Handlers](#custom-handlers)
  - [Configuration](#configuration-1)
  - [Creating a Custom Handler](#creating-a-custom-handler)
  - [Handler Lifecycle](#handler-lifecycle)
  - [Runtime Handler Management](#runtime-handler-management)
  - [Log Entry Structure](#log-entry-structure)
  - [Example Handlers](#example-handlers)
- [Production Considerations](#production-considerations)
  - [Runtime Overhead](#runtime-overhead)
  - [Production Configuration](#production-configuration)
  - [Runtime Control](#runtime-control)
  - [Performance Benchmarks](#performance-benchmarks)
  - [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)
  - [Console doesn't start](#console-doesnt-start)
  - [Logs not appearing in console](#logs-not-appearing-in-console)
- [License](#license)

## Overview

Echelon provides a Logger-like API that sends filtered log messages to an integrated console. This solves the "console pollution" problem during development - your main IEx console shows only regular Logger output, while Echelon logs appear in a dedicated monitoring console.

**Dual-Purpose Design:**
- **As a library**: Add as a dependency to send logs via the Echelon API
- **As a standalone console**: Run in a separate terminal to receive and display logs

## Features

### Client Features
- ✅ **Zero Configuration** - Just add the dependency
- ✅ **Logger-like API** - Familiar `debug/info/warn/error` functions
- ✅ **Benchmarking** - Measure and log execution time, memory, and reductions with `bench/2`
- ✅ **Auto-Discovery** - Automatically finds and connects to console
- ✅ **Smart Buffering** - Buffers logs when console is disconnected
- ✅ **Graceful Fallback** - Configurable behavior when console unavailable

### Console Features
- 🎨 **Color-Coded Output** - Different colors for debug/info/warn/error
- 🔍 **Auto-Discovery** - Automatically discovers connected applications
- 🌐 **Multi-App Support** - Monitor multiple applications simultaneously
- 📊 **Metadata Display** - Shows structured metadata with each log
- ⚡ **Real-Time** - Displays logs as they arrive

## Installation

Add `echelon` to your `mix.exs` dependencies:

```elixir
def deps do
  [
    {:echelon, path: "../echelon"}  # For local development
  ]
end
```

Run:
```bash
mix deps.get
```

That's it! No configuration needed.

## Usage

### Basic Logging (Client API)

```elixir
# Using keyword lists (traditional Elixir style)
Echelon.debug("Database query", query: sql, duration_ms: 45)
Echelon.info("User logged in", user_id: 123, email: "user@example.com")
Echelon.warn("Cache miss", key: cache_key)
Echelon.error("Payment failed", reason: :timeout, amount: 99.99)

# Using maps for complex data structures
Echelon.info("Request completed", %{
  user: %{id: 123, role: :admin, name: "Alice"},
  request: %{method: "POST", path: "/api/users", duration_ms: 45},
  metrics: %{db_queries: 3, cache_hits: 12}
})

# Mix and match - maps work with any Elixir data type
Echelon.debug("Processing batch", %{
  batch_id: "abc123",
  items: [1, 2, 3, 4, 5],
  tags: ["important", "priority"],
  config: %{retry: 3, timeout: 5000}
})
```

### Lazy Evaluation

For expensive computations, use a function:

```elixir
Echelon.debug(fn -> "Expensive: #{inspect(large_data_structure)}" end)
```

The function is only evaluated if the console is connected.

### Grouping Related Logs

Group related log entries with indentation and visual separators:

```elixir
Echelon.group("database_transaction", fn ->
  Echelon.info("Starting transaction")
  Echelon.debug("Executing query", sql: "INSERT INTO users...")
  Echelon.info("Transaction committed")
end)
```

**Output:**
```
▶ database_transaction ▶
  [15:32:01.234] INFO  my_app Starting transaction
  [15:32:01.235] DEBUG my_app Executing query
    sql: "INSERT INTO users..."
  [15:32:01.236] INFO  my_app Transaction committed
◀ database_transaction ◀
```

Group markers appear in **bright magenta** with **cyan** group names for high visibility.

**Nested groups** create visual hierarchy:

```elixir
Echelon.group("api_request", fn ->
  Echelon.info("Received request", endpoint: "/api/users")

  Echelon.group("validation", fn ->
    Echelon.debug("Validating input")
    Echelon.debug("Validation passed")
  end)

  Echelon.group("database", fn ->
    Echelon.info("Inserting user record")
  end)

  Echelon.info("Response sent", status: 201)
end)
```

**Output:**
```
▶ api_request ▶
  [15:32:01.234] INFO  my_app Received request
    endpoint: "/api/users"
  ▶ validation ▶
    [15:32:01.235] DEBUG my_app Validating input
    [15:32:01.236] DEBUG my_app Validation passed
  ◀ validation ◀
  ▶ database ▶
    [15:32:01.237] INFO  my_app Inserting user record
  ◀ database ◀
  [15:32:01.238] INFO  my_app Response sent
    status: 201
◀ api_request ◀
```

The function's **return value is preserved**:

```elixir
result = Echelon.group("computation", fn ->
  Echelon.debug("Computing...")
  42
end)
# result == 42
```

If an exception occurs, the group is properly closed before the exception propagates.

### Benchmarking Functions

Wrap any zero-arity function to measure and log its execution time, process memory delta, and Erlang reduction count:

```elixir
result = Echelon.bench("sort_users", fn ->
  users |> Enum.sort_by(& &1.name)
end)
# result == [sorted users list]
```

**Output:**
```
[15:32:01.234] DEBUG my_app bench: sort_users
  elapsed_us: 312
  elapsed_ms: 0.31
  memory_delta_bytes: 4096
  reductions: 8001
```

The unlabeled form uses `"bench"` as the default label:

```elixir
Echelon.bench(fn -> expensive_operation() end)
```

**Return value is preserved** — `bench` is transparent to the caller:

```elixir
sorted = Echelon.bench("sort", fn -> Enum.sort(list) end)
# sorted == sorted list, bench result discarded
```

**Exception handling** — if the function raises, the error is logged and the exception is reraised with its original stacktrace:

```elixir
Echelon.bench("risky_op", fn -> raise ArgumentError, "bad input" end)
# Logs: ERROR bench: risky_op raised ArgumentError
#         elapsed_us: 23, elapsed_ms: 0.02, exception: "bad input"
# Then raises ArgumentError with original stacktrace
```

**Composing with groups:**

```elixir
Echelon.group("data_pipeline", fn ->
  parsed  = Echelon.bench("parse",     fn -> parse_csv(raw) end)
  records = Echelon.bench("transform", fn -> transform(parsed) end)
  Echelon.bench("insert",    fn -> insert_all(records) end)
end)
```

**Metrics explained:**
- `elapsed_us` / `elapsed_ms` — wall-clock execution time
- `memory_delta_bytes` — process heap change (can be negative if GC ran)
- `reductions` — Erlang work units, useful for comparing algorithmic cost

### Running the Console

**Using IEx (recommended):**
```bash
cd /path/to/echelon
iex --sname echelon -S mix
```

**Using the launcher script:**
```bash
cd /path/to/echelon
./bin/echelon
```

**⚠️ Important:** The node name **must be `echelon`** for the console to start. This prevents conflicts when multiple apps include Echelon as a dependency - only the node named `echelon` will run the console server, while other nodes act as clients only.

In your app terminal, start with any node name:

```bash
iex --sname my_app -S mix phx.server
```

The console will automatically discover and connect to your application(s).

### What You'll See

**Your App IEx Console** (clean, only Logger output):
```
iex(1)> MyApp.process_request()
:ok
```

**Echelon Console** (filtered Echelon logs):
```
✓ Echelon started on node: echelon@localhost
🔍 Echelon Console Ready
Waiting for log entries from connected applications...

[15:32:01.234] INFO  my_app User logged in
  user_id: 123
  email: "user@example.com"

[15:32:05.789] WARN  my_app Slow query detected
  query: "SELECT * FROM large_table"
  duration_ms: 1250

[15:32:10.123] INFO  my_app Request completed
  user: %{id: 123, role: :admin, name: "Alice"}
  request: %{method: "POST", path: "/api/users", duration_ms: 45}
  metrics: %{db_queries: 3, cache_hits: 12}
```

### Color Scheme

- 🔵 **DEBUG** - Cyan
- 🟢 **INFO** - Green
- 🟡 **WARN** - Yellow
- 🔴 **ERROR** - Red

## Configuration (Optional)

Configure behavior in `config/config.exs`:

```elixir
config :echelon,
  # Client options
  fallback: :buffer,              # :buffer | :logger | :silent
  buffer_size: 1000,              # Max buffered logs when disconnected
  cookie: :echelon,               # Cookie for distributed Erlang
  # Console options (optional)
  display: Echelon.Console.TerminalDisplay  # Custom display module
```

### Fallback Strategies

When the console is unavailable:
- **`:buffer`** (default) - Buffers logs in memory, flushes when console connects
- **`:logger`** - Falls back to standard Logger
- **`:silent`** - Drops logs silently

## Custom Handlers

Extend Echelon with custom log handlers for databases, metrics, external services, and more.

### Configuration

Register handlers via the `:handlers` configuration key:

```elixir
config :echelon,
  handlers: [
    # Built-in file handler
    {:file, Echelon.Console.Handlers.FileLogHandler, [
      enabled: true,
      path: "logs/app.log",
      max_entries: 10_000,
      max_bytes: 10_485_760,  # 10MB
      max_backups: 5
    ]},

    # Custom database handler
    {:database, MyApp.DatabaseLogHandler, [
      enabled: true,
      connection: MyApp.Repo,
      table: "logs"
    ]},

    # Custom metrics handler
    {:metrics, MyApp.MetricsHandler, [
      enabled: false,
      endpoint: "https://metrics.example.com"
    ]}
  ]
```

**Handler Format:** Each handler is a `{name, module, opts}` tuple:
- `name` - Atom identifying the handler (`:file`, `:database`, etc.)
- `module` - Handler module implementing `Echelon.Console.LogHandler` behavior
- `opts` - Keyword list of handler-specific configuration options

**Important:** Custom handler modules must be available on the console side (where `Echelon.Console.Server` runs). In distributed systems, handler code must be compiled and loaded on the node running the console, not just on client nodes sending logs.

**Note:** The file handler is always available (even if not explicitly configured) to support the `Echelon.file()` API. It starts disabled by default.

### Creating a Custom Handler

Implement the `Echelon.Console.LogHandler` behavior:

```elixir
defmodule MyApp.DatabaseLogHandler do
  @behaviour Echelon.Console.LogHandler
  require Logger

  @impl true
  def init(opts \\ []) do
    %{
      enabled: false,
      repo: Keyword.get(opts, :repo),
      table: Keyword.get(opts, :table, "logs")
    }
  end

  @impl true
  def enable(state) do
    # Acquire resources (open connections, etc.)
    {:ok, %{state | enabled: true}}
  end

  @impl true
  def disable(state) do
    # Release resources (close connections, etc.)
    {:ok, %{state | enabled: false}}
  end

  @impl true
  def handle_entry(entry, state) do
    # Write log entry to database
    attrs = %{
      level: entry.level,
      message: entry.message,
      metadata: Jason.encode!(entry.metadata),
      timestamp: DateTime.from_unix!(entry.timestamp, :microsecond)
    }

    case state.repo.insert({state.table, attrs}) do
      {:ok, _} -> {:ok, state}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def enabled?(state) do
    state.enabled && state.repo != nil
  end

  @impl true
  def terminate(state) do
    # Optional: cleanup on server shutdown
    :ok
  end
end
```

### Handler Lifecycle

1. **Initialization** - `init/1` called with configuration options
2. **Enabling** - `enable/1` called to acquire resources (if `enabled: true` in config)
3. **Processing** - `handle_entry/2` called for each log when `enabled?/1` returns true
4. **On Error** - If `handle_entry/2` returns error, handler is automatically disabled
5. **Disabling** - `disable/1` called to release resources
6. **Termination** - `terminate/1` called on server shutdown (optional)

### Runtime Handler Management

Control handlers dynamically at runtime:

```elixir
# List all handlers and their status
Echelon.handlers()
#=> %{
#=>   file: %{module: Echelon.Console.Handlers.FileLogHandler, enabled: false},
#=>   database: %{module: MyApp.DatabaseLogHandler, enabled: true}
#=> }

# Enable a handler
Echelon.enable_handler(:metrics)
#=> :ok

# Disable a handler
Echelon.disable_handler(:database)
#=> :ok

# File handler convenience methods (still work)
Echelon.file("custom.log")  # Enable file handler with path
Echelon.file(false)         # Disable file handler
Echelon.file_path()         # Get current file path
```

### Log Entry Structure

Handlers receive log entries with this structure:

```elixir
%{
  level: :debug | :info | :warn | :error,
  message: String.t(),
  timestamp: integer(),              # microseconds since epoch
  node: atom(),                      # e.g., :myapp@localhost
  metadata: map() | keyword(),
  group_marker: :start | :end | nil,
  group_name: String.t() | nil,
  group_depth: integer() | nil
}
```

### Example Handlers

**Simple File Counter:**
```elixir
defmodule MyApp.CounterHandler do
  @behaviour Echelon.Console.LogHandler

  @impl true
  def init(opts \\ []) do
    %{enabled: false, count: 0, path: Keyword.get(opts, :path)}
  end

  @impl true
  def enable(state) do
    {:ok, %{state | enabled: true}}
  end

  @impl true
  def disable(state) do
    # Write final count
    if state.path do
      File.write!(state.path, "Total logs: #{state.count}")
    end
    {:ok, %{state | enabled: false}}
  end

  @impl true
  def handle_entry(_entry, state) do
    {:ok, %{state | count: state.count + 1}}
  end

  @impl true
  def enabled?(state), do: state.enabled
end
```

## Production Considerations

### Runtime Overhead

Echelon is designed to be **production-safe** with minimal overhead:

**When disabled** (recommended for production):
- **< 100 nanoseconds** overhead per log call
- Lazy functions are **NOT evaluated** (zero cost for expensive operations)
- No metadata collection, no system calls, no memory allocation
- Immediate return with early enabled check

**When enabled** (development/debugging):
- **< 10 microseconds** overhead per log call
- Non-blocking async delivery via `GenServer.cast`
- Automatic buffering when console disconnected

### Production Configuration

Recommended `config/prod.exs`:

```elixir
config :echelon,
  enabled: false,        # Disable for minimal overhead
  fallback: :silent      # Drop logs silently
```

This configuration ensures **negligible performance impact** in production, even with debug/trace logging left in your code.

### Runtime Control

Enable/disable logging dynamically for production debugging:

```elixir
# Temporarily enable for debugging
Echelon.on()

# Check current state
Echelon.enabled?()  # => true

# Disable again
Echelon.off()
```

Changes are runtime-only and reset on application restart.

### Performance Benchmarks

Run benchmarks on your hardware:

```bash
mix run bench/runtime_overhead.exs
```

**Expected overhead** (typical modern CPU):
- Disabled: ~50-100ns per call
- Enabled: ~2-10μs per call

Even with 100 log calls per request:
- Disabled: ~5-10μs (0.005-0.01ms) total
- Enabled: ~500μs (0.5ms) total

Both are negligible compared to typical request processing time.

### Best Practices

1. **Use lazy evaluation for expensive operations:**
   ```elixir
   # ❌ Bad: always computed
   Echelon.debug("Data: #{inspect(large_struct)}")

   # ✅ Good: only computed when enabled
   Echelon.debug(fn -> "Data: #{inspect(large_struct)}" end)
   ```

2. **Disable in production by default** - enable only when needed for debugging

3. **Avoid logging in hot paths** - even < 100ns adds up in tight loops

For detailed production deployment guidance, see [docs/PRODUCTION.md](docs/PRODUCTION.md).

## Troubleshooting

### Console doesn't start

If you see only `✓ Echelon started on node: <name>` without `🔍 Echelon Console Ready`, check that:
- Your node is named exactly `echelon` (not `console`, `echelon_console`, or anything else)
- You're starting with `--sname echelon` or `--name echelon@<hostname>`

The console server only starts on nodes named `echelon` to prevent conflicts when multiple applications include Echelon as a dependency.

### Logs not appearing in console

Check that nodes are connected:
```elixir
# In your app:
Node.list()  # Should include :echelon@localhost

# Manually connect if needed:
Node.connect(:"echelon@localhost")
```

Verify the console is running:
```elixir
# In your app:
:global.whereis_name(:echelon_console)  # Should return a PID
```

## License

Apache-2.0
