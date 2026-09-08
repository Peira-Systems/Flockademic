defmodule Flockademic.Regions.TigerWebTest do
  use ExUnit.Case, async: true

  alias Flockademic.Regions.TigerWeb

  describe "import_state/1 input validation" do
    test "rejects anything that isn't a two-letter abbreviation before any HTTP call" do
      assert TigerWeb.import_state("GA'; DROP TABLE regions;--") ==
               {:error, :invalid_state_abbreviation}

      assert TigerWeb.import_state("USA") == {:error, :invalid_state_abbreviation}
      assert TigerWeb.import_state("") == {:error, :invalid_state_abbreviation}
      assert TigerWeb.import_state(:ga) == {:error, :invalid_state_abbreviation}
    end
  end
end
