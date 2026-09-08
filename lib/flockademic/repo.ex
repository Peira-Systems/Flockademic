defmodule Flockademic.Repo do
  use Ecto.Repo,
    otp_app: :flockademic,
    adapter: Ecto.Adapters.Postgres
end
