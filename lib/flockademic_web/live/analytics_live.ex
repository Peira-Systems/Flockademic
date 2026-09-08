defmodule FlockademicWeb.AnalyticsLive do
  @moduledoc """
  Regional rankings (Project.md, Analytics).

  "Fastest-growing" and "largest absolute increase" rankings need multiple
  days of `RegionSnapshot` history to mean anything — with one ingestion
  run to date, this page ranks by current totals/density (which ARE real
  today) and says so plainly rather than presenting a fabricated trend.

  The underlying spatial join (~3,100 counties nationwide × ~126,000
  cameras) takes a few seconds even after indexing fixes, so it loads via
  `assign_async` — the page shell renders immediately with a loading
  state instead of blocking the whole page on the query.
  """

  use FlockademicWeb, :live_view

  alias Flockademic.Regions.RankingsCache

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(page_title: "Analytics")
      |> assign_async(:county_rankings, fn ->
        {:ok, %{county_rankings: RankingsCache.rankings("county")}}
      end)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="max-w-4xl mx-auto space-y-8">
        <div class="flex items-center justify-between">
          <h1 class="text-2xl font-bold">Analytics</h1>
          <.link navigate={~p"/"} class="btn btn-ghost btn-sm">
            <.icon name="hero-map" class="size-4" /> Back to map
          </.link>
        </div>

        <div class="alert alert-info text-sm">
          <.icon name="hero-information-circle" class="size-5" />
          <span>
            Growth-based rankings (fastest-growing, largest absolute increase, newest emerging
            clusters) need multiple days of snapshot history to mean anything. Only one ingestion
            run exists so far, so this page ranks counties by their current documented totals and
            density instead of a fabricated trend.
          </span>
        </div>

        <.async_result :let={county_rankings} assign={@county_rankings}>
          <:loading>
            <div class="flex items-center gap-2 opacity-60 text-sm py-8 justify-center">
              <span class="loading loading-spinner loading-sm"></span>
              Ranking ~3,100 counties against ~126,000 cameras — this takes a few seconds.
            </div>
          </:loading>
          <:failed :let={_reason}>
            <div class="alert alert-error text-sm">Couldn't load rankings. Try refreshing.</div>
          </:failed>

          <section>
            <h2 class="text-lg font-semibold mb-2">Highest documented camera count</h2>
            <.rankings_table
              rows={county_rankings |> Enum.sort_by(& &1.total_cameras, :desc) |> Enum.take(20)}
              value_label="Cameras"
              value_fn={& &1.total_cameras}
            />
          </section>

          <section class="mt-8">
            <h2 class="text-lg font-semibold mb-2">Highest camera density</h2>
            <.rankings_table
              rows={
                county_rankings
                |> Enum.filter(&(&1.camera_density && &1.total_cameras > 0))
                |> Enum.sort_by(& &1.camera_density, :desc)
                |> Enum.take(20)
              }
              value_label="Per sq mi"
              value_fn={&Float.round(&1.camera_density, 3)}
            />
          </section>
        </.async_result>
      </div>
    </Layouts.app>
    """
  end

  attr :rows, :list, required: true
  attr :value_label, :string, required: true
  attr :value_fn, :any, required: true

  defp rankings_table(assigns) do
    ~H"""
    <div class="overflow-x-auto">
      <table class="table table-sm">
        <thead>
          <tr>
            <th>#</th>
            <th>County</th>
            <th class="text-right">{@value_label}</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={{row, index} <- Enum.with_index(@rows, 1)}>
            <td class="opacity-50">{index}</td>
            <td>{row.region.name}</td>
            <td class="text-right tabular-nums">{@value_fn.(row)}</td>
          </tr>
          <tr :if={@rows == []}>
            <td colspan="3" class="text-center opacity-50 py-4">No data yet</td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end
end
