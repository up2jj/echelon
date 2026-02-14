# Echelon Demo

Quick demonstration of Echelon's zero-touch log filtering.

## Step-by-Step Test

### Terminal 1: Start the Console

```bash
cd /Users/up2jj/Projekty/echelon
iex --sname echelon -S mix
```

You should see:
```
✓ Echelon started on node: echelon@localhost
🔍 Echelon Console Ready
Waiting for log entries from connected applications...
```

### Terminal 2: Test in IEx

```bash
cd /Users/up2jj/Projekty/echelon
iex --sname test_app -S mix
```

Once IEx starts, try these commands:

```elixir
# Send various log levels
Echelon.info("Hello from Echelon!")
Echelon.debug("Debug information", data: %{test: true})
Echelon.warn("Warning message", severity: :medium)
Echelon.error("Error occurred", reason: :test, code: 42)

# Test with metadata
Echelon.info("User action",
  user_id: 123,
  action: "login",
  ip: "192.168.1.1"
)

# Test lazy evaluation
Echelon.debug(fn ->
  "This message was computed lazily: #{:rand.uniform(1000)}"
end)

# Multiple messages
for i <- 1..5 do
  Echelon.info("Message #{i}", iteration: i)
  Process.sleep(100)
end
```

### What You Should See

**Terminal 2 (Your App):**
- Clean IEx console with just your commands
- No Echelon log output polluting the console

**Terminal 1 (Echelon Console):**
- Color-coded log entries:
  - 🔵 DEBUG in cyan
  - 🟢 INFO in green
  - 🟡 WARN in yellow
  - 🔴 ERROR in red
- Timestamps for each entry
- Node name (echelon_client_XXXX@localhost)
- Formatted metadata

### Example Output (Console)

```
🔍 Echelon Console Ready
Waiting for log entries from connected applications...

[18:45:23.456] INFO  echelon_client_a8b9 Hello from Echelon!

[18:45:25.123] DEBUG echelon_client_a8b9 Debug information
  data: %{test: true}

[18:45:27.789] WARN  echelon_client_a8b9 Warning message
  severity: :medium

[18:45:30.456] ERROR echelon_client_a8b9 Error occurred
  reason: :test
  code: 42
```

## Testing Reconnection

### Test 1: Buffer When Disconnected

1. **Close** the console (Ctrl+C twice in Terminal 1)
2. In Terminal 2, send logs:
   ```elixir
   Echelon.info("Buffered message 1")
   Echelon.info("Buffered message 2")
   ```
3. **Restart** the console in Terminal 1:
   ```bash
   iex --sname echelon -S mix
   ```
4. Within 5 seconds, you should see both buffered messages appear!

### Test 2: Multiple Apps

1. Keep console running in Terminal 1
2. In Terminal 2, keep first app running
3. Open Terminal 3:
   ```bash
   cd /Users/up2jj/Projekty/echelon
   iex --sname test_app2 -S mix
   ```
4. In Terminal 3:
   ```elixir
   Echelon.info("From second app!")
   ```
5. Both apps' logs appear in the same console, with different node names

## Configuration Examples

### Change Buffer Size

In your app's `config/config.exs`:

```elixir
import Config

config :echelon,
  buffer_size: 500,  # Reduce buffer size
  fallback: :buffer
```

### Fallback to Logger

```elixir
config :echelon,
  fallback: :logger  # Falls back to Logger when console unavailable
```

### Silent Mode

```elixir
config :echelon,
  fallback: :silent  # Drops logs when console unavailable
```

### Custom Cookie

For security in production:

```elixir
# In all apps (both client and console use the same config):
config :echelon,
  cookie: :my_secret_cookie
```

## Troubleshooting

### Console doesn't receive logs

Check if nodes are connected:

**In Terminal 1 (console):**
```elixir
Node.self()  # Should be: echelon@localhost
:global.registered_names()  # Should include: :echelon_console
```

**In Terminal 2 (app):**
```elixir
Node.self()  # Should be: echelon_client_XXXX@localhost
Node.list()  # Should show connected nodes
Node.connect(:"echelon@localhost")  # Manually connect if needed
```

### "Failed to start distributed node"

This is usually okay! It means:
- Another instance is using the node name (close other IEx sessions)
- Or EPMD isn't running (we use shortnames to avoid this)

The app will still work, it just won't connect to the console until the issue is resolved.

## Next Steps

Try integrating Echelon into one of your existing projects:

```elixir
# In mix.exs of tm, noteburger, or any other app:
def deps do
  [
    # ... other deps
    {:echelon, path: "/Users/up2jj/Projekty/echelon"}
  ]
end
```

Then use `Echelon.info/2` instead of `Logger.info/2` for logs you want to monitor separately!
