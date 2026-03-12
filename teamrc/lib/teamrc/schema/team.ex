defmodule Teamrc.Schema.Team do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "teams" do
    field :name, :string
    field :rules, {:array, :map}, default: []
    field :skills, {:array, :map}, default: []
    field :platforms, {:array, :string}, default: []
    has_many :members, Teamrc.Schema.Member
    has_many :invites, Teamrc.Schema.Invite

    timestamps(type: :utc_datetime)
  end

  @id_re ~r/^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$/

  def changeset(team, attrs) do
    team
    |> cast(attrs, [:name, :rules, :skills, :platforms])
    |> validate_required([:name])
    |> validate_length(:name, max: 64)
    |> validate_format(:name, ~r/^[a-zA-Z0-9][a-zA-Z0-9 _-]*$/)
    |> validate_entry_ids(:rules)
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
