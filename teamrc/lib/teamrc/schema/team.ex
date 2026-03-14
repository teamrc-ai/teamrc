defmodule Teamrc.Schema.Team do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "teams" do
    field :name, :string
    field :skills, {:array, :map}, default: []
    field :platforms, {:array, :string}, default: []
    field :knowledge, :string
    field :visibility, :string, default: "private"
    field :clone_token, :string
    field :owner_user_id, :binary_id
    field :owner_claim_secret, :string
    field :members_hash, :string
    field :skills_hash, :string
    field :knowledge_hash, :string
    field :deleted_at, :utc_datetime
    has_many :members, Teamrc.Schema.Member
    has_many :invites, Teamrc.Schema.Invite

    timestamps(type: :utc_datetime)
  end

  @id_re ~r/^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$/

  def changeset(team, attrs) do
    team
    |> cast(attrs, [
      :name,
      :skills,
      :platforms,
      :knowledge,
      :visibility,
      :clone_token,
      :owner_user_id,
      :owner_claim_secret,
      :members_hash,
      :skills_hash,
      :knowledge_hash
    ])
    |> validate_required([:name])
    |> validate_length(:name, max: 64)
    |> validate_length(:knowledge, max: 100_000)
    |> validate_format(:name, ~r/^[a-zA-Z0-9][a-zA-Z0-9 _-]*$/)
    |> validate_inclusion(:visibility, ["public", "private"])
    |> check_constraint(:visibility, name: :visibility_check, message: "must be 'public' or 'private'")
    |> unique_constraint(:clone_token)
    |> validate_entry_ids(:skills)
  end

  defp validate_entry_ids(changeset, field) do
    validate_change(changeset, field, fn _, entries ->
      invalid =
        Enum.find(entries, fn entry ->
          id = entry["id"] || entry[:id]
          not is_binary(id) or not Regex.match?(@id_re, id)
        end)

      case invalid do
        nil -> []
        _ -> [{field, "contains an entry with an invalid ID (must be 1-64 alphanumeric, hyphens, or underscores)"}]
      end
    end)
  end
end
