defmodule Echelon.FileConfig do
  @moduledoc """
  Utilities for file configuration and path generation.

  Provides functionality to automatically deduce log file paths based on
  git branch names or node names, ensuring safe and valid file names.
  """

  @doc """
  Generates a log file path automatically.

  Attempts to detect the current git branch and use it in the filename.
  Falls back to the node name if git is unavailable or fails.

  Returns a filename in the current working directory.

  ## Examples

      iex> Echelon.FileConfig.deduce_file_path()
      "echelon_main.log"

      iex> Echelon.FileConfig.deduce_file_path()
      "echelon_feature_user_auth.log"

  """
  @spec deduce_file_path() :: String.t()
  def deduce_file_path do
    case get_git_branch() do
      {:ok, branch} ->
        sanitized = sanitize_branch_name(branch)
        "echelon_#{sanitized}.log"

      :error ->
        # Fallback to node name
        node_name = get_node_name()
        "echelon_#{node_name}.log"
    end
  end

  @doc """
  Attempts to get the current git branch name.

  Uses `git branch --show-current` command. Returns `{:ok, branch}` on success
  or `:error` if git is unavailable or the command fails.

  ## Examples

      iex> Echelon.FileConfig.get_git_branch()
      {:ok, "main"}

      iex> Echelon.FileConfig.get_git_branch()
      :error

  """
  @spec get_git_branch() :: {:ok, String.t()} | :error
  def get_git_branch do
    case System.cmd("git", ["branch", "--show-current"], stderr_to_stdout: true) do
      {output, 0} ->
        branch = String.trim(output)

        if branch != "" do
          {:ok, branch}
        else
          :error
        end

      _ ->
        :error
    end
  rescue
    # git command not found or System.cmd fails
    _ -> :error
  end

  @doc """
  Sanitizes a branch name to be safe for use in a filename.

  Replaces special characters with underscores and limits the length
  to 50 characters to ensure compatibility across filesystems.

  ## Examples

      iex> Echelon.FileConfig.sanitize_branch_name("feature/user-auth")
      "feature_user_auth"

      iex> Echelon.FileConfig.sanitize_branch_name("fix/issue-#123")
      "fix_issue_123"

      iex> very_long = String.duplicate("a", 100)
      iex> sanitized = Echelon.FileConfig.sanitize_branch_name(very_long)
      iex> String.length(sanitized)
      50

  """
  @spec sanitize_branch_name(String.t()) :: String.t()
  def sanitize_branch_name(branch) when is_binary(branch) do
    branch
    |> String.replace(~r/[^a-zA-Z0-9_-]/, "_")
    |> String.slice(0..49)
  end

  # Private helper to extract node name
  defp get_node_name do
    Node.self()
    |> to_string()
    |> String.split("@")
    |> List.first()
    |> sanitize_branch_name()
  end
end
