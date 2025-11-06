defmodule PipeForge.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Ensure MinIO bucket exists on startup
    ensure_storage_bucket()

    children = [
      PipeForgeWeb.Telemetry,
      PipeForge.Repo,
      {Oban, Application.get_env(:pipeforge, Oban)},
      {DNSCluster, query: Application.get_env(:pipeforge, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: PipeForge.PubSub},
      PipeForge.Ingestion.Pipeline,
      # Start to serve requests, typically the last entry
      PipeForgeWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: PipeForge.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp ensure_storage_bucket do
    case PipeForge.Storage.ensure_bucket() do
      :ok ->
        :ok

      {:error, reason} ->
        require Logger
        Logger.warning("Failed to ensure storage bucket exists: #{inspect(reason)}")
        :ok
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    PipeForgeWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
