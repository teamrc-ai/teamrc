defmodule Teamrc.PIITest do
  use Teamrc.DataCase, async: false

  alias Teamrc.PII

  describe "email_hash/1" do
    test "returns nil for nil input" do
      assert PII.email_hash(nil) == nil
    end

    test "returns nil for empty string" do
      assert PII.email_hash("") == nil
    end

    test "returns a SHA-256 hex string for valid email" do
      hash = PII.email_hash("test@example.com")
      assert is_binary(hash)
      assert String.length(hash) == 64
      assert Regex.match?(~r/^[0-9a-f]{64}$/, hash)
    end

    test "is case-insensitive" do
      assert PII.email_hash("Test@Example.COM") == PII.email_hash("test@example.com")
    end

    test "trims whitespace" do
      assert PII.email_hash("  test@example.com  ") == PII.email_hash("test@example.com")
    end

    test "different emails produce different hashes" do
      refute PII.email_hash("alice@example.com") == PII.email_hash("bob@example.com")
    end
  end

  describe "sanitized_participant/2" do
    @participant %{email: "alice@example.com", display_name: "Alice"}

    test ":self access includes email, display_name, and email_hash" do
      result = PII.sanitized_participant(@participant, :self)
      assert result["email"] == "alice@example.com"
      assert result["display_name"] == "Alice"
      assert is_binary(result["email_hash"])
    end

    test ":owner access includes email, display_name, and email_hash" do
      result = PII.sanitized_participant(@participant, :owner)
      assert result["email"] == "alice@example.com"
      assert result["display_name"] == "Alice"
      assert is_binary(result["email_hash"])
    end

    test ":participant access includes display_name and email_hash but NOT email" do
      result = PII.sanitized_participant(@participant, :participant)
      refute Map.has_key?(result, "email")
      assert result["display_name"] == "Alice"
      assert is_binary(result["email_hash"])
    end

    test ":public access includes only email_hash" do
      result = PII.sanitized_participant(@participant, :public)
      refute Map.has_key?(result, "email")
      refute Map.has_key?(result, "display_name")
      assert is_binary(result["email_hash"])
    end

    test "falls back to email local part for display_name when not provided" do
      result = PII.sanitized_participant(%{email: "bob@example.com"}, :self)
      assert result["display_name"] == "bob"
    end

    test "falls back to 'anonymous' when no email or display_name" do
      result = PII.sanitized_participant(%{}, :self)
      assert result["display_name"] == "anonymous"
    end
  end

  describe "get_user_pii/2" do
    test "returns nil when user_id is nil" do
      assert PII.get_user_pii(nil, "some-id") == nil
    end

    test "returns nil when requesting_user_id is nil" do
      assert PII.get_user_pii("some-id", nil) == nil
    end

    test "returns nil for non-self access" do
      assert PII.get_user_pii("user-1", "user-2") == nil
    end

    test "returns user data for self access" do
      user = Teamrc.AccountsFixtures.user_fixture()
      result = PII.get_user_pii(user.id, user.id)
      assert result["id"] == user.id
      assert result["email"] == user.email
    end
  end
end
