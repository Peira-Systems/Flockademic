defmodule FlockademicWeb.Plugs.ContentSecurityPolicy do
  @moduledoc """
  Sets a `Content-Security-Policy` header on browser responses.

  A fresh per-request nonce is generated and stashed in `conn.assigns.csp_nonce`
  for the one inline `<script>` in the root layout (the theme / no-FOUC
  snippet). Everything else is `'self'`, with narrow exceptions:

    * `img-src` / `connect-src` allow CARTO's basemap tile CDN (raster tiles
      are fetched then drawn to canvas) and `data:` (the inline SVG camera
      marker built in `assets/js/hooks/map.js`).
    * `style-src` allows `'unsafe-inline'` — MapLibre GL sets inline `style`
      attributes on the map container/controls at runtime.

  Disabled in `:dev` (see `config/dev.exs`) because `phoenix_live_reload`
  injects its own inline script that a nonce policy would block.
  """

  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    if enabled?() do
      nonce = 18 |> :crypto.strong_rand_bytes() |> Base.encode64()

      conn
      |> assign(:csp_nonce, nonce)
      |> put_resp_header("content-security-policy", policy(nonce))
    else
      assign(conn, :csp_nonce, nil)
    end
  end

  defp enabled?, do: Application.get_env(:flockademic, :content_security_policy, true)

  defp policy(nonce) do
    Enum.join(
      [
        "default-src 'self'",
        "base-uri 'self'",
        "frame-ancestors 'none'",
        "form-action 'self'",
        "object-src 'none'",
        "script-src 'self' 'nonce-#{nonce}'",
        "style-src 'self' 'unsafe-inline'",
        "img-src 'self' data: https://*.basemaps.cartocdn.com",
        "font-src 'self' data:",
        "connect-src 'self' https://*.basemaps.cartocdn.com",
        "worker-src 'self'"
      ],
      "; "
    )
  end
end
