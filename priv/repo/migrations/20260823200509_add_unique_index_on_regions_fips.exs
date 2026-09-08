defmodule Flockademic.Repo.Migrations.AddUniqueIndexOnRegionsFips do
  use Ecto.Migration

  def change do
    drop index(:regions, [:fips])
    create unique_index(:regions, [:fips])
  end
end
