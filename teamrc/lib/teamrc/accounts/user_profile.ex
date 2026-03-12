defmodule Teamrc.Accounts.UserProfile do
  @moduledoc "Schema for user profile information (PII-separated from auth-sensitive users table)."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "user_profiles" do
    field :display_name, :string
    field :bio, :string
    belongs_to :user, Teamrc.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(profile, attrs) do
    profile
    |> cast(attrs, [:user_id, :display_name, :bio])
    |> validate_required([:user_id])
    |> validate_length(:display_name, max: 100)
    |> validate_length(:bio, max: 500)
    |> unique_constraint(:user_id)
  end
end
