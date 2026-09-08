defmodule Flockademic.Repo.Migrations.CreateRegions do
  use Ecto.Migration

  def change do
    create table(:regions) do
      add :type, :string, null: false
      add :name, :string, null: false
      add :fips, :string
      add :geom, :geometry

      timestamps(type: :utc_datetime)
    end

    create index(:regions, [:type])
    create index(:regions, [:fips])

    execute "CREATE INDEX regions_geom_index ON regions USING GIST (geom)",
            "DROP INDEX regions_geom_index"
  end
end
