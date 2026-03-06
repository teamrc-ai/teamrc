defmodule TeamrcWeb.Plugs.ApiErrorHandler do
  @moduledoc """
  Catches unhandled exceptions in API routes and returns safe JSON errors.
  Prevents leaking stack traces, Ecto internals, or other sensitive details.
  """

  require Logger

  defmacro __using__(_opts) do
    quote do
      use Plug.ErrorHandler
      require Logger

      @impl Plug.ErrorHandler
      def handle_errors(conn, %{kind: _kind, reason: %Ecto.NoResultsError{}, stack: _stack}) do
        conn
        |> put_status(:not_found)
        |> Phoenix.Controller.json(%{error: "not_found"})
      end

      def handle_errors(conn, %{kind: kind, reason: reason, stack: stack}) do
        Logger.error(
          "Unhandled #{kind} in API: #{inspect(reason)}\n#{Exception.format_stacktrace(stack)}"
        )

        conn
        |> put_status(:internal_server_error)
        |> Phoenix.Controller.json(%{error: "internal_error"})
      end
    end
  end
end
