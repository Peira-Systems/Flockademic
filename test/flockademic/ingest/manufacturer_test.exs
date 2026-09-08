defmodule Flockademic.Ingest.ManufacturerTest do
  use ExUnit.Case, async: true

  alias Flockademic.Ingest.Manufacturer

  test "nil passes through as nil" do
    assert Manufacturer.normalize(nil) == nil
  end

  test "collapses case/typo/suffix variants to one canonical name" do
    for raw <- [
          "Flock Safety",
          "FLOCK SAFETY",
          "Flock Group Inc.",
          "Flock Safety Inc",
          "flock",
          "FlockSafety",
          "Flow Safety",
          "Flock Surveillance"
        ] do
      assert Manufacturer.normalize(raw) == "Flock Safety", "expected #{raw} to normalize"
    end

    for raw <- ["Motorola Solutions", "Motorola", "Mortorola Solutions", "Motorolla", "Vigilant"] do
      assert Manufacturer.normalize(raw) == "Motorola Solutions"
    end
  end

  test "resolves a known Wikidata QID pasted into the manufacturer field" do
    assert Manufacturer.normalize("Q108485435") == "Flock Safety"
    assert Manufacturer.normalize("wikidata=Q108485435") == "Flock Safety"
  end

  test "resolves brand-name product lines to their parent company" do
    assert Manufacturer.normalize("AutoVu Cloudrunner") == "Genetec"
    assert Manufacturer.normalize("ELSAG") == "Leonardo"
    assert Manufacturer.normalize("Gridless Sentry") == "Gridless"
  end

  test "consolidates explicit unknown-placeholder values, distinct from nil" do
    for raw <- ["Unknown", "unknown", "Unkwn", "unkn", "Unkown", "generic", "other"] do
      assert Manufacturer.normalize(raw) == "Unknown"
    end
  end

  test "leaves uncertainty-marked values alone rather than guessing" do
    assert Manufacturer.normalize("Cyber Secure?") == "Cyber Secure?"
    assert Manufacturer.normalize("SCM?") == "SCM?"
    assert Manufacturer.normalize("Motorola?") == "Motorola?"
  end

  test "leaves multi-vendor combined tags alone rather than merging" do
    assert Manufacturer.normalize("Flock Safety;Motorola Solutions") ==
             "Flock Safety;Motorola Solutions"

    assert Manufacturer.normalize("Other w/ Rekor Scout") == "Other w/ Rekor Scout"
  end

  test "leaves genuinely unrecognized values unchanged (trimmed)" do
    assert Manufacturer.normalize("  Some New Vendor  ") == "Some New Vendor"
    assert Manufacturer.normalize("Municipal Parking Services") == "Municipal Parking Services"
  end

  test "substring-matches unenumerated variants of a distinctive company name" do
    assert Manufacturer.normalize("Axis Q1800") == "Axis Communications"
    assert Manufacturer.normalize("Flock Surveillance Camera") == "Flock Safety"
    assert Manufacturer.normalize("Cyber Secure Corp") == "Cyber Secure"
    assert Manufacturer.normalize("Motorola APX8000") == "Motorola Solutions"
    assert Manufacturer.normalize("Neology Corp") == "Neology"
    assert Manufacturer.normalize("spot ai") == "Spot AI"
    assert Manufacturer.normalize("spot.ai") == "Spot AI"
  end

  test "substring matching still respects the ?/multi-vendor guards" do
    assert Manufacturer.normalize("Motorola?") == "Motorola?"
    assert Manufacturer.normalize("Flock Safety;Motorola Solutions") ==
             "Flock Safety;Motorola Solutions"

    assert Manufacturer.normalize("Neology / PIPS") == "Neology / PIPS"
  end
end
