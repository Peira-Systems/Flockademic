defmodule Flockademic.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      FlockademicWeb.Telemetry,
      Flockademic.Repo,
      # After Repo: their init/1 warms a cache in a Task, which needs the
      # Repo already running (see each moduledoc).
      Flockademic.Cameras.GeoJSONCache,
      Flockademic.Regions.RankingsCache,
      {DNSCluster, query: Application.get_env(:flockademic, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Flockademic.PubSub},
      # Supervises ingestion runs (Flockademic.Ingest.run/2) so a source
      # adapter crashing doesn't take down the app.
      {Task.Supervisor, name: Flockademic.IngestSupervisor},
      # Periodically re-runs the live Overpass adapter (Project.md's
      # "Phase 5 — Production ingestion"). Disabled by default — init/1
      # returns :ignore unless explicitly enabled (see its moduledoc),
      # so this is always safe to list here.
      Flockademic.Ingest.Scheduler,
      # Start to serve requests, typically the last entry
      FlockademicWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Flockademic.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    FlockademicWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
