defmodule Teamrc.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Teamrc.Accounts` context.
  """

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"
  def valid_user_password, do: "hello_world_1234"

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_user_email(),
      accepted_terms_at: DateTime.utc_now(:second),
      terms_version_accepted: "2026-03-11"
    })
  end

  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> Teamrc.Accounts.register_user()

    user
  end

  def user_with_password_fixture(attrs \\ %{}) do
    email = attrs[:email] || unique_user_email()
    password = attrs[:password] || valid_user_password()

    {:ok, user} =
      Teamrc.Accounts.register_user(%{
        email: email,
        accepted_terms_at: DateTime.utc_now(:second),
        terms_version_accepted: "2026-03-11"
      })

    # Set password directly
    {:ok, {user, _tokens}} =
      user
      |> Teamrc.Accounts.User.password_changeset(%{password: password})
      |> Teamrc.Repo.update()
      |> case do
        {:ok, user} -> {:ok, {user, []}}
        error -> error
      end

    %{user | password: password}
  end

  def oauth_user_fixture(attrs \\ %{}) do
    provider = attrs[:provider] || "github"
    uid = attrs[:provider_uid] || "#{System.unique_integer([:positive])}"
    email = attrs[:email] || unique_user_email()

    {:ok, user} =
      Teamrc.Accounts.find_or_create_oauth_user(provider, uid, %{
        email: email,
        avatar_url: attrs[:avatar_url]
      })

    user
  end

  def extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end
end
