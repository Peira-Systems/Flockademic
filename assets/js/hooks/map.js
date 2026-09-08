import * as maplibregl from "maplibre-gl"
import "maplibre-gl/dist/maplibre-gl.css"

// maplibre-gl processes GeoJSON sources in a Web Worker loaded from a
// separate file. esbuild doesn't emit that file as part of bundling
// app.js the way webpack/rollup plugins do, so config/config.exs bundles
// it separately (esbuild "flockademic_worker" profile) and we point
// maplibre at the result here, before creating any Map.
maplibregl.setWorkerUrl("/assets/js/maplibre-gl-worker.js")

// CARTO's "Positron" raster tiles: OSM-derived but stripped of building
// fill, most POI icons, and secondary-road clutter, so camera markers
// read clearly against it. CARTO now requires a (free) API key for
// basemap tiles — without one, tiles come back stamped with an "API KEY
// REQUIRED" watermark. The key is passed as a `?key=` query param (see
// https://carto.com/basemaps/apikey/) and reaches the browser anyway, so
// it's wired through as a plain config value, not a server secret:
// `CARTO_API_KEY` env var -> :flockademic config -> `data-carto-api-key`
// on the #map element -> here.
function buildBasemapStyle(apiKey) {
  const query = apiKey ? `?key=${encodeURIComponent(apiKey)}` : ""
  return {
    version: 8,
    sources: {
      osm: {
        type: "raster",
        tiles: ["a", "b", "c", "d"].map(
          sub => `https://${sub}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png${query}`
        ),
        tileSize: 256,
        attribution: "&copy; OpenStreetMap contributors &copy; CARTO"
      }
    },
    layers: [{id: "osm", type: "raster", source: "osm"}]
  }
}

const CAMERA_ICON_ID = "camera-icon"

// Below this zoom, a single map tile can cover the whole country — with a
// nationwide dataset that means tens of thousands of points landing in one
// tile. MapLibre/Mapbox GL's symbol/icon bucket has a long-standing bug
// where that overflows an internal 16-bit vertex buffer and desyncs
// (`bucket.icon.opacityVertexArray.length != bucket.icon.layoutVertexArray
// .length / 4`), which silently drops the whole tile's icons — the visible
// symptom being large chunks of the map missing cameras with no error
// shown to the user. Plain circles don't carry the opacity-fade buffers
// that trigger this, so we render circles until zoomed in enough that
// per-tile camera counts are safely small, then switch to the
// directional icon.
const ICON_MIN_ZOOM = 10

// A bullet/dome-camera glyph: circular lens head facing "up" (north) with a
// small body beneath it. `icon-rotate` (driven by OSM's `direction` tag,
// a compass bearing) rotates this around its center, so the lens ends up
// pointing the way the real camera is aimed.
const CAMERA_ICON_SVG = `
<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32">
  <rect x="10" y="15" width="12" height="13" rx="3" fill="#2563eb" stroke="#ffffff" stroke-width="2"/>
  <circle cx="16" cy="10" r="8" fill="#2563eb" stroke="#ffffff" stroke-width="2"/>
  <circle cx="16" cy="10" r="3.5" fill="#ffffff"/>
</svg>
`.trim()

// Loads the camera glyph and calls back with true/false for whether it's
// available as `CAMERA_ICON_ID`. Never hangs: on any failure it still calls
// back (with false) so the caller can fall back to a plain circle layer
// instead of silently rendering nothing.
function loadCameraIcon(map, callback) {
  if (map.hasImage(CAMERA_ICON_ID)) return callback(true)

  const img = new Image(32, 32)
  img.onload = () => {
    try {
      if (!map.hasImage(CAMERA_ICON_ID)) map.addImage(CAMERA_ICON_ID, img)
      callback(true)
    } catch (e) {
      console.error("[map] addImage failed", e)
      callback(false)
    }
  }
  img.onerror = e => {
    console.error("[map] camera icon image failed to load", e)
    callback(false)
  }
  img.src = "data:image/svg+xml;charset=utf-8," + encodeURIComponent(CAMERA_ICON_SVG)
}

const MapLibreMap = {
  mounted() {
    // Loading overlay (rendered by MapLive, starts visible). We hide it
    // only once the camera dataset has been fetched *and* MapLibre has
    // finished rendering it — see applyCameras / hideLoading.
    this.loadingEl = document.getElementById("map-loading")
    this.defaultLoadingMessage = this.loadingEl
      ?.querySelector("[data-role=message]")
      ?.textContent.trim()

    this.map = new maplibregl.Map({
      container: this.el,
      style: buildBasemapStyle(this.el.dataset.cartoApiKey),
      center: [-98.5795, 39.8283], // continental US
      zoom: 4
    })
    this.map.addControl(new maplibregl.NavigationControl(), "top-right")
    this.map.on("error", e => console.error("[map] maplibre error", e.error))

    this.map.on("load", () => {
      loadCameraIcon(this.map, iconAvailable => {
        this.map.addSource("cameras", {
          type: "geojson",
          data: {type: "FeatureCollection", features: []}
        })

        // Always add the circle layer — it's the safe rendering path at
        // low zoom (see ICON_MIN_ZOOM above) and, if the icon fails to
        // load, becomes the fallback for every zoom level too.
        this.map.addLayer({
          id: "cameras-circle",
          type: "circle",
          source: "cameras",
          maxzoom: iconAvailable ? ICON_MIN_ZOOM : 24,
          paint: {
            "circle-radius": ["interpolate", ["linear"], ["zoom"], 0, 1.5, ICON_MIN_ZOOM, 5],
            "circle-color": "#2563eb",
            "circle-stroke-width": 1,
            "circle-stroke-color": "#ffffff"
          }
        })

        this.cameraLayerIds = ["cameras-circle"]

        if (iconAvailable) {
          this.map.addLayer({
            id: "cameras-icon",
            type: "symbol",
            source: "cameras",
            minzoom: ICON_MIN_ZOOM,
            layout: {
              "icon-image": CAMERA_ICON_ID,
              // Fixed pixel size regardless of zoom, so every camera
              // stays visible whether you're looking at one block or
              // the whole country.
              "icon-size": 0.55,
              "icon-rotate": ["coalesce", ["get", "direction"], 0],
              "icon-rotation-alignment": "map",
              "icon-allow-overlap": true,
              "icon-ignore-placement": true
            }
          })
          this.cameraLayerIds.push("cameras-icon")
        }

        this.cameraLayerIds.forEach(layerId => {
          this.map.on("mouseenter", layerId, () => {
            this.map.getCanvas().style.cursor = "pointer"
          })
          this.map.on("mouseleave", layerId, () => {
            this.map.getCanvas().style.cursor = ""
          })
          this.map.on("click", layerId, e => {
            const id = e.features[0]?.properties?.id
            if (id != null) this.pushEvent("camera:clicked", {id})
          })
        })

        if (this.pending) {
          this.applyCameras(this.pending.geojson, this.pending.bounds)
          this.pending = null
        }
      })

      // Nationwide camera data can be tens of thousands of features —
      // fetched directly over plain HTTP rather than embedded in the
      // LiveView socket payload (Project.md: don't push the whole
      // dataset through LiveView; deliver it as an efficient map-
      // oriented representation instead).
      this.loadCameras("/api/cameras.geojson")
    })

    // Region selection tells us which region + bounds via the (small)
    // LiveView socket message, then we fetch that region's cameras
    // ourselves — same reasoning as the initial load above.
    this.handleEvent("region:focus", ({region_id, bounds}) => {
      const url = region_id
        ? `/api/cameras.geojson?region_id=${encodeURIComponent(region_id)}`
        : "/api/cameras.geojson"
      this.loadCameras(url, bounds, region_id ? "Loading region cameras…" : null)
    })

    // Timeline playback and the manufacturer/camera-type filters both act
    // on the already-loaded camera set entirely client-side (see
    // hooks/timeline.js and hooks/filters.js) — no server round trip per
    // animation frame or checkbox toggle. Both dispatch window events;
    // this combines whichever ones are currently active into one
    // MapLibre filter expression.
    this.dateISO = null
    this.activeManufacturers = []
    this.activeCameraTypes = []

    this._onDateChanged = e => {
      this.dateISO = e.detail.iso
      this.applyFilters()
    }
    this._onFiltersChanged = e => {
      this.activeManufacturers = e.detail.manufacturers
      this.activeCameraTypes = e.detail.cameraTypes
      this.applyFilters()
    }
    window.addEventListener("flockademic:date-changed", this._onDateChanged)
    window.addEventListener("flockademic:filters-changed", this._onFiltersChanged)
  },

  applyFilters() {
    if (!this.cameraLayerIds?.length) return

    const clauses = ["all"]
    if (this.dateISO) {
      clauses.push(["<=", ["get", "first_observed_at"], this.dateISO])
    }
    if (this.activeManufacturers.length) {
      clauses.push(["in", ["get", "manufacturer"], ["literal", this.activeManufacturers]])
    }
    if (this.activeCameraTypes.length) {
      clauses.push(["in", ["get", "camera_type"], ["literal", this.activeCameraTypes]])
    }

    const filter = clauses.length > 1 ? clauses : null
    this.cameraLayerIds.forEach(layerId => this.map.setFilter(layerId, filter))
  },

  loadCameras(url, bounds, loadingMessage) {
    this.showLoading(loadingMessage)
    fetch(url)
      .then(r => {
        if (!r.ok) throw new Error(`HTTP ${r.status}`)
        return r.json()
      })
      .then(geojson => this.applyCameras(geojson, bounds))
      .catch(e => {
        console.error("[map] failed to load cameras from", url, e)
        this.showLoadError()
      })
  },

  showLoading(message) {
    const el = this.loadingEl
    if (!el) return
    clearTimeout(this._hideTimer)
    clearTimeout(this._loadingSafety)
    const msg = el.querySelector("[data-role=message]")
    if (msg) msg.textContent = message || this.defaultLoadingMessage || "Loading…"
    el.querySelector("[data-role=spinner]")?.classList.remove("hidden")
    el.classList.remove("hidden", "opacity-0")
  },

  hideLoading() {
    const el = this.loadingEl
    if (!el) return
    clearTimeout(this._loadingSafety)
    el.classList.add("opacity-0")
    // Wait out the fade, but bail if something re-showed it in the meantime.
    this._hideTimer = setTimeout(() => {
      if (el.classList.contains("opacity-0")) el.classList.add("hidden")
    }, 300)
  },

  showLoadError() {
    const el = this.loadingEl
    if (!el) return
    clearTimeout(this._hideTimer)
    clearTimeout(this._loadingSafety)
    const msg = el.querySelector("[data-role=message]")
    if (msg) msg.textContent = "Couldn’t load camera data — check your connection and reload."
    el.querySelector("[data-role=spinner]")?.classList.add("hidden")
    el.classList.remove("hidden", "opacity-0")
    // Don't block the map forever.
    this._hideTimer = setTimeout(() => this.hideLoading(), 6000)
  },

  applyCameras(geojson, bounds) {
    if (!this.map.getSource("cameras")) {
      this.pending = {geojson, bounds}
      return
    }

    this.map.getSource("cameras").setData(geojson)

    // Keep the overlay up through MapLibre's own parse + render of the
    // feature set (tens of thousands of points), not just the fetch —
    // `idle` fires once the worker has processed the data and the map has
    // settled. The timeout is a failsafe in case `idle` never comes.
    this.map.once("idle", () => this.hideLoading())
    clearTimeout(this._loadingSafety)
    this._loadingSafety = setTimeout(() => this.hideLoading(), 15000)

    // The timeline (hooks/timeline.js) needs the same feature set to
    // compute its date range/counters — dispatched rather than fetched
    // twice.
    window.dispatchEvent(new CustomEvent("flockademic:cameras-loaded", {detail: {geojson}}))

    if (bounds) {
      this.map.fitBounds(
        [[bounds.west, bounds.south], [bounds.east, bounds.north]],
        {padding: 60, maxZoom: 12, duration: 500}
      )
    } else if (geojson.features.length) {
      const b = new maplibregl.LngLatBounds()
      geojson.features.forEach(f => b.extend(f.geometry.coordinates))
      this.map.fitBounds(b, {padding: 60, maxZoom: 14, duration: 0})
    }
  },

  destroyed() {
    clearTimeout(this._hideTimer)
    clearTimeout(this._loadingSafety)
    window.removeEventListener("flockademic:date-changed", this._onDateChanged)
    window.removeEventListener("flockademic:filters-changed", this._onFiltersChanged)
    this.map?.remove()
  }
}

export default MapLibreMap
