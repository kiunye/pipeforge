defmodule PipeForge.Repo do
  use Ecto.Repo,
    otp_app: :pipeforge,
    adapter: Ecto.Adapters.Postgres
end
