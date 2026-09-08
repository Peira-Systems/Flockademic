defmodule Flockademic.Repo.Migrations.CreateObservations do
  use Ecto.Migration

  def change do
    # Observations are immutable: a camera appearing in one source snapshot.
    # No updated_at, since a record should never be edited after insertion.
    create table(:observations, primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :camera_id, references(:cameras, on_delete: :delete_all), null: false
      add :source, :string, null: false
      add :source_record_id, :string, null: false
      add :observed_at, :utc_datetime, null: false
      add :latitude, :float, null: false
      add :longitude, :float, null: false
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:observations, [:camera_id])
    create index(:observations, [:observed_at])
    create unique_index(:observations, [:source, :source_record_id])
  end
end
