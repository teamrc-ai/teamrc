defmodule Teamrc.PIILeakTest do
  @moduledoc """
  Static analysis tests to verify PII is not leaked in API responses.
  Ensures raw email addresses are never exposed in team/sync API responses.
  """
  use ExUnit.Case, async: true

  @api_controller_path Path.expand(
                         "../../lib/teamrc_web/controllers/api_controller.ex",
                         __DIR__
                       )

  @account_controller_path Path.expand(
                             "../../lib/teamrc_web/controllers/account_controller.ex",
                             __DIR__
                           )

  describe "API controller does not leak raw participant emails" do
    test "api_controller.ex does not return raw participant emails in JSON responses" do
      content = File.read!(@api_controller_path)

      # The API controller should use PII.email_hash or sanitized_participant
      # when handling participant data, never raw .email on participants
      refute content =~ "participant.email" or content =~ "participant[\"email\"]",
             "API controller should not reference raw participant email"
    end
  end

  describe "export endpoint hashes participant emails" do
    test "account_controller.ex exports reference PII module or email_hash" do
      content = File.read!(@account_controller_path)

      # The export should go through accounts.ex which hashes emails
      # Just verify it doesn't manually iterate participants with raw emails
      refute content =~ ~r/participants.*\.email\b/,
             "Account controller should not expose raw participant emails in export"
    end
  end

  describe "no Clerk references remain in source" do
    @source_dir Path.expand("../../lib", __DIR__)

    test "no files reference Clerk in module names or function calls" do
      files =
        Path.wildcard(Path.join(@source_dir, "**/*.ex"))
        |> Enum.reject(&String.contains?(&1, "_build"))

      violations =
        Enum.flat_map(files, fn file ->
          content = File.read!(file)

          if content =~ ~r/clerk/i and
               not (content =~ ~r/# (old|legacy|removed|was).*clerk/i) do
            [{file, "contains Clerk reference"}]
          else
            []
          end
        end)

      assert violations == [],
             "Found Clerk references in source files:\n#{inspect(violations, pretty: true)}"
    end
  end
end
