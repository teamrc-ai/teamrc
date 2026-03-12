defmodule Teamrc.Schema.DeviceAuthRequest do
  @moduledoc "Ecto schema for device authorization requests."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "device_auth_requests" do
    field :user_code, :string
    field :device_code, :string
    field :token, :string
    field :status, :string, default: "pending"
    field :expires_at, :utc_datetime
    field :account_id, :binary_id
    field :email, :string
    field :failed_attempts, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  def changeset(request, attrs) do
    request
    |> cast(attrs, [:user_code, :device_code, :token, :status, :expires_at, :account_id, :email, :failed_attempts])
    |> validate_required([:user_code, :device_code, :token, :status, :expires_at])
    |> validate_inclusion(:status, ["pending", "confirmed"])
    |> unique_constraint(:user_code)
    |> unique_constraint(:device_code)
  end
end
