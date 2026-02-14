defmodule Echelon do
  @moduledoc """
  Send logs to Echelon console with zero configuration.

  Echelon provides a Logger-like API for sending filtered log messages
  to a separate console application, keeping your IEx console clean while
  preserving important debugging output.

  ## Usage

      # In your application code - using keyword lists
      Echelon.debug("Database query", query: query, duration: 15)
      Echelon.info("User logged in", user_id: 123, email: "user@example.com")
      Echelon.warn("Cache miss", key: cache_key)
      Echelon.error("Payment failed", reason: :timeout, amount: 99.99)

      # Or using maps for complex data structures
      Echelon.info("Request completed", %{
        user: %{id: 123, role: :admin},
        request: %{method: "POST", path: "/api/users"},
        metrics: %{duration_ms: 45, db_queries: 3}
      })

  ## Installation

  Add `echelon` to your list of dependencies in `mix.exs`:

      def deps do
        [{:echelon, "~> 0.1.0"}]
      end

  That's it! No configuration needed. The Echelon client will automatically
  discover and connect to the Echelon console when it's running.

  ## Lazy Evaluation

  You can pass a function for expensive computations that should only
  be evaluated if the console is connected:

      Echelon.debug(fn -> inspect(expensive_data_structure) end)

  ## Controlling Logging

  You can temporarily suspend and resume logging at runtime:

      # Disable logging
      Echelon.off()
      Echelon.info("This will NOT be logged")

      # Re-enable logging
      Echelon.on()
      Echelon.info("This will be logged")

      # Check current state
      Echelon.enabled?()  #=> true

  When disabled, all log entries are dropped silently with minimal overhead.

  You can also configure the initial state in `config/config.exs`:

      config :echelon,
        enabled: false  # Start with logging disabled

  ## File Logging

  Save log entries to a file while maintaining terminal output:

      # Enable with auto-detected filename (based on git branch)
      Echelon.file()
      #=> Creates echelon_main.log (if on 'main' branch)

      # Enable with specific file path
      Echelon.file("/tmp/my_app.log")

      # Disable file logging
      Echelon.file(false)

      # Check current file path
      Echelon.file_path()
      #=> "/tmp/my_app.log"

  Files are automatically rotated when they exceed 10,000 entries or 10MB.
  Up to 5 backup files are kept (.1, .2, .3, .4, .5).

  Configure file logging in `config/config.exs`:

      config :echelon,
        handlers: [
          {:file, Echelon.Console.Handlers.FileLogHandler, [
            enabled: false,           # Start disabled, enable via API
            path: nil,                # nil = auto-detect from git
            max_entries: 10_000,      # Rotate after N entries
            max_bytes: 10_485_760,    # Rotate after 10MB
            max_backups: 5            # Keep 5 backup files
          ]}
        ]

  ## Configuration (Optional)

  Configure fallback behavior in `config/config.exs`:

      config :echelon,
        fallback: :buffer,  # :buffer | :logger | :silent
        buffer_size: 1000,
        cookie: :echelon_secret
  """

  @type metadata :: keyword() | map()
  @type message :: String.t() | (() -> String.t())

  @doc """
  Log a message at debug level.

  Metadata can be a keyword list or a map with any values (including nested maps,
  lists, structs, etc.).

  ## Examples

      Echelon.debug("Starting computation")
      Echelon.debug("Query executed", query: "SELECT * FROM users", duration_ms: 45)
      Echelon.debug(fn -> "Expensive computation result" end)

      # Using maps for complex data
      Echelon.debug("User data", %{
        user: %{id: 123, name: "Alice"},
        preferences: %{theme: "dark", notifications: true}
      })
  """
  @spec debug(message(), metadata()) :: :ok
  def debug(message, metadata \\ []) do
    log(:debug, message, metadata)
  end

  @doc """
  Log a message at info level.

  ## Examples

      Echelon.info("User logged in")
      Echelon.info("Request processed", user_id: 123, status: :ok)

      # Using a map for metadata
      Echelon.info("API response", %{
        endpoint: "/api/users",
        status: 200,
        response_time_ms: 45
      })
  """
  @spec info(message(), metadata()) :: :ok
  def info(message, metadata \\ []) do
    log(:info, message, metadata)
  end

  @doc """
  Log a message at warn level.

  ## Examples

      Echelon.warn("Slow query detected")
      Echelon.warn("Deprecated API used", function: :old_api)
  """
  @spec warn(message(), metadata()) :: :ok
  def warn(message, metadata \\ []) do
    log(:warn, message, metadata)
  end

  @doc """
  Log a message at error level.

  ## Examples

      Echelon.error("Payment processing failed")
      Echelon.error("Connection timeout", reason: :timeout, retry: 3)
  """
  @spec error(message(), metadata()) :: :ok
  def error(message, metadata \\ []) do
    log(:error, message, metadata)
  end

  @doc """
  Sends a ping signal to the console to verify connectivity.

  Returns `:ok` immediately. The console will display:
  - "pong" if the console is connected and healthy
  - "pang" if the console is disconnected or has errors

  Useful for verifying the Echelon logging system is working during development.

  ## Examples

      Echelon.ping()
      #=> :ok
      # Console displays: "pong" (if connected) or "pang" (if disconnected)

      # Within groups - respects indentation
      Echelon.group("operation", fn ->
        Echelon.ping()
      end)

  """
  @spec ping() :: :ok
  def ping do
    send_marker(:ping, "ping")
  end

  @doc """
  Adds a horizontal rule separator to the log output.

  Inserts a visual separator (---) that respects the current group
  indentation level. Useful for organizing related log sections.

  ## Examples

      Echelon.info("Phase 1 starting")
      Echelon.debug("Processing...")
      Echelon.hr()
      Echelon.info("Phase 2 starting")

      # Within groups - respects indentation
      Echelon.group("operation", fn ->
        Echelon.info("Step 1")
        Echelon.hr()
        Echelon.info("Step 2")
      end)

  """
  @spec hr() :: :ok
  def hr do
    send_marker(:hr, "")
  end

  @doc """
  Enables Echelon logging.

  When enabled, log entries will be sent to the Echelon console (if connected)
  or handled according to the fallback strategy.

  This is the default state - logging is enabled when the application starts.

  ## Examples

      Echelon.on()
      #=> :ok

      Echelon.info("This will be logged")

  """
  @spec on() :: :ok
  def on do
    Echelon.Client.enable()
  end

  @doc """
  Disables Echelon logging.

  When disabled, all log entries are dropped silently. This can be useful
  for temporarily suspending logging in production or during specific operations.

  ## Examples

      Echelon.off()
      #=> :ok

      Echelon.info("This will NOT be logged")

      Echelon.on()
      #=> :ok

      Echelon.info("This will be logged again")

  """
  @spec off() :: :ok
  def off do
    Echelon.Client.disable()
  end

  @doc """
  Returns whether Echelon logging is currently enabled.

  ## Examples

      Echelon.enabled?()
      #=> true

      Echelon.off()
      Echelon.enabled?()
      #=> false

  """
  @spec enabled?() :: boolean()
  def enabled? do
    Echelon.Client.enabled?()
  end

  @doc """
  Enables file logging with an automatically detected filename.

  The filename is generated based on the current git branch name (if available)
  or the node name as a fallback. Files are created in the current working directory.

  ## Examples

      # On git branch "main"
      Echelon.file()
      #=> :ok
      # Creates: echelon_main.log

      # On git branch "feature/user-auth"
      Echelon.file()
      #=> :ok
      # Creates: echelon_feature_user_auth.log

      # When git is not available
      Echelon.file()
      #=> :ok
      # Creates: echelon_<node_name>.log

  After enabling file logging, all subsequent log entries will be written to both
  the terminal and the file.

  ## File Rotation

  Files are automatically rotated when they exceed 10,000 entries or 10MB in size.
  Up to 5 backup files are kept (.1, .2, .3, .4, .5).

  """
  @spec file() :: :ok | {:error, term()}
  def file do
    path = Echelon.FileConfig.deduce_file_path()
    file(path)
  end

  @doc """
  Enables or disables file logging with control over the file path.

  ## Arguments

  - `path` - A string path to the log file, `nil` to auto-detect, or `false` to disable

  ## Examples

      # Enable with explicit path
      Echelon.file("/tmp/my_app.log")
      #=> :ok

      # Enable with auto-detection (same as Echelon.file())
      Echelon.file(nil)
      #=> :ok

      # Disable file logging
      Echelon.file(false)
      #=> :ok

      # Switch to a different file
      Echelon.file("/var/log/app.log")
      #=> :ok

  ## Error Handling

  If the file cannot be opened (due to permissions, invalid path, etc.),
  an error is returned and file logging is disabled:

      Echelon.file("/root/protected.log")
      #=> {:error, :eacces}

  If the Echelon console is not running, an error is returned:

      Echelon.file("/tmp/app.log")
      #=> {:error, :console_not_found}

  Terminal output continues to work regardless of file logging status.

  """
  @spec file(String.t() | nil | false) :: :ok | {:error, term()}
  def file(path_or_control)

  def file(false) do
    case :global.whereis_name(:echelon_console) do
      :undefined ->
        {:error, :console_not_found}

      pid ->
        GenServer.call(pid, :disable_file)
    end
  end

  def file(nil) do
    path = Echelon.FileConfig.deduce_file_path()
    file(path)
  end

  def file(path) when is_binary(path) do
    case :global.whereis_name(:echelon_console) do
      :undefined ->
        {:error, :console_not_found}

      pid ->
        GenServer.call(pid, {:configure_file, path})
    end
  end

  @doc """
  Returns the current log file path, or nil if file logging is disabled.

  ## Examples

      Echelon.file("/tmp/app.log")
      Echelon.file_path()
      #=> "/tmp/app.log"

      Echelon.file(false)
      Echelon.file_path()
      #=> nil

      # When console is not running
      Echelon.file_path()
      #=> nil

  """
  @spec file_path() :: String.t() | nil
  def file_path do
    case :global.whereis_name(:echelon_console) do
      :undefined ->
        nil

      pid ->
        GenServer.call(pid, :get_file_path)
    end
  end

  @doc """
  Lists all registered handlers with their current status.

  Returns a map of handler names to their status information, including
  the handler module and whether it's currently enabled.

  ## Examples

      Echelon.handlers()
      #=> %{
      #=>   file: %{module: Echelon.Console.Handlers.FileLogHandler, enabled: false},
      #=>   database: %{module: MyApp.DatabaseHandler, enabled: true}
      #=> }

      # When console is not running
      Echelon.handlers()
      #=> %{}

  """
  @spec handlers() :: %{atom() => %{module: module(), enabled: boolean()}}
  def handlers do
    case :global.whereis_name(:echelon_console) do
      :undefined ->
        %{}

      pid ->
        GenServer.call(pid, :list_handlers)
    end
  end

  @doc """
  Enables a specific handler at runtime.

  The handler must already be registered in the configuration. This function
  calls the handler's `enable/1` callback to acquire resources.

  ## Arguments

  - `name` - Atom identifying the handler (e.g., `:file`, `:database`)

  ## Examples

      Echelon.enable_handler(:database)
      #=> :ok

      Echelon.enable_handler(:nonexistent)
      #=> {:error, :handler_not_found}

      # When console is not running
      Echelon.enable_handler(:file)
      #=> {:error, :console_not_found}

  """
  @spec enable_handler(atom()) :: :ok | {:error, term()}
  def enable_handler(name) when is_atom(name) do
    case :global.whereis_name(:echelon_console) do
      :undefined ->
        {:error, :console_not_found}

      pid ->
        GenServer.call(pid, {:enable_handler, name})
    end
  end

  @doc """
  Disables a specific handler at runtime.

  This calls the handler's `disable/1` callback to release resources.
  The handler remains registered and can be re-enabled later.

  ## Arguments

  - `name` - Atom identifying the handler (e.g., `:file`, `:database`)

  ## Examples

      Echelon.disable_handler(:database)
      #=> :ok

      Echelon.disable_handler(:nonexistent)
      #=> {:error, :handler_not_found}

      # When console is not running
      Echelon.disable_handler(:file)
      #=> {:error, :console_not_found}

  """
  @spec disable_handler(atom()) :: :ok | {:error, term()}
  def disable_handler(name) when is_atom(name) do
    case :global.whereis_name(:echelon_console) do
      :undefined ->
        {:error, :console_not_found}

      pid ->
        GenServer.call(pid, {:disable_handler, name})
    end
  end

  @doc """
  Groups related log entries with indentation and visual separators.

  All log entries within the function will be indented and surrounded by
  separator lines showing the group name.

  Groups can be nested, with each level adding indentation.

  ## Examples

      Echelon.group("database_transaction", fn ->
        Echelon.info("Starting transaction")
        Echelon.debug("Executing queries", count: 3)
        Echelon.info("Transaction committed")
      end)

      # Nested groups
      Echelon.group("outer", fn ->
        Echelon.info("Outer operation")

        Echelon.group("inner", fn ->
          Echelon.debug("Inner details")
        end)
      end)

  The function's return value is preserved:

      result = Echelon.group("computation", fn ->
        Echelon.debug("Computing...")
        42
      end)
      # result == 42

  ## Error Handling

  If the function raises an exception, the group will be properly closed
  before re-raising:

      Echelon.group("failing_operation", fn ->
        Echelon.info("About to fail")
        raise "error"
      end)
      # Group end marker is sent before exception propagates

  """
  @spec group(String.t(), (() -> result)) :: result when result: any()
  def group(name, func) when is_binary(name) and is_function(func, 0) do
    # Get current stack
    stack = Process.get(:echelon_group_stack, [])

    # Push new group
    new_stack = stack ++ [name]
    Process.put(:echelon_group_stack, new_stack)

    # Send start marker
    send_group_marker(name, :start, new_stack)

    # Execute function with error handling
    try do
      result = func.()

      # Send end marker on success
      send_group_marker(name, :end, new_stack)

      # Pop group
      Process.put(:echelon_group_stack, stack)

      result
    rescue
      exception ->
        # Send end marker on error
        send_group_marker(name, :end, new_stack)

        # Pop group
        Process.put(:echelon_group_stack, stack)

        # Re-raise
        reraise exception, __STACKTRACE__
    end
  end

  # Private implementation
  defp log(level, message, metadata) do
    # Early return if logging is disabled - avoids all metadata collection overhead
    unless Application.get_env(:echelon, :enabled, true) do
      :ok
    else
      # Evaluate lazy messages
      message = if is_function(message, 0), do: message.(), else: message

      # Get current group state
      stack = Process.get(:echelon_group_stack, [])
      group_depth = length(stack)
      group_name = List.last(stack)

      # Build log entry
      entry = %{
        level: level,
        message: message,
        metadata: metadata,
        timestamp: System.system_time(:microsecond),
        node: node(),
        pid: self(),
        app: get_app(),
        group_depth: group_depth,
        group_name: group_name,
        group_marker: nil
      }

      # Send to client
      Echelon.Client.send_log(entry)
    end
  end

  # Send a marker entry (ping, hr, etc.)
  defp send_marker(marker, message) do
    # Early return if logging is disabled
    unless Application.get_env(:echelon, :enabled, true) do
      :ok
    else
      # Get current group state
      stack = Process.get(:echelon_group_stack, [])
      group_depth = length(stack)
      group_name = List.last(stack)

      # Build marker entry
      entry = %{
        level: :info,
        message: message,
        metadata: [],
        timestamp: System.system_time(:microsecond),
        node: node(),
        pid: self(),
        app: get_app(),
        group_depth: group_depth,
        group_name: group_name,
        group_marker: marker
      }

      # Send to client
      Echelon.Client.send_log(entry)
    end
  end

  # Send a group marker entry (start or end)
  defp send_group_marker(name, marker_type, stack) do
    depth = length(stack)

    entry = %{
      level: :info,
      message: "",
      metadata: [],
      timestamp: System.system_time(:microsecond),
      node: node(),
      pid: self(),
      app: get_app(),
      group_depth: depth,
      group_name: name,
      group_marker: marker_type
    }

    Echelon.Client.send_log(entry)
  end

  # Get the application name for the current process
  defp get_app do
    case Process.get(:"$callers") do
      [caller | _] ->
        case :application.get_application(caller) do
          {:ok, app} -> app
          :undefined -> :unknown
        end

      _ ->
        case :application.get_application(self()) do
          {:ok, app} -> app
          :undefined -> :unknown
        end
    end
  end
end
