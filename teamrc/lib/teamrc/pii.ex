defmodule Teamrc.PII do
  @moduledoc """
  Controlled access to Personally Identifiable Information.
  All PII reads must go through this module.
  Never return raw PII in team/sync API responses.

  ## Access Levels

  - `:self` — user accessing their own data (full access: email, display_name)
  - `:owner` — team owner accessing participant data (email visible)
  - `:participant` — team member (display_name only)
  - `:public` — anonymous (email_hash only, for Gravatar)
  """

  @type access_level :: :self | :owner | :participant | :public

  @doc """
  Returns a sanitized view of participant data based on the caller's access level.

  The `participant_data` map may contain:
  - `"email"` or `:email` — the participant's email address
  - `"display_name"` or `:display_name` — a human-readable display name

  Returns a map with only the fields appropriate for the access level.
  """
  @spec sanitized_participant(map(), access_level()) :: map()
  def sanitized_participant(participant_data, :self) do
    email = get_field(participant_data, :email)
    display_name = get_field(participant_data, :display_name) || email_to_display_name(email)

    %{
      "email" => email,
      "display_name" => display_name,
      "email_hash" => email_hash(email)
    }
  end

  def sanitized_participant(participant_data, :owner) do
    email = get_field(participant_data, :email)
    display_name = get_field(participant_data, :display_name) || email_to_display_name(email)

    %{
      "email" => email,
      "display_name" => display_name,
      "email_hash" => email_hash(email)
    }
  end

  def sanitized_participant(participant_data, :participant) do
    email = get_field(participant_data, :email)
    display_name = get_field(participant_data, :display_name) || email_to_display_name(email)

    %{
      "display_name" => display_name,
      "email_hash" => email_hash(email)
    }
  end

  def sanitized_participant(participant_data, :public) do
    email = get_field(participant_data, :email)

    %{
      "email_hash" => email_hash(email)
    }
  end

  @doc """
  Returns full PII for a user only if the requesting user is the same user.
  Returns `nil` for non-self access.

  This function is intended for account detail endpoints where a user
  views their own profile data.
  """
  @spec get_user_pii(String.t() | nil, String.t() | nil) :: map() | nil
  def get_user_pii(nil, _requesting_user_id), do: nil
  def get_user_pii(_user_id, nil), do: nil

  def get_user_pii(user_id, requesting_user_id) when user_id == requesting_user_id do
    case Teamrc.Repo.get(Teamrc.Accounts.User, user_id) do
      nil ->
        nil

      user ->
        %{
          "id" => user.id,
          "email" => user.email,
          "created_at" => user.inserted_at,
          "updated_at" => user.updated_at
        }
    end
  end

  def get_user_pii(_user_id, _requesting_user_id), do: nil

  @doc """
  Computes a SHA-256 hash of the email address for use as a Gravatar-compatible
  identifier. The email is lowercased and trimmed before hashing.

  Returns `nil` if the email is nil or empty.
  """
  @spec email_hash(String.t() | nil) :: String.t() | nil
  def email_hash(nil), do: nil
  def email_hash(""), do: nil

  def email_hash(email) when is_binary(email) do
    email
    |> String.trim()
    |> String.downcase()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  # --- Private Helpers ---

  defp get_field(data, key) when is_atom(key) do
    Map.get(data, key) || Map.get(data, Atom.to_string(key))
  end

  defp email_to_display_name(nil), do: "anonymous"
  defp email_to_display_name(""), do: "anonymous"

  defp email_to_display_name(email) when is_binary(email) do
    case String.split(email, "@", parts: 2) do
      [local | _] -> local
      _ -> "anonymous"
    end
  end
end
