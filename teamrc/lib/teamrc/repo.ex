defmodule Teamrc.Repo do
  use Ecto.Repo,
    otp_app: :teamrc,
    adapter: Ecto.Adapters.Postgres
end
