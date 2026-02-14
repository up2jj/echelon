defmodule Echelon.Console.TerminalDisplay do
  @moduledoc """
  Formats and displays log entries in the terminal with ANSI colors.
  """

  @colors %{
    debug: :cyan,
    info: :green,
    warn: :yellow,
    error: :red
  }

  @level_labels %{
    debug: "DEBUG",
    info: "INFO ",
    warn: "WARN ",
    error: "ERROR"
  }

  @doc """
  Displays a log entry in the terminal with color formatting.

  Supports both keyword list and map metadata.
  """
  def show(entry) do
    timestamp = format_timestamp(entry.timestamp)
    level = entry.level || :info
    level_str = format_level(level)
    node_str = format_node(entry.node)
    message = entry.message || ""
    metadata = entry.metadata || []

    # Build the main log line
    main_line = [
      IO.ANSI.format([
        :faint,
        "[#{timestamp}] "
      ]),
      IO.ANSI.format([
        @colors[level] || :white,
        IO.ANSI.bright(),
        level_str
      ]),
      IO.ANSI.reset(),
      " ",
      IO.ANSI.format([:faint, node_str]),
      " ",
      message
    ]

    IO.puts(main_line)

    # Display metadata if present
    if has_metadata?(metadata) do
      format_metadata(metadata)
      |> IO.puts()
    end

    :ok
  end

  ## Private Functions

  defp format_timestamp(microseconds) when is_integer(microseconds) do
    # Convert microseconds to datetime
    datetime = DateTime.from_unix!(microseconds, :microsecond)
    Calendar.strftime(datetime, "%H:%M:%S.%f")
    |> String.slice(0..-4//1)  # Trim to milliseconds
  end

  defp format_timestamp(_), do: "??:??:??"

  defp format_level(level) do
    @level_labels[level] || "INFO "
  end

  defp format_node(node) when is_atom(node) do
    node
    |> Atom.to_string()
    |> format_node_string()
  end

  defp format_node(_), do: "unknown"

  defp format_node_string(node_str) do
    # Extract just the name part before @ for brevity
    case String.split(node_str, "@") do
      [name, _host] -> name
      [name] -> name
      _ -> node_str
    end
  end

  defp has_metadata?([]), do: false
  defp has_metadata?(metadata) when is_map(metadata), do: map_size(metadata) > 0
  defp has_metadata?(_), do: true

  defp format_metadata(metadata) do
    metadata
    |> Enum.map(fn {key, value} ->
      "  #{key}: #{inspect(value, pretty: true, width: 80)}"
    end)
    |> Enum.join("\n")
    |> then(fn str ->
      IO.ANSI.format([:faint, str, IO.ANSI.reset()])
    end)
  end
end
