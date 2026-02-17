defmodule Echelon.Helpers do
  @moduledoc """
  Convenience helpers for Echelon logging with shorter function names.

  This module provides short "e"-prefixed aliases for the main Echelon
  logging functions, allowing for more concise logging statements.

  ## Usage

      import Echelon.Helpers

      # Now you can use short aliases instead of Echelon.debug/info/warn/error
      edebug("Starting process")
      einfo("User logged in", user_id: 123)
      ewarn("Slow query detected", duration_ms: 1250)
      eerror("Connection failed", reason: :timeout)

  ## Examples

      import Echelon.Helpers

      # All logging levels with and without metadata
      edebug("Debug message")
      edebug("Query executed", query: sql, duration_ms: 45)

      einfo("Info message")
      einfo("User action", user_id: 123, action: :login)

      ewarn("Warning message")
      ewarn("Slow operation", duration_ms: 1500)

      eerror("Error message")
      eerror("Failed to process", reason: :timeout)

      # Lazy evaluation works too
      edebug(fn -> "Expensive: \#{inspect(large_structure)}" end)

      # Maps as metadata
      einfo("Request completed", %{
        user: %{id: 123, role: :admin},
        metrics: %{duration_ms: 45, db_queries: 3}
      })

  These functions are simple delegations to `Echelon.debug/2`, `Echelon.info/2`,
  `Echelon.warn/2`, and `Echelon.error/2`. See the `Echelon` module for full
  documentation on behavior, lazy evaluation, and metadata handling.
  """

  @type metadata :: keyword() | map()
  @type message :: String.t() | (() -> String.t())

  @doc """
  Log a message at debug level.

  Convenience wrapper for `Echelon.debug/2`.

  ## Examples

      edebug("Starting computation")
      edebug("Query executed", query: "SELECT * FROM users")
      edebug(fn -> "Expensive result" end)
  """
  @spec edebug(message(), metadata()) :: :ok
  def edebug(message, metadata \\ []) do
    Echelon.debug(message, metadata)
  end

  @doc """
  Log a message at info level.

  Convenience wrapper for `Echelon.info/2`.

  ## Examples

      einfo("User logged in")
      einfo("Request processed", user_id: 123, status: :ok)
  """
  @spec einfo(message(), metadata()) :: :ok
  def einfo(message, metadata \\ []) do
    Echelon.info(message, metadata)
  end

  @doc """
  Log a message at warn level.

  Convenience wrapper for `Echelon.warn/2`.

  ## Examples

      ewarn("Slow query detected")
      ewarn("Deprecated API used", function: :old_api)
  """
  @spec ewarn(message(), metadata()) :: :ok
  def ewarn(message, metadata \\ []) do
    Echelon.warn(message, metadata)
  end

  @doc """
  Log a message at error level.

  Convenience wrapper for `Echelon.error/2`.

  ## Examples

      eerror("Payment processing failed")
      eerror("Connection timeout", reason: :timeout, retry: 3)
  """
  @spec eerror(message(), metadata()) :: :ok
  def eerror(message, metadata \\ []) do
    Echelon.error(message, metadata)
  end

  @doc """
  Enables Echelon logging.

  Convenience wrapper for `Echelon.on/0`.

  ## Examples

      eon()
      #=> :ok
  """
  @spec eon() :: :ok
  def eon do
    Echelon.on()
  end

  @doc """
  Disables Echelon logging.

  Convenience wrapper for `Echelon.off/0`.

  ## Examples

      eoff()
      #=> :ok
  """
  @spec eoff() :: :ok
  def eoff do
    Echelon.off()
  end

  @doc """
  Returns whether Echelon logging is currently enabled.

  Convenience wrapper for `Echelon.enabled?/0`.

  ## Examples

      eenabled?()
      #=> true
  """
  @spec eenabled?() :: boolean()
  def eenabled? do
    Echelon.enabled?()
  end

  @doc """
  Groups related log entries with indentation and visual separators.

  Convenience wrapper for `Echelon.group/2`.

  ## Examples

      egroup("database_transaction", fn ->
        einfo("Starting transaction")
        edebug("Executing queries", count: 3)
        einfo("Transaction committed")
      end)

      # Nested groups
      egroup("api_request", fn ->
        einfo("Processing request")

        egroup("validation", fn ->
          edebug("Validating input")
        end)
      end)
  """
  @spec egroup(String.t(), (() -> result)) :: result when result: any()
  def egroup(name, func) do
    Echelon.group(name, func)
  end

  @doc """
  Benchmarks a function and logs timing, memory, and reduction metrics at debug level.

  Convenience wrapper for `Echelon.bench/1`.
  """
  @spec ebench((() -> result)) :: result when result: any()
  def ebench(fun) when is_function(fun, 0) do
    Echelon.bench(fun)
  end

  @doc """
  Benchmarks a labeled function and logs timing, memory, and reduction metrics at debug level.

  Convenience wrapper for `Echelon.bench/2`.
  """
  @spec ebench(String.t(), (() -> result)) :: result when result: any()
  def ebench(label, fun) when is_binary(label) and is_function(fun, 0) do
    Echelon.bench(label, fun)
  end
end
