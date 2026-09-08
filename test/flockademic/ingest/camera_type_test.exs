defmodule Flockademic.Ingest.CameraTypeTest do
  use ExUnit.Case, async: true

  alias Flockademic.Ingest.CameraType

  test "nil passes through as nil" do
    assert CameraType.normalize(nil) == nil
  end

  test "collapses case/typo/punctuation variants to one canonical name" do
    for raw <- ["public", "Public", "PUBLIC", "pubic"] do
      assert CameraType.normalize(raw) == "Public"
    end

    for raw <- ["traffic", "trafic", "teaffic", "traffic;"] do
      assert CameraType.normalize(raw) == "Traffic"
    end

    for raw <- ["camera", "camerea", "camera,"] do
      assert CameraType.normalize(raw) == "Camera"
    end
  end

  test "collapses a tagger writing the brand name where a type belongs" do
    for raw <- [
          "flock",
          "flock_camera",
          "flock_safety",
          "flock_saftey",
          "flock_saftey_camera",
          "flock_360_ptz_camera",
          "flock_alpr",
          "alpr_flock"
        ] do
      assert CameraType.normalize(raw) == "Flock", "expected #{raw} to normalize"
    end
  end

  test "resolves ALPR spelled out or mis-tagged as a key=value dump" do
    assert CameraType.normalize("alpr") == "ALPR"
    assert CameraType.normalize("ALPR") == "ALPR"
    assert CameraType.normalize("type=alpr") == "ALPR"
    assert CameraType.normalize("type=ALPR") == "ALPR"
    assert CameraType.normalize("license_plate_reader") == "ALPR"
    assert CameraType.normalize("alpr_camera") == "ALPR Camera"
  end

  test "title-cases other recognized single-concept values" do
    assert CameraType.normalize("red_light") == "Red Light"
    assert CameraType.normalize("parking_lot") == "Parking Lot"
    assert CameraType.normalize("average_speed") == "Average Speed"
    assert CameraType.normalize("cctv") == "CCTV"
  end

  test "leaves multi-value lists alone rather than merging" do
    for raw <- [
          "public, outdoor, traffic",
          "camera,_ai,_flock,_police",
          "camera;public",
          "traffic;public",
          "public outdoor traffic"
        ] do
      assert CameraType.normalize(raw) == raw
    end
  end

  test "leaves raw tag dumps and operator names alone rather than guessing" do
    assert CameraType.normalize("man_made=surveillance") == "man_made=surveillance"
    assert CameraType.normalize("Troy PD") == "Troy PD"
    assert CameraType.normalize("Auburn Police Department") == "Auburn Police Department"
  end

  test "leaves genuinely unrecognized values unchanged (trimmed)" do
    assert CameraType.normalize("  yes  ") == "yes"
    assert CameraType.normalize("raven") == "raven"
  end
end
