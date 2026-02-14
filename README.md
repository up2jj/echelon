# Echelon

Zero-touch log filtering for Elixir applications with integrated console. Keep your IEx console clean while preserving important debugging output in a dedicated monitoring console.

## Overview

Echelon provides a Logger-like API that sends filtered log messages to an integrated console. This solves the "console pollution" problem during development - your main IEx console shows only regular Logger output, while Echelon logs appear in a dedicated monitoring console.

**Dual-Purpose Design:**
- **As a library**: Add as a dependency to send logs via the Echelon API
- **As a standalone console**: Run in a separate terminal to receive and display logs

## Features

### Client Features
- ✅ **Zero Configuration** - Just add the dependency
- ✅ **Logger-like API** - Familiar `debug/info/warn/error` functions
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
