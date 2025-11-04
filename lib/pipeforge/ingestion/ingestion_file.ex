defmodule PipeForge.Ingestion.IngestionFile do
  use Ecto.Schema
  import Ecto.Changeset

  schema "ingestion_files" do
    field :filename, :string
    field :file_path, :string
    field :content_hash, :string
    field :status, :string
    field :total_rows, :integer
    field :processed_rows, :integer
    field :failed_rows, :integer
    field :error_message, :string
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(ingestion_file, attrs) do
    ingestion_file
    |> cast(attrs, [
      :filename,
      :file_path,
      :content_hash,
      :status,
      :total_rows,
      :processed_rows,
      :failed_rows,
      :error_message,
      :started_at,
      :completed_at
    ])
    |> validate_required([:filename, :file_path, :content_hash, :status])
    |> validate_inclusion(:status, ["pending", "processing", "completed", "failed"])
    |> unique_constraint(:content_hash)
  end
end
