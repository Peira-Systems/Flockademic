defmodule Flockademic.Repo.Migrations.CreateRegionSnapshots do
  use Ecto.Migration

  def change do
    create table(:region_snapshots) do
      add :region_id, references(:regions, on_delete: :delete_all), null: false
      add :date, :date, null: false
      add :camera_count, :integer, null: false
      add :new_camera_count, :integer, null: false
      add :camera_density, :float
      add :growth_rate, :float

      timestamps(type: :utc_datetime)
    end

    create unique_index(:region_snapshots, [:region_id, :date])
    create index(:region_snapshots, [:date])
  end
end
