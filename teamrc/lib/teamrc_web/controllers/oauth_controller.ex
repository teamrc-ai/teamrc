defmodule TeamrcWeb.OAuthController do
  @moduledoc """
  Handles OAuth callbacks from GitHub and Google via Ueberauth.

  The request phase is handled automatically by Ueberauth's plug pipeline.
  This controller only implements the callback phase.
  """

  use TeamrcWeb, :controller

  plug Ueberauth

  alias Teamrc.Accounts
  alias TeamrcWeb.UserAuth

  @doc """
  Handles the OAuth callback from the provider.

  Extracts the auth info from the Ueberauth struct, finds or creates the user,
  checks terms acceptance, and logs them in.
  """
  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    provider = to_string(auth.provider)
    uid = to_string(auth.uid)

    info = %{
      email: auth.info.email,
      avatar_url: auth.info.image
    }

    case Accounts.find_or_create_oauth_user(provider, uid, info) do
      {:ok, user} ->
        if is_nil(user.accepted_terms_at) do
          # User needs to accept ToS before getting a session.
          # Preserve any redirect_to from session under :post_tos_return_to
          # so it survives the ToS acceptance flow.
          original_return = get_session(conn, :user_return_to)

          conn
          |> put_session(:pending_oauth_user_id, user.id)
          |> put_session(:pending_oauth_at, System.system_time(:second))
          |> then(fn c ->
            if original_return,
              do: put_session(c, :post_tos_return_to, original_return),
              else: c
          end)
          |> redirect(to: ~p"/users/accept-terms")
        else
          conn
          |> put_flash(:info, "Welcome!")
          |> UserAuth.log_in_user(user)
        end

      {:error, :oauth_provider_mismatch} ->
        conn
        |> put_flash(:error, "Authentication failed. Please try again.")
        |> redirect(to: ~p"/users/log-in")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Authentication failed. Please try again.")
        |> redirect(to: ~p"/users/log-in")
    end
  end

  def callback(%{assigns: %{ueberauth_failure: failure}} = conn, _params) do
    require Logger
    Logger.error("Ueberauth failure: #{inspect(failure)}")

    conn
    |> put_flash(:error, "Authentication failed. Please try again.")
    |> redirect(to: ~p"/users/log-in")
  end
end
