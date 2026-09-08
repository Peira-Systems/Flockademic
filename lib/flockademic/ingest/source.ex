defmodule Flockademic.Ingest.Source do
  @moduledoc """
  Behaviour for a source adapter: something that fetches records from an
  external open dataset and normalizes them into the common attrs shape
  expected by `Flockademic.Cameras.ingest_observation/1`.

  Adapters must NOT skip normalization/validation — a caller should be able
  to treat every source uniformly (Project.md, Data Ingestion).
  """

  @type attrs :: %{
          required(:source) => String.t(),
          required(:source_id) => String.t(),
          required(:source_record_id) => String.t(),
          required(:latitude) => float(),
          required(:longitude) => float(),
          required(:observed_at) => DateTime.t(),
          optional(:manufacturer) => String.t() | nil,
          optional(:operator) => String.t() | nil,
          optional(:camera_type) => String.t() | nil,
          optional(:metadata) => map()
        }

  @callback fetch(opts :: keyword()) :: {:ok, [attrs()]} | {:error, term()}
end
