defmodule FlockademicWeb.MapLive do
  @moduledoc """
  Full-screen map landing page: the animated historical view, region
  selection + stats, and camera detail/provenance (Project.md, Map
  Experience / MVP / Camera Detail / Region Detail).
  """

  use FlockademicWeb, :live_view

  alias Flockademic.{Cameras, Regions}

  @impl true
  def mount(_params, _session, socket) do
    socket =
      assign(socket,
        camera_count: Cameras.count_cameras(),
        page_title: "Flockademic",
        app_version: Application.spec(:flockademic, :vsn) |> to_string(),
        carto_api_key: Application.get_env(:flockademic, :carto_api_key),
        states: Regions.list_regions_by_type("state"),
        counties: [],
        selected_state_id: nil,
        selected_region: nil,
        region_stats: nil,
        selected_camera: nil,
        manufacturers: Cameras.distinct_manufacturers(),
        camera_types: Cameras.distinct_camera_types()
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("state:selected", %{"state_id" => ""}, socket) do
    {:noreply,
     socket
     |> assign(selected_state_id: nil, counties: [], selected_region: nil, region_stats: nil)
     |> push_event("region:focus", %{region_id: nil, bounds: nil})}
  end

  def handle_event("state:selected", %{"state_id" => state_id}, socket) do
    state = Regions.get_region!(state_id)
    counties = Regions.list_counties_in_state(state)

    {:noreply,
     socket
     |> assign(selected_state_id: state.id, counties: counties)
     |> select_region(state)}
  end

  def handle_event("county:selected", %{"county_id" => ""}, socket) do
    state = socket.assigns.selected_state_id && Regions.get_region!(socket.assigns.selected_state_id)
    {:noreply, if(state, do: select_region(socket, state), else: clear_region(socket))}
  end

  def handle_event("county:selected", %{"county_id" => county_id}, socket) do
    {:noreply, select_region(socket, Regions.get_region!(county_id))}
  end

  def handle_event("region:clear", _params, socket) do
    {:noreply, clear_region(socket) |> assign(selected_state_id: nil, counties: [])}
  end

  def handle_event("camera:clicked", %{"id" => id}, socket) do
    {:noreply, assign(socket, selected_camera: Cameras.get_camera_detail!(id))}
  end

  def handle_event("camera:close", _params, socket) do
    {:noreply, assign(socket, selected_camera: nil)}
  end

  defp select_region(socket, region) do
    socket
    |> assign(selected_region: region, region_stats: Regions.region_stats(region))
    |> push_event("region:focus", %{region_id: region.id, bounds: Regions.bounds(region)})
  end

  defp clear_region(socket) do
    socket
    |> assign(selected_region: nil, region_stats: nil)
    |> push_event("region:focus", %{region_id: nil, bounds: nil})
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="relative w-screen h-screen overflow-hidden">
      <div
        id="map"
        phx-hook="MapLibreMap"
        phx-update="ignore"
        data-carto-api-key={@carto_api_key}
        class="absolute inset-0"
        style="position: absolute; inset: 0;"
      >
      </div>

      <%!-- Shown until the map hook has fetched the (large) camera dataset and
      MapLibre has finished rendering it — without this the basemap just sits
      there with no markers and the site looks frozen. Toggled entirely by
      hooks/map.js; starts visible so it also covers the JS bundle download. --%>
      <div
        id="map-loading"
        class="pointer-events-none absolute inset-0 z-20 flex items-center justify-center bg-base-100/30 backdrop-blur-[2px] opacity-100 transition-opacity duration-300"
      >
        <div class="pointer-events-auto flex items-center gap-3 rounded-lg bg-base-100/95 px-5 py-3 shadow-lg backdrop-blur">
          <span data-role="spinner" class="loading loading-spinner loading-md text-primary"></span>
          <span data-role="message" class="text-sm font-medium">
            {if @camera_count > 0,
              do: "Loading #{format_count(@camera_count)} camera locations…",
              else: "Loading camera locations…"}
          </span>
        </div>
      </div>

      <div class="absolute top-4 left-4 z-10 flex items-start gap-2">
        <button
          type="button"
          class="btn btn-circle btn-sm bg-base-100/90 backdrop-blur shadow-lg shrink-0"
          title="Toggle panel"
          phx-click={
            JS.toggle(to: "#left-panel")
            |> JS.toggle(to: "#left-panel-collapse-icon")
            |> JS.toggle(to: "#left-panel-expand-icon")
          }
        >
          <span id="left-panel-collapse-icon"><.icon name="hero-chevron-left" class="size-4" /></span>
          <span id="left-panel-expand-icon" class="hidden">
            <.icon name="hero-chevron-right" class="size-4" />
          </span>
        </button>

        <div id="left-panel" class="w-80 max-w-[calc(100vw-6rem)] space-y-3">
          <div class="rounded-lg bg-base-100/90 backdrop-blur px-4 py-3 shadow-lg space-y-1">
            <div class="flex items-center justify-between">
              <div class="flex items-center gap-1.5">
                <div class="text-sm font-bold tracking-wide">FLOCKADEMIC</div>
                <button
                  type="button"
                  phx-click={JS.show(to: "#about-popup", display: "flex")}
                  title="About"
                  aria-label="About"
                  class="btn btn-ghost btn-circle btn-xs size-4 min-h-0 p-0 text-xs font-bold opacity-60 hover:opacity-100"
                >
                  ?
                </button>
              </div>
              <.link navigate={~p"/analytics"} class="btn btn-ghost btn-xs">
                <.icon name="hero-chart-bar" class="size-3.5" /> Analytics
              </.link>
            </div>
            <div class="text-xs opacity-70">Documented ALPR expansion &middot; United States</div>
            <div class="text-lg font-semibold">{@camera_count} known by this date</div>
          </div>

          <div class="rounded-lg bg-base-100/90 backdrop-blur px-4 py-3 shadow-lg space-y-2">
            <div class="text-xs font-semibold uppercase opacity-60">Region</div>
            <form id="state-select-form" phx-change="state:selected" class="space-y-2">
              <.input
                type="select"
                name="state_id"
                value={@selected_state_id}
                prompt="All states"
                options={Enum.map(@states, &{&1.name, &1.id})}
              />
            </form>
            <form
              :if={@selected_state_id}
              id="county-select-form"
              phx-change="county:selected"
              class="space-y-2"
            >
              <.input
                type="select"
                name="county_id"
                value={@selected_region && @selected_region.type == "county" && @selected_region.id}
                prompt="Entire state"
                options={Enum.map(@counties, &{&1.name, &1.id})}
              />
            </form>
            <.region_stats :if={@region_stats} region={@selected_region} stats={@region_stats} />
          </div>

          <div
            :if={@manufacturers != [] or @camera_types != []}
            id="filters"
            phx-hook="FiltersControl"
            phx-update="ignore"
            class="rounded-lg bg-base-100/90 backdrop-blur px-4 py-3 shadow-lg space-y-2 max-h-64 overflow-y-auto"
          >
            <div class="text-xs font-semibold uppercase opacity-60">Filters</div>

            <div :if={@manufacturers != []}>
              <div class="text-[11px] font-medium opacity-60 mb-1">Manufacturer</div>
              <label :for={m <- @manufacturers} class="flex items-center gap-2 text-xs py-0.5">
                <input type="checkbox" data-filter-kind="manufacturer" value={m} class="checkbox checkbox-xs" />
                {m}
              </label>
            </div>

            <div :if={@camera_types != []}>
              <div class="text-[11px] font-medium opacity-60 mb-1">Camera type</div>
              <label :for={t <- @camera_types} class="flex items-center gap-2 text-xs py-0.5">
                <input type="checkbox" data-filter-kind="camera_type" value={t} class="checkbox checkbox-xs" />
                {t}
              </label>
            </div>
          </div>
        </div>
      </div>

      <.camera_panel :if={@selected_camera} detail={@selected_camera} />

      <%!-- Purely presentational — toggled client-side with JS commands so
      opening/closing it never round-trips to the server and can't disturb the
      map hook (which would otherwise re-fetch the whole camera dataset). --%>
      <div
        id="about-popup"
        style="display: none;"
        class="absolute inset-0 z-30 items-center justify-center p-4"
      >
        <div
          class="absolute inset-0 bg-base-content/30 backdrop-blur-sm"
          phx-click={JS.hide(to: "#about-popup")}
        >
        </div>
        <div class="relative w-auto max-w-[calc(100vw-2rem)] rounded-lg bg-base-100/95 backdrop-blur px-8 py-6 shadow-lg flex flex-col items-center gap-2 text-center whitespace-nowrap">
          <div class="text-xl font-bold tracking-wide">
            Flockademic <span class="tabular-nums">v{@app_version}</span>
          </div>
          <a
            href="https://github.com/Peira-Systems/Flockademic"
            target="_blank"
            rel="noopener noreferrer"
            class="link link-hover text-base font-bold"
          >
            https://github.com/Peira-Systems/Flockademic
          </a>
          <div class="text-base font-bold">Created by Darshan Gencarelle</div>
          <button
            type="button"
            phx-click={JS.hide(to: "#about-popup")}
            class="btn btn-sm btn-neutral mt-3"
          >
            Close
          </button>
        </div>
      </div>

      <div class="absolute bottom-4 left-1/2 -translate-x-1/2 z-10 w-full max-w-xl px-4">
        <div
          id="timeline"
          phx-hook="TimelineControl"
          phx-update="ignore"
          class="rounded-lg bg-base-100/90 backdrop-blur px-4 py-3 shadow-lg space-y-2"
        >
          <div class="flex items-center gap-3">
            <button
              type="button"
              data-role="play"
              class="btn btn-circle btn-sm"
              disabled
              title="Play/pause"
            >
              <.icon name="hero-play-solid" class="size-4" />
            </button>
            <input type="range" data-role="slider" class="range range-sm flex-1" disabled />
            <select data-role="speed" class="select select-xs w-24">
              <option value="10">10 days/s</option>
              <option value="30" selected>30 days/s</option>
              <option value="90">90 days/s</option>
              <option value="365">1 yr/s</option>
            </select>
          </div>
          <div class="flex items-center justify-between text-xs">
            <span data-role="date" class="tabular-nums opacity-70">First observed</span>
            <span class="opacity-70">
              <span data-role="known-count" class="font-semibold tabular-nums">0</span> known &middot;
              <span data-role="new-count" class="font-semibold tabular-nums">+0</span> last 30d
            </span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :region, :map, required: true
  attr :stats, :map, required: true

  defp region_stats(assigns) do
    ~H"""
    <div class="border-t border-base-300 pt-2 space-y-1 text-sm">
      <div class="font-semibold">{@region.name}</div>
      <div class="grid grid-cols-2 gap-x-2 gap-y-1 text-xs">
        <span class="opacity-60">Documented cameras</span>
        <span class="text-right tabular-nums">{@stats.total_cameras}</span>

        <span class="opacity-60">First observed</span>
        <span class="text-right">{format_date(@stats.first_observed_at)}</span>

        <span class="opacity-60">New — 30 days</span>
        <span class="text-right tabular-nums">{@stats.new_observations_30d}</span>

        <span class="opacity-60">New — 1 year</span>
        <span class="text-right tabular-nums">{@stats.new_observations_1y}</span>

        <span class="opacity-60">Density</span>
        <span class="text-right tabular-nums">{format_density(@stats.camera_density)}</span>

        <span class="opacity-60">Growth rate</span>
        <span class="text-right tabular-nums">{format_growth(@stats.growth_rate)}</span>

        <span :if={@stats.peak_growth_period} class="opacity-60">Peak expansion</span>
        <span :if={@stats.peak_growth_period} class="text-right">
          {format_date(elem(@stats.peak_growth_period, 0))} – {format_date(elem(@stats.peak_growth_period, 1))}
        </span>
      </div>
      <div :if={@stats.snapshot_count < 2} class="text-[11px] opacity-50 pt-1">
        Growth trend needs multiple days of snapshot history — only one ingestion run so far.
      </div>
      <button type="button" phx-click="region:clear" class="btn btn-ghost btn-xs mt-1">
        Clear selection
      </button>
    </div>
    """
  end

  attr :detail, :map, required: true

  defp camera_panel(assigns) do
    ~H"""
    <div class="absolute top-4 right-4 z-10 w-80 max-w-[calc(100vw-2rem)] rounded-lg bg-base-100/95 backdrop-blur shadow-lg p-4 space-y-3 max-h-[calc(100vh-2rem)] overflow-y-auto">
      <div class="flex items-start justify-between">
        <div class="text-sm font-bold">Camera #{@detail.camera.id}</div>
        <button type="button" phx-click="camera:close" class="btn btn-ghost btn-xs btn-circle">
          <.icon name="hero-x-mark" class="size-4" />
        </button>
      </div>

      <dl class="text-xs space-y-1">
        <div class="flex justify-between gap-2">
          <dt class="opacity-60">Manufacturer</dt>
          <dd class="text-right">{@detail.camera.manufacturer || "Unknown"}</dd>
        </div>
        <div class="flex justify-between gap-2">
          <dt class="opacity-60">Camera type</dt>
          <dd class="text-right">{@detail.camera.camera_type || "Unknown"}</dd>
        </div>
        <div class="flex justify-between gap-2">
          <dt class="opacity-60">Operator</dt>
          <dd class="text-right">{@detail.camera.operator || "Unknown"}</dd>
        </div>
        <div class="flex justify-between gap-2">
          <dt class="opacity-60">Data source</dt>
          <dd class="text-right">{@detail.camera.source}</dd>
        </div>
        <div class="flex justify-between gap-2">
          <dt class="opacity-60">First observed</dt>
          <dd class="text-right">{format_date(@detail.camera.first_observed_at)}</dd>
        </div>
        <div class="flex justify-between gap-2">
          <dt class="opacity-60">Last observed</dt>
          <dd class="text-right">{format_date(@detail.camera.last_observed_at)}</dd>
        </div>
        <div class="flex justify-between gap-2">
          <dt class="opacity-60">Installation date</dt>
          <dd class="text-right">{@detail.camera.installed_at && format_date(@detail.camera.installed_at) || "Not independently known"}</dd>
        </div>
        <div class="flex justify-between gap-2">
          <dt class="opacity-60">Coordinates</dt>
          <dd class="text-right tabular-nums">
            {Float.round(@detail.camera.latitude, 5)}, {Float.round(@detail.camera.longitude, 5)}
          </dd>
        </div>
      </dl>

      <div class="border-t border-base-300 pt-2">
        <div class="text-xs font-semibold uppercase opacity-60 mb-1">Data quality</div>
        <span class="badge badge-sm">{temporal_confidence_label(@detail.camera)}</span>
      </div>

      <div :if={@detail.nearest_other} class="border-t border-base-300 pt-2 text-xs">
        <div class="font-semibold uppercase opacity-60 mb-1">Nearest documented camera</div>
        <p class="opacity-80">
          #{@detail.nearest_other.camera.id} is {format_distance(@detail.nearest_other.distance_meters)} away.
          This is spatial proximity only — not evidence either camera caused the other's deployment.
        </p>
      </div>

      <div class="border-t border-base-300 pt-2">
        <div class="text-xs font-semibold uppercase opacity-60 mb-1">
          Provenance ({length(@detail.observations)} observation{if length(@detail.observations) != 1, do: "s"})
        </div>
        <ul class="text-xs space-y-1">
          <li :for={obs <- @detail.observations} class="opacity-80">
            <span class="font-medium">{obs.source}</span>
            observed this record on {format_date(obs.observed_at)}
            (source record <code class="text-[10px]">{obs.source_record_id}</code>)
          </li>
        </ul>
      </div>
    </div>
    """
  end

  defp temporal_confidence_label(%{installed_at: nil}), do: "Dataset first-seen date"
  defp temporal_confidence_label(_camera), do: "Confirmed installation date"

  # 136000 -> "136,000"
  defp format_count(n) when is_integer(n),
    do: n |> Integer.to_string() |> String.replace(~r/\B(?=(\d{3})+(?!\d))/, ",")

  defp format_count(n), do: to_string(n)

  defp format_date(nil), do: "Unknown"
  defp format_date(%DateTime{} = dt), do: Calendar.strftime(dt, "%b %-d, %Y")
  defp format_date(%Date{} = d), do: Calendar.strftime(d, "%b %-d, %Y")

  defp format_density(nil), do: "N/A"
  defp format_density(d) when d < 0.01, do: "#{Float.round(d, 4)} / sq mi"
  defp format_density(d) when d < 1, do: "#{Float.round(d, 3)} / sq mi"
  defp format_density(d), do: "#{Float.round(d, 2)} / sq mi"

  defp format_growth(nil), do: "Insufficient history"
  defp format_growth(rate), do: "#{if rate >= 0, do: "+"}#{Float.round(rate * 100, 1)}%"

  defp format_distance(meters) when meters >= 1609.34, do: "#{Float.round(meters / 1609.34, 2)} mi"
  defp format_distance(meters), do: "#{round(meters)} m"
end
