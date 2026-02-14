defmodule Echelon.Console.LogHandler do
  @moduledoc """
  Behaviour for log output handlers.

  Handlers receive log entries and write them to various outputs
  (files, databases, external services, etc.). Each handler manages
  its own state within the server's state map.

  Handlers are stateless modules - all state is passed in and returned.

  ## Implementing a Handler

  To create a custom handler, implement all required callbacks:

      defmodule MyApp.CustomHandler do
        @behaviour Echelon.Console.LogHandler

        @impl true
        def init do
          %{enabled: false, custom_state: nil}
        end

        @impl true
        def enable(state) do
          # Acquire resources (open connections, files, etc.)
          {:ok, %{state | enabled: true}}
        end

        @impl true
        def disable(state) do
          # Release resources
          {:ok, %{state | enabled: false}}
        end

        @impl true
        def handle_entry(entry, state) do
          # Process the log entry
          {:ok, state}
        end

        @impl true
        def enabled?(state) do
          state.enabled
        end
      end

  ## Registering a Handler

  Handlers are registered in `Console.Server.init/1`:

      handlers: %{
        file: {FileLogHandler, FileLogHandler.init()},
        custom: {MyApp.CustomHandler, MyApp.CustomHandler.init()}
      }

  """

  @doc """
  Called when the handler is first initialized.

  Returns initial handler state based on application configuration.
  Should not perform side effects - use enable/1 for that.

  ## Examples

      def init do
        config = Application.get_env(:echelon, :file, [])
        %{
          enabled: Keyword.get(config, :enabled, false),
          path: Keyword.get(config, :path),
          # ... other config
        }
      end

  """
  @callback init() :: handler_state :: map()

  @doc """
  Called when the handler is enabled (either at startup or via API).

  Should perform resource acquisition (open files, connect to databases, etc.).
  Returns `{:ok, new_state}` on success or `{:error, reason}` on failure.

  ## Examples

      def enable(state) do
        case File.open(state.path, [:write, :utf8, :append]) do
          {:ok, io_device} ->
            {:ok, %{state | io_device: io_device, enabled: true}}
          {:error, reason} ->
            {:error, reason}
        end
      end

  """
  @callback enable(handler_state :: map()) ::
              {:ok, new_state :: map()} | {:error, reason :: term()}

  @doc """
  Called when the handler is disabled.

  Should perform cleanup (close files, disconnect, etc.).
  Always returns `{:ok, new_state}` - cleanup failures should be logged
  but not propagated.

  ## Examples

      def disable(state) do
        if state.io_device do
          File.close(state.io_device)
        end
        {:ok, %{state | io_device: nil, enabled: false}}
      end

  """
  @callback disable(handler_state :: map()) :: {:ok, new_state :: map()}

  @doc """
  Called for each log entry when the handler is enabled.

  Should write the entry to the output destination.
  Returns `{:ok, new_state}` on success or `{:error, reason}` on failure.

  On error, the server may disable the handler automatically.

  ## Examples

      def handle_entry(entry, state) do
        formatted = format_entry(entry)
        case IO.write(state.io_device, formatted) do
          :ok ->
            {:ok, update_counters(state, formatted)}
          {:error, reason} ->
            {:error, reason}
        end
      end

  """
  @callback handle_entry(entry :: map(), handler_state :: map()) ::
              {:ok, new_state :: map()} | {:error, reason :: term()}

  @doc """
  Returns whether the handler is currently enabled.

  This is checked before calling `handle_entry/2` for each log entry.

  ## Examples

      def enabled?(state) do
        state.enabled and state.io_device != nil
      end

  """
  @callback enabled?(handler_state :: map()) :: boolean()

  @doc """
  Called during server termination.

  Should perform final cleanup. Like `disable/1`, should always succeed.
  This callback is optional - if not implemented, `disable/1` will be called instead.

  ## Examples

      def terminate(state) do
        close_connections(state)
        :ok
      end

  """
  @callback terminate(handler_state :: map()) :: :ok

  @optional_callbacks [terminate: 1]
end
