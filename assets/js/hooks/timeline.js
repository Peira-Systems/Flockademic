// Owns timeline playback entirely client-side: scrubbing, play/pause, and
// the "known by this date" / "new this period" counters are all derived
// from the camera GeoJSON the map hook fetches (see map.js, which
// dispatches "flockademic:cameras-loaded" once it has data) rather than
// round-tripping to the server per animation frame — the map hook is the
// one other place that cares about the current date, and it listens for
// the "flockademic:date-changed" window event this hook dispatches.

const STEP_MS = 1000 / 30 // ~30fps ticks
const DAY_MS = 86_400_000

function parseTimestamp(iso) {
  const t = Date.parse(iso)
  return Number.isNaN(t) ? null : t
}

// Count of entries <= target in a sorted-ascending array, via binary
// search. With nationwide datasets in the tens of thousands of cameras,
// doing this with Array.filter on every animation frame would mean
// millions of comparisons/sec — this keeps each frame O(log n).
function countLessOrEqual(sortedArr, target) {
  let lo = 0
  let hi = sortedArr.length
  while (lo < hi) {
    const mid = (lo + hi) >>> 1
    if (sortedArr[mid] <= target) {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  return lo
}

const TimelineControl = {
  mounted() {
    this.sortedTimestamps = []
    this.playing = false
    this.minDate = null
    this.maxDate = null

    this.playBtn = this.el.querySelector("[data-role=play]")
    this.slider = this.el.querySelector("[data-role=slider]")
    this.dateLabel = this.el.querySelector("[data-role=date]")
    this.knownLabel = this.el.querySelector("[data-role=known-count]")
    this.newLabel = this.el.querySelector("[data-role=new-count]")
    this.speedSelect = this.el.querySelector("[data-role=speed]")

    this.playBtn.addEventListener("click", () => this.togglePlay())
    this.slider.addEventListener("input", () => {
      if (this.playing) this.pause()
      this.render(Number(this.slider.value))
    })

    this._onCamerasLoaded = e => this.setData(e.detail.geojson.features)
    window.addEventListener("flockademic:cameras-loaded", this._onCamerasLoaded)
  },

  setData(features) {
    this.sortedTimestamps = features
      .map(f => parseTimestamp(f.properties.first_observed_at))
      .filter(t => t !== null)
      .sort((a, b) => a - b)

    if (!this.sortedTimestamps.length) {
      this.playBtn.disabled = true
      this.slider.disabled = true
      this.dateLabel.textContent = "No data"
      return
    }

    this.minDate = this.sortedTimestamps[0]
    this.maxDate = this.sortedTimestamps[this.sortedTimestamps.length - 1]

    this.slider.min = this.minDate
    this.slider.max = this.maxDate
    this.slider.value = this.maxDate
    this.slider.disabled = this.minDate === this.maxDate
    this.playBtn.disabled = this.minDate === this.maxDate

    this.render(this.maxDate)
  },

  togglePlay() {
    if (this.playing) {
      this.pause()
    } else {
      this.play()
    }
  },

  play() {
    if (Number(this.slider.value) >= this.maxDate) {
      this.slider.value = this.minDate
    }
    this.playing = true
    this.playBtn.setAttribute("data-playing", "true")
    this.tick()
  },

  tick() {
    const speedDaysPerSec = Number(this.speedSelect?.value || 30)
    const stepValue = (speedDaysPerSec * DAY_MS * STEP_MS) / 1000

    this.timer = setTimeout(() => {
      const next = Number(this.slider.value) + stepValue

      if (next >= this.maxDate) {
        this.slider.value = this.maxDate
        this.render(this.maxDate)
        this.pause()
        return
      }

      this.slider.value = next
      this.render(next)
      this.tick()
    }, STEP_MS)
  },

  pause() {
    this.playing = false
    this.playBtn.removeAttribute("data-playing")
    clearTimeout(this.timer)
  },

  render(timestamp) {
    const knownCount = countLessOrEqual(this.sortedTimestamps, timestamp)
    const windowStart = timestamp - 30 * DAY_MS
    const newCount = knownCount - countLessOrEqual(this.sortedTimestamps, windowStart)

    this.dateLabel.textContent = new Date(timestamp).toLocaleDateString(undefined, {
      year: "numeric",
      month: "short",
      day: "numeric"
    })
    this.knownLabel.textContent = knownCount.toLocaleString()
    this.newLabel.textContent = "+" + newCount.toLocaleString()

    window.dispatchEvent(
      new CustomEvent("flockademic:date-changed", {
        // map.js compares this against each camera's `first_observed_at`
        // with MapLibre's string `<=`, which is lexicographic — the
        // backend renders that field from a `timestamp(0)` column (no
        // fractional seconds), so a millisecond-precision ISO string here
        // would sort as "less than" a same-instant whole-second one
        // (`.` < `Z`) and silently exclude every matching camera.
        // Truncating to whole seconds keeps both sides the same format.
        detail: {timestamp, iso: new Date(timestamp).toISOString().slice(0, 19) + "Z"}
      })
    )
  },

  destroyed() {
    clearTimeout(this.timer)
    window.removeEventListener("flockademic:cameras-loaded", this._onCamerasLoaded)
  }
}

export default TimelineControl
