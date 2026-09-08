// Manufacturer/camera-type filters, applied entirely client-side against
// the camera set already loaded on the map — no server round trip per
// checkbox toggle. Combines with the timeline's date filter in map.js via
// the same "dispatch a window CustomEvent" pattern used there.

const FiltersControl = {
  mounted() {
    this.checkboxes = Array.from(this.el.querySelectorAll("input[type=checkbox]"))
    this.checkboxes.forEach(cb => cb.addEventListener("change", () => this.emit()))
  },

  emit() {
    const manufacturers = this.checkboxes
      .filter(cb => cb.dataset.filterKind === "manufacturer" && cb.checked)
      .map(cb => cb.value)

    const cameraTypes = this.checkboxes
      .filter(cb => cb.dataset.filterKind === "camera_type" && cb.checked)
      .map(cb => cb.value)

    window.dispatchEvent(
      new CustomEvent("flockademic:filters-changed", {
        detail: {manufacturers, cameraTypes}
      })
    )
  }
}

export default FiltersControl
