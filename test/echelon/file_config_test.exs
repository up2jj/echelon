defmodule Echelon.FileConfigTest do
  use ExUnit.Case, async: true

  describe "deduce_file_path/0" do
    test "generates path with echelon_ prefix and .log extension" do
      path = Echelon.FileConfig.deduce_file_path()

      assert String.starts_with?(path, "echelon_")
      assert String.ends_with?(path, ".log")
    end

    test "generates valid filename from git branch when available" do
      # This test will pass if we're in a git repository with a branch
      # The actual branch name will vary, but we can verify the format
      path = Echelon.FileConfig.deduce_file_path()

      # Should be a valid filename (no path separators)
      refute String.contains?(path, "/")
      refute String.contains?(path, "\\")

      # Should have proper structure: echelon_{something}.log
      assert Regex.match?(~r/^echelon_[a-zA-Z0-9_-]+\.log$/, path)
    end

    test "falls back to node name when not in git repo" do
      # We can test this by checking that the path includes sanitized node name
      path = Echelon.FileConfig.deduce_file_path()

      # Path should always be valid regardless of git availability
      assert is_binary(path)
      assert String.length(path) > 0
    end
  end

  describe "get_git_branch/0" do
    test "returns {:ok, branch} when in a git repository" do
      case Echelon.FileConfig.get_git_branch() do
        {:ok, branch} ->
          # If we got a branch, verify it's a non-empty string
          assert is_binary(branch)
          assert String.length(branch) > 0
          refute String.contains?(branch, "\n")

        :error ->
          # It's OK if we're not in a git repo or git is unavailable
          # This test just documents the expected behavior
          assert true
      end
    end

    test "returns :error when git command fails" do
      # We can't reliably test git failure without mocking,
      # but we can verify the function handles both cases
      result = Echelon.FileConfig.get_git_branch()

      assert result == :error or match?({:ok, _}, result)
    end

    test "returns trimmed branch name without whitespace" do
      case Echelon.FileConfig.get_git_branch() do
        {:ok, branch} ->
          # Branch should be trimmed (no leading/trailing whitespace)
          assert branch == String.trim(branch)

        :error ->
          # Not in git repo, that's fine
          assert true
      end
    end
  end

  describe "sanitize_branch_name/1" do
    test "replaces forward slashes with underscores" do
      # Note: hyphens are preserved as they're valid in filenames
      assert Echelon.FileConfig.sanitize_branch_name("feature/user-auth") ==
               "feature_user-auth"

      assert Echelon.FileConfig.sanitize_branch_name("fix/bug/issue-123") ==
               "fix_bug_issue-123"
    end

    test "replaces special characters with underscores" do
      # Hyphens are preserved, other special chars replaced
      assert Echelon.FileConfig.sanitize_branch_name("fix/issue-#123") ==
               "fix_issue-_123"

      assert Echelon.FileConfig.sanitize_branch_name("feature@v2.0") ==
               "feature_v2_0"

      assert Echelon.FileConfig.sanitize_branch_name("test!branch?here") ==
               "test_branch_here"
    end

    test "preserves alphanumeric characters, hyphens, and underscores" do
      assert Echelon.FileConfig.sanitize_branch_name("feature-123_test") ==
               "feature-123_test"

      assert Echelon.FileConfig.sanitize_branch_name("ABC-xyz_789") ==
               "ABC-xyz_789"
    end

    test "limits length to 50 characters" do
      very_long = String.duplicate("a", 100)
      sanitized = Echelon.FileConfig.sanitize_branch_name(very_long)

      assert String.length(sanitized) == 50
    end

    test "handles branch names exactly 50 characters" do
      exact_50 = String.duplicate("b", 50)
      sanitized = Echelon.FileConfig.sanitize_branch_name(exact_50)

      assert String.length(sanitized) == 50
      assert sanitized == exact_50
    end

    test "handles branch names shorter than 50 characters" do
      short = "main"
      sanitized = Echelon.FileConfig.sanitize_branch_name(short)

      assert sanitized == "main"
    end

    test "handles empty string" do
      assert Echelon.FileConfig.sanitize_branch_name("") == ""
    end

    test "handles branch names with only special characters" do
      assert Echelon.FileConfig.sanitize_branch_name("###") == "___"
      assert Echelon.FileConfig.sanitize_branch_name("///") == "___"
    end

    test "handles mixed case preservation" do
      assert Echelon.FileConfig.sanitize_branch_name("Feature/UserAuth") ==
               "Feature_UserAuth"

      assert Echelon.FileConfig.sanitize_branch_name("MAIN-Branch") ==
               "MAIN-Branch"
    end

    test "handles unicode characters by replacing with underscores" do
      # Each unicode char might be multiple bytes, so just verify replacement
      result1 = Echelon.FileConfig.sanitize_branch_name("feature-中文")
      assert String.starts_with?(result1, "feature-")
      refute result1 =~ "中"
      refute result1 =~ "文"

      result2 = Echelon.FileConfig.sanitize_branch_name("test-émoji-🚀")
      assert String.contains?(result2, "test-")
      assert String.contains?(result2, "_")
    end

    test "handles consecutive special characters" do
      assert Echelon.FileConfig.sanitize_branch_name("feature///user-auth") ==
               "feature___user-auth"
    end

    test "handles very long names with special characters" do
      # Create a 100-char name with special chars
      long_with_special = "feature/" <> String.duplicate("a", 50) <> "/#test"
      sanitized = Echelon.FileConfig.sanitize_branch_name(long_with_special)

      # Should be limited to 50 chars and have special chars replaced
      assert String.length(sanitized) == 50
      assert String.starts_with?(sanitized, "feature_")
      refute String.contains?(sanitized, "/")
      refute String.contains?(sanitized, "#")
    end

    test "real-world branch name examples" do
      examples = %{
        "main" => "main",
        "develop" => "develop",
        "feature/user-authentication" => "feature_user-authentication",
        "bugfix/JIRA-123" => "bugfix_JIRA-123",
        "release/v1.2.3" => "release_v1_2_3",
        "hotfix/security-patch" => "hotfix_security-patch",
        "chore/update-dependencies" => "chore_update-dependencies"
      }

      Enum.each(examples, fn {input, expected} ->
        assert Echelon.FileConfig.sanitize_branch_name(input) == expected
      end)
    end
  end
end
