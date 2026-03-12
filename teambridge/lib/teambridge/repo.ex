defmodule Teambridge.Repo do
  use Ecto.Repo,
    otp_app: :teambridge,
    adapter: Ecto.Adapters.Postgres
end
