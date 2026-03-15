defmodule Teamrc.Schema.Task do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "tasks" do
    field :number, :integer
    field :description, :string
    field :assignee, :string
    field :status, :string, default: "todo"
    field :created_by, :string
    field :claimed_by, :string
    field :claimed_at, :utc_datetime
    field :completed_at, :utc_datetime
    belongs_to :team, Teamrc.Schema.Team, type: :binary_id

    timestamps(type: :utc_datetime)
  end

  @valid_statuses ~w(todo in_progress done cancelled failed)

  def changeset(task, attrs) do
    task
    |> cast(attrs, [:number, :description, :assignee, :status, :created_by, :claimed_by, :claimed_at, :completed_at])
    |> validate_required([:number, :description, :assignee, :status])
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_length(:description, max: 2000)
    |> validate_length(:assignee, max: 64)
    |> unique_constraint(:number, name: "tasks_team_id_number_index")
  end
end
