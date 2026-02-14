defmodule Echelon.Console.FileDisplay do
  @moduledoc """
  Formats log entries as plain text for file output.

  Similar to TerminalDisplay but without ANSI color codes, suitable for
  writing to log files. Returns formatted strings instead of printing.
  """

  @level_labels %{
    debug: "DEBUG",
    info: "INFO ",
    warn: "WARN ",
    error: "ERROR"
  }

  @doc """
  Formats a log entry as a plain text string.

  Handles group markers for visual grouping of related entries.
  Returns a formatted string ready to be written to a file.

  ## Examples

      iex> entry = %{level: :info, message: "Test", metadata: [], timestamp: 1234567890000000, node: :myapp@localhost, pid: self()}
      iex> Echelon.Console.FileDisplay.format_entry(entry)
      "[HH:MM:SS.mmm] INFO  myapp Test\\n"

  """
  @spec format_entry(map()) :: String.t()
  def format_entry(entry) do
    case entry[:group_marker] do
      :start -> format_group_start(entry)
      :end -> format_group_end(entry)
      :ping -> format_ping(entry)
      :hr -> format_hr(entry)
      nil -> format_regular_entry(entry)
    end
  end

  ## Private Functions

  # Format group start separator
  defp format_group_start(entry) do
    name = entry[:group_name] || "unnamed"
    depth = entry[:group_depth] || 0
    indent = String.duplicate("  ", max(0, depth - 1))

    "#{indent}▶ #{name} ▶\n"
  end

  # Format group end separator
  defp format_group_end(entry) do
    name = entry[:group_name] || "unnamed"
    depth = entry[:group_depth] || 0
    indent = String.duplicate("  ", max(0, depth - 1))

    "#{indent}◀ #{name} ◀\n"
  end

  # Format ping entry for file output
  defp format_ping(entry) do
    depth = entry[:group_depth] || 0
    indent = String.duplicate("  ", depth)
    message = entry[:message] || "pong"

    "#{indent}#{message}\n"
  end

  # Format horizontal rule for file output
  defp format_hr(entry) do
    depth = entry[:group_depth] || 0
    indent = String.duplicate("  ", depth)

    "#{indent}---\n"
  end

  # Format regular log entry with indentation
  defp format_regular_entry(entry) do
    timestamp = format_timestamp(entry.timestamp)
    level = entry.level || :info
    level_str = format_level(level)
    node_str = format_node(entry.node)
    message = entry.message || ""
    metadata = entry.metadata || []

    # Calculate indentation based on group depth
    depth = entry[:group_depth] || 0
    indent = String.duplicate("  ", depth)

    # Build the main log line with indentation
    main_line = "#{indent}[#{timestamp}] #{level_str} #{node_str} #{message}\n"

    # Add metadata if present (with extra indentation)
    if has_metadata?(metadata) do
      metadata_str = format_metadata(metadata, indent)
      main_line <> metadata_str
    else
      main_line
    end
  end

  ## Formatting Helpers

  defp format_timestamp(microseconds) when is_integer(microseconds) do
    # Convert microseconds to datetime
    datetime = DateTime.from_unix!(microseconds, :microsecond)

    Calendar.strftime(datetime, "%H:%M:%S.%f")
    |> String.slice(0..-4//1)
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

  defp format_metadata(metadata, base_indent) do
    metadata
    |> Enum.map(fn {key, value} ->
      "#{base_indent}  #{key}: #{inspect(value, pretty: true, width: 80)}"
    end)
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end
end
