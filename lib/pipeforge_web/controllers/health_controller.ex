defmodule PipeForgeWeb.HealthController do
  use PipeForgeWeb, :controller

  def health(conn, _params) do
    json(conn, %{status: "ok", timestamp: DateTime.utc_now()})
  end

  def ready(conn, _params) do
    case check_database() do
      :ok ->
        json(conn, %{status: "ready", database: "connected", timestamp: DateTime.utc_now()})

      {:error, reason} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{
          status: "not_ready",
          database: "disconnected",
          error: inspect(reason),
          timestamp: DateTime.utc_now()
        })
    end
  end

  defp check_database do
    try do
      PipeForge.Repo.query!("SELECT 1", [], timeout: 5_000)
      :ok
    rescue
      e -> {:error, e}
    catch
      :exit, reason -> {:error, reason}
    end
  end
end
