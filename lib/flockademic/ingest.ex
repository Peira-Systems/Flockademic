defmodule Flockademic.Ingest do
  @moduledoc """
  Runs a `Flockademic.Ingest.Source` adapter and idempotently persists
  whatever it returns via `Flockademic.Cameras.ingest_observation/1`.
  """

  alias Flockademic.Cameras

  def run(source_mod, opts \\ []) do
    with {:ok, records} <- source_mod.fetch(opts) do
      {:ok, Enum.map(records, &Cameras.ingest_observation/1)}
    end
  end

  @doc """
  Runs `source_mod` repeatedly over a grid of bounding-box tiles covering
  `bbox` (`{south, west, north, east}`), instead of one large query.

  The public Overpass instance times out on area-heavy queries well below
  the size of a US state (confirmed empirically: a mid-size metro-area bbox
  already 504'd). Tiling keeps each request small. A camera that falls in
  two overlapping tiles is simply observed twice, which `Cameras.
  ingest_observation/1`'s idempotency already handles correctly.

  Options:

    * `:tile_degrees` - tile edge length in degrees (default `0.5`)
    * `:delay_ms` - pause between requests, to stay polite to the shared
      public instance (default `1000`)

  Any other opts are forwarded to `source_mod.fetch/1` (e.g. `:overpass_url`).
  """
  def run_grid(source_mod, bbox, opts \\ []) do
    {tile_degrees, opts} = Keyword.pop(opts, :tile_degrees, 0.5)
    {delay_ms, opts} = Keyword.pop(opts, :delay_ms, 1_000)
    {south, west, north, east} = bbox

    tiles =
      for s <- frange(south, north, tile_degrees), w <- frange(west, east, tile_degrees) do
        {s, w, min(s + tile_degrees, north), min(w + tile_degrees, east)}
      end

    Enum.reduce(tiles, %{ingested: 0, failed_tiles: []}, fn tile, acc ->
      Process.sleep(delay_ms)

      case source_mod.fetch(Keyword.put(opts, :bbox, tile)) do
        {:ok, records} ->
          count =
            records
            |> Enum.map(&Cameras.ingest_observation/1)
            |> Enum.count(&match?({:ok, _}, &1))

          %{acc | ingested: acc.ingested + count}

        {:error, reason} ->
          %{acc | failed_tiles: [{tile, reason} | acc.failed_tiles]}
      end
    end)
  end

  defp frange(from, to, step) do
    Stream.iterate(from, &(&1 + step)) |> Enum.take_while(&(&1 < to))
  end
end
