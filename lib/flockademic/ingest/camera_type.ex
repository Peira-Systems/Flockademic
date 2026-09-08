defmodule Flockademic.Ingest.CameraType do
  @moduledoc """
  Normalizes the free-text `surveillance` OSM tag value into a consistent
  set of camera types.

  Same crowd-sourced-tagging problem as `Flockademic.Ingest.Manufacturer`,
  different tag: case variants ("Public" / "public"), typos ("trafic",
  "teaffic", "camerea", "pubic"), stray punctuation ("traffic;"), and a
  cluster of spellings for a tagger writing in the brand name instead of a
  type ("flock", "flock_camera", "flock_safety", "flock_saftey"). This
  table was built from `Flockademic.Cameras.distinct_camera_types/0`
  against the live dataset.

  What this deliberately does NOT touch, for the same reason
  `Manufacturer` doesn't: normalizing something means asserting it's
  correct.

  * Multi-value tags (comma-, semicolon-, or space-separated lists of more
    than one type) — e.g. `"public, outdoor, traffic"`,
    `"camera,_ai,_flock,_police"`. Collapsing these to one value would
    discard real information about which claim is which.
  * Raw OSM tag dumps that landed in this field whole — e.g.
    `"man_made=surveillance"`, `"type=alpr"` (kept, since it's an
    unambiguous single value spelled oddly) vs. the giant combined-tag
    strings that clearly aren't a `surveillance` value at all.
  * Operator/agency names or free-text commentary that landed in this
    field instead of `operator` — e.g. `"Troy PD"`, `"Auburn Police
    Department"`, `"private by penn state on public roadway"`,
    `"unconstitutional_4th_amendment"`.
  * Ambiguous fragments — e.g. `"yes"`, `"al"`, `"license_plate"`,
    `"license"`, `"raven"` (reads like a product name, not a type).

  Unrecognized input passes through unchanged (trimmed).
  """

  @aliases %{
    # OSM's own controlled vocabulary for the `surveillance` tag
    "public" => "Public",
    "pubic" => "Public",
    "private" => "Private",
    "outdoor" => "Outdoor",
    "indoor" => "Indoor",
    "traffic" => "Traffic",
    "trafic" => "Traffic",
    "teaffic" => "Traffic",
    "traffic;" => "Traffic",
    "traffic_signals" => "Traffic Signals",

    # Generic camera/ALPR descriptors
    "camera" => "Camera",
    "camerea" => "Camera",
    "camera," => "Camera",
    "alpr" => "ALPR",
    "type=alpr" => "ALPR",
    "license_plate_reader" => "ALPR",
    "alpr_camera" => "ALPR Camera",

    # Taggers writing the brand name in where a type belongs
    "flock" => "Flock",
    "flock_camera" => "Flock",
    "flock_safety" => "Flock",
    "flock_saftey" => "Flock",
    "flock_saftey_camera" => "Flock",
    "flock_360_ptz_camera" => "Flock",
    "flock_alpr" => "Flock",
    "alpr_flock" => "Flock",

    # Other single-concept values observed, normalized to Title Case for
    # display consistency with the above
    "red_light" => "Red Light",
    "vehicular" => "Vehicular",
    "webcam" => "Webcam",
    "cctv" => "CCTV",
    "guard" => "Guard",
    "police" => "Police",
    "school" => "School",
    "street" => "Street",
    "trailer" => "Trailer",
    "fixed" => "Fixed",
    "parking" => "Parking",
    "parking_lot" => "Parking Lot",
    "residential" => "Residential",
    "entrance" => "Entrance",
    "neighborhood" => "Neighborhood",
    "transportation" => "Transportation",
    "average_speed" => "Average Speed",
    "destroyed" => "Destroyed"
  }

  @doc """
  Normalizes a raw `surveillance` tag string. Returns `nil` for `nil`
  input, otherwise the canonical name if this exact (trimmed,
  case-insensitive) value is a known alias, or the trimmed original value
  unchanged if it isn't.
  """
  @spec normalize(String.t() | nil) :: String.t() | nil
  def normalize(nil), do: nil

  def normalize(raw) when is_binary(raw) do
    trimmed = String.trim(raw)
    Map.get(@aliases, String.downcase(trimmed), trimmed)
  end
end
