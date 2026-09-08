defmodule Flockademic.Ingest.Manufacturer do
  @moduledoc """
  Normalizes the free-text `manufacturer`/`brand` OSM tag values into a
  consistent set of names.

  Crowd-sourced tagging produces exactly what you'd expect: 188 distinct
  raw strings for what's really ~40 companies — case variants ("AXIS" /
  "Axis" / "Axis Communications"), typos ("Mortorola Solutions",
  "Genetech"), corporate-suffix noise ("Flock Group Inc." / "Flock Safety
  Inc"), and outright duplicates from different taggers. This table was
  built from `Flockademic.Cameras.distinct_manufacturers/0` (plus the raw
  `brand` tag for cameras that had one but no `manufacturer`) against the
  live dataset — it is a lookup of real observed values, not a guess at
  what OSM taggers *might* write.

  What this deliberately does NOT touch, on the principle that
  normalizing something means asserting it's correct (Project.md: never
  silently merge conflicting claims):

  * Values ending in `?` (the tagger's own uncertainty marker) — e.g.
    `"Cyber Secure?"`, `"SCM?"`, `"Motorola?"`.
  * Multi-vendor combined tags (`;`-separated, or containing `" w/ "` /
    `" / "` where both sides name a distinct company) — e.g. `"Flock
    Safety;Motorola Solutions"`, `"Other w/ Rekor Scout"`.
  * Singletons with no independent corroboration — e.g. `"Oswego City"`,
    `"Municipal Parking Services"` (these read like an operator name
    landed in the manufacturer field, but reclassifying that is a
    judgment call this table isn't confident enough to make), or obvious
    vandalism (`"Rilee Daniels jerk cam"`).

  Unrecognized input passes through unchanged (trimmed) rather than
  erroring — an unmapped value is far less costly than a wrong merge, and
  this table should be revisited periodically against fresh
  `distinct_manufacturers/0` output as ingestion covers more of the
  country.

  The raw tag value is always preserved untouched in `Camera.metadata`
  regardless of what this returns, so no provenance is lost either way.
  """

  @aliases %{
    # Flock Safety
    "flock safety" => "Flock Safety",
    "flock group inc." => "Flock Safety",
    "flock safety inc" => "Flock Safety",
    "flock" => "Flock Safety",
    "flocksafety" => "Flock Safety",
    "flock safety (installation in progress)" => "Flock Safety",
    "flow safety" => "Flock Safety",
    "floc" => "Flock Safety",
    "flock surveillance" => "Flock Safety",
    # Flock Safety's Wikidata QID, sometimes pasted into the manufacturer
    # field directly instead of the name (confirmed by cross-referencing
    # thousands of other records tagging this same QID as Flock Safety).
    "q108485435" => "Flock Safety",
    "wikidata=q108485435" => "Flock Safety",

    # Motorola Solutions (Vigilant Solutions and Avigilon are both
    # Motorola Solutions subsidiaries; combined tags naming them
    # alongside Motorola fold in here too)
    "motorola solutions" => "Motorola Solutions",
    "motorola" => "Motorola Solutions",
    "motorola solutions(vigilant)" => "Motorola Solutions",
    "motorola/vigilant" => "Motorola Solutions",
    "motorola solutions l6q" => "Motorola Solutions",
    "mortorola solutions" => "Motorola Solutions",
    "motorolla" => "Motorola Solutions",
    "motorola/aviglon" => "Motorola Solutions",
    "vigilant" => "Motorola Solutions",

    # Genetec (AutoVu is Genetec's ALPR product line)
    "genetec" => "Genetec",
    "genetech" => "Genetec",
    "autovu cloudrunner" => "Genetec",

    # Axis Communications
    "axis communications" => "Axis Communications",
    "axis" => "Axis Communications",
    "axis communication" => "Axis Communications",

    # Axon Enterprise
    "axon enterprise" => "Axon Enterprise",
    "axon" => "Axon Enterprise",
    "axon enterprice" => "Axon Enterprise",
    "axon enterprise / outpost" => "Axon Enterprise",
    "axon enterprise/outpost" => "Axon Enterprise",
    "axon enterprises" => "Axon Enterprise",

    # Leonardo (ELSAG is Leonardo's ALPR brand, formerly Selex/ELSAG)
    "leonardo" => "Leonardo",
    "leonardo us cyber and security solutions, inc." => "Leonardo",
    "leonardo us cyber and security solutions, llc" => "Leonardo",
    "elsag" => "Leonardo",

    # PlateSmart / Cyclops Technologies (merged entity — both names
    # appear on their own and combined in the source data)
    "platesmart/cyclopstchnlgs" => "PlateSmart / Cyclops Technologies",
    "platesmart" => "PlateSmart / Cyclops Technologies",
    "cyclopstechnologies" => "PlateSmart / Cyclops Technologies",
    "platesmart ptz lpr" => "PlateSmart / Cyclops Technologies",

    # Rekor
    "rekor" => "Rekor",
    "rekor systems inc" => "Rekor",
    "rekor systems" => "Rekor",
    "rekor scout" => "Rekor",
    "rekoe" => "Rekor",

    # Ubicquia
    "ubicquia, inc." => "Ubicquia",
    "ubicquia" => "Ubicquia",
    "ubicquia, inc" => "Ubicquia",

    # Neology
    "neology, inc." => "Neology",
    "neology(3m)" => "Neology",
    "neology" => "Neology",

    # Ekin (Box Spotter / x Spotter are Ekin product names)
    "ekin box spotter" => "Ekin",
    "ekin x spotter" => "Ekin",
    "ekin spotter" => "Ekin",
    "ekin" => "Ekin",

    # Avigilon
    "avigilon" => "Avigilon",

    # Verkada
    "verkada" => "Verkada",
    "verkada inc." => "Verkada",
    "verkada inc" => "Verkada",

    # Redspeed (distinct from Redflex — different company, not merged)
    "redspeed redcurb" => "Redspeed",
    "redspeed usa" => "Redspeed",
    "red speed" => "Redspeed",

    # NDI Recognition Systems
    "ndi recognition systems" => "NDI Recognition Systems",
    "ndi recognition systems(appian)" => "NDI Recognition Systems",

    # LiveView Technologies
    "liveview technologies" => "LiveView Technologies",
    "lvt" => "LiveView Technologies",
    "lifeview technologies" => "LiveView Technologies",
    "liveview technologie" => "LiveView Technologies",
    "live view technologies" => "LiveView Technologies",
    "liveview technologies (lvt)" => "LiveView Technologies",
    "live view technology" => "LiveView Technologies",
    "lvt mobile tower" => "LiveView Technologies",

    # Bosch
    "bosch security systems" => "Bosch",
    "bosch" => "Bosch",

    # Kapsch
    "kapsch" => "Kapsch",
    "kapsch vrx-350x" => "Kapsch",

    # PaceTalk
    "packetalk" => "PaceTalk",
    "pacetalk" => "PaceTalk",

    # Insight
    "insight lpr" => "Insight",
    "insight" => "Insight",

    # Uniview (Unv is their stock ticker/short name)
    "uniview technologies" => "Uniview",
    "uniview" => "Uniview",
    "unv" => "Uniview",
    "zhejiang uniview technologies co., ltd" => "Uniview",

    # Hikvision
    "hikvision" => "Hikvision",
    "hangzhou hikvision digital technology co., ltd." => "Hikvision",
    "hik vision(chinese manufacturer)" => "Hikvision",

    # Mobotix
    "mobotix" => "Mobotix",
    "mobitix" => "Mobotix",

    # Skycop
    "skycop" => "Skycop",
    "sky cop inc." => "Skycop",

    # Turing
    "turing ai" => "Turing",
    "turing" => "Turing",
    "turing skyshield" => "Turing",

    # Sensys Gatso
    "sensys gatso usa" => "Sensys Gatso",
    "sensys gatso group" => "Sensys Gatso",
    "sensys" => "Sensys Gatso",

    # Cyber Secure (the "?"-suffixed variant is deliberately left alone)
    "cyber secure" => "Cyber Secure",

    # EPIC IO Technologies
    "epic io technologies" => "EPIC IO Technologies",
    "epic io" => "EPIC IO Technologies",

    # Gridless
    "gridless" => "Gridless",
    "gridless sentry" => "Gridless",

    # Spot AI
    "spot ai" => "Spot AI",
    "spot.ai" => "Spot AI",
    "spotai" => "Spot AI",

    # Explicit "not really known" placeholders — distinct from a camera
    # that simply has no manufacturer tag at all (stays nil, not this).
    "unknown" => "Unknown",
    "unkwn" => "Unknown",
    "unkn" => "Unknown",
    "unkown" => "Unknown",
    "generic" => "Unknown",
    "other" => "Unknown"
  }

  # Catch-all for values the exact-match table above doesn't enumerate —
  # a product model tacked on ("Axis Q1800"), a corporate suffix we
  # haven't seen yet, a new typo — for companies whose name is
  # distinctive enough that "contains this substring" is a safe bet on
  # its own. Checked only after the exact table misses, and only for
  # values that survive the `?`/multi-vendor guards below, so it can
  # never override a precise mapping or swallow a combined tag.
  @substring_aliases [
    {"flock", "Flock Safety"},
    {"axis", "Axis Communications"},
    {"cyber secure", "Cyber Secure"},
    {"motorola", "Motorola Solutions"},
    {"neology", "Neology"},
    {"spot.ai", "Spot AI"},
    {"spot ai", "Spot AI"}
  ]

  @doc """
  Normalizes a raw manufacturer/brand string. Returns `nil` for `nil`
  input, otherwise:

  * the canonical name if this exact (trimmed, case-insensitive) value is
    a known alias;
  * otherwise the trimmed original value unchanged if it ends in `?` or
    looks like a multi-vendor combined tag (see moduledoc);
  * otherwise the canonical name if the value contains one of a small set
    of distinctive company-name substrings (`@substring_aliases`) — this
    catches unenumerated variants (product models, new suffixes) without
    needing an exact entry for each one;
  * otherwise the trimmed original value unchanged.
  """
  @spec normalize(String.t() | nil) :: String.t() | nil
  def normalize(nil), do: nil

  def normalize(raw) when is_binary(raw) do
    trimmed = String.trim(raw)
    lower = String.downcase(trimmed)

    cond do
      Map.has_key?(@aliases, lower) ->
        Map.fetch!(@aliases, lower)

      String.ends_with?(trimmed, "?") ->
        trimmed

      multi_vendor?(lower) ->
        trimmed

      canonical = substring_alias(lower) ->
        canonical

      true ->
        trimmed
    end
  end

  defp multi_vendor?(lower) do
    String.contains?(lower, ";") or String.contains?(lower, " w/ ") or
      String.contains?(lower, " / ")
  end

  defp substring_alias(lower) do
    Enum.find_value(@substring_aliases, fn {needle, canonical} ->
      String.contains?(lower, needle) && canonical
    end)
  end
end
