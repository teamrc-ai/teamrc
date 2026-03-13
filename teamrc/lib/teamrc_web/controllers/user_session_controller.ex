defmodule TeamrcWeb.UserSessionController do
  use TeamrcWeb, :controller

  alias Teamrc.Accounts
  alias TeamrcWeb.UserAuth

  def register(conn, %{"user" => user_params}) do
    attrs = %{
      "email" => user_params["email"],
      "password" => user_params["password"],
      "terms_accepted" => user_params["terms_accepted"]
    }

    case Accounts.register_user_with_password(attrs) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "Account created successfully!")
        |> UserAuth.log_in_user(user, %{"remember_me" => "true"})

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Registration failed. Please check your information and try again.")
        |> redirect(to: ~p"/users/register")
    end
  end

  def create(conn, %{"_action" => "confirmed"} = params) do
    create(conn, params, "User confirmed successfully.")
  end

  def create(conn, params) do
    create(conn, params, "Welcome back!")
  end

  # magic link login
  defp create(conn, %{"user" => %{"token" => token} = user_params}, info) do
    case Accounts.login_user_by_magic_link(token) do
      {:ok, {user, tokens_to_disconnect}} ->
        UserAuth.disconnect_sessions(tokens_to_disconnect)
        log_in_with_tos_check(conn, user, user_params, info)

      _ ->
        conn
        |> put_flash(:error, "The link is invalid or it has expired.")
        |> redirect(to: ~p"/users/log-in")
    end
  end

  # email + password login
  defp create(conn, %{"user" => user_params}, info) do
    %{"email" => email, "password" => password} = user_params

    if user = Accounts.get_user_by_email_and_password(email, password) do
      log_in_with_tos_check(conn, user, user_params, info)
    else
      # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
      conn
      |> put_flash(:error, "Invalid email or password")
      |> put_flash(:email, String.slice(email, 0, 160))
      |> redirect(to: ~p"/users/log-in")
    end
  end

  # Gate login on ToS acceptance. If not accepted, log in but redirect to accept-terms.
  # Extra session values are passed to log_in_user/4 to persist through session renewal,
  # since create_or_extend_session may call clear_session for new logins.
  defp log_in_with_tos_check(conn, user, user_params, info) do
    if is_nil(user.accepted_terms_at) do
      original_return = get_session(conn, :user_return_to)

      persist =
        [{:pending_oauth_user_id, user.id}] ++
          if(original_return, do: [{:post_tos_return_to, original_return}], else: [])

      conn
      |> put_session(:user_return_to, ~p"/users/accept-terms")
      |> put_flash(:info, "Please accept the Terms of Service to continue.")
      |> UserAuth.log_in_user(user, user_params, persist)
    else
      conn
      |> put_flash(:info, info)
      |> UserAuth.log_in_user(user, user_params)
    end
  end

  def update_password(conn, %{"user" => user_params} = params) do
    user = conn.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)
    {:ok, {_user, expired_tokens}} = Accounts.update_user_password(user, user_params)

    # disconnect all existing LiveViews with old sessions
    UserAuth.disconnect_sessions(expired_tokens)

    conn
    |> put_session(:user_return_to, ~p"/users/settings")
    |> create(params, "Password updated successfully!")
  end

  @doc "Complete login after ToS acceptance. Logs in user from pending OAuth session or existing session."
  def terms_accepted(conn, _params) do
    # Restore the original return destination saved before the ToS detour
    conn =
      case get_session(conn, :post_tos_return_to) do
        nil -> conn
        path ->
          conn
          |> put_session(:user_return_to, path)
          |> delete_session(:post_tos_return_to)
      end

    # Try existing authenticated user first, then fall back to pending OAuth user
    user =
      case conn.assigns[:current_scope] do
        %{user: %{accepted_terms_at: at} = u} when not is_nil(at) -> u
        _ ->
          pending_at = get_session(conn, :pending_oauth_at)
          expired = is_nil(pending_at) or System.system_time(:second) - pending_at > 600

          case {expired, get_session(conn, :pending_oauth_user_id)} do
            {true, _} -> nil
            {false, nil} -> nil
            {false, user_id} -> Teamrc.Accounts.get_user(user_id)
          end
      end

    case user do
      %{accepted_terms_at: at} when not is_nil(at) ->
        conn
        |> delete_session(:pending_oauth_user_id)
        |> delete_session(:pending_oauth_at)
        |> UserAuth.log_in_user(user, %{"remember_me" => "true"})

      _ ->
        conn
        |> put_flash(:error, "Please log in again.")
        |> redirect(to: ~p"/users/log-in")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end

  def forgot_password(conn, %{"user" => %{"email" => email}}) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_user_reset_password_instructions(
        user,
        &url(~p"/users/reset-password/#{&1}")
      )
    end

    # Always return the same response to prevent user enumeration
    conn
    |> put_flash(:info, "If your email is in our system, you will receive reset instructions shortly.")
    |> redirect(to: ~p"/users/log-in")
  end

  def reset_password(conn, %{"token" => token, "user" => user_params}) do
    case Accounts.get_user_by_reset_password_token(token) do
      nil ->
        conn
        |> put_flash(:error, "Reset password link is invalid or it has expired.")
        |> redirect(to: ~p"/users/forgot-password")

      user ->
        case Accounts.reset_user_password(user, user_params) do
          {:ok, {_user, expired_tokens}} ->
            UserAuth.disconnect_sessions(expired_tokens)

            conn
            |> put_flash(:info, "Password reset successfully.")
            |> redirect(to: ~p"/users/log-in")

          {:error, _changeset} ->
            conn
            |> put_flash(:error, "Failed to reset password. Please try again.")
            |> redirect(to: ~p"/users/reset-password/#{token}")
        end
    end
  end
end
