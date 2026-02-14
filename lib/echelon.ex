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

  # Private implementation
  defp log(level, message, metadata) do
    # Evaluate lazy messages
    message = if is_function(message, 0), do: message.(), else: message

    # Build log entry
    entry = %{
      level: level,
      message: message,
      metadata: metadata,
      timestamp: System.system_time(:microsecond),
      node: node(),
      pid: self(),
      app: get_app()
    }

    # Send to client
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
