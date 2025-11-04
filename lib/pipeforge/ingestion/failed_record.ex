defmodule PipeForge.Ingestion.FailedRecord do
  @moduledoc """
  Schema for tracking failed CSV ingestion records with error details and retry capabilities.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "failed_records" do
    field :row_number, :integer
    field :raw_data, :map
    field :error_reasons, {:array, :string}
    field :retry_count, :integer, default: 0
    field :status, :string, default: "pending"
    field :last_retried_at, :utc_datetime

    belongs_to :ingestion_file, PipeForge.Ingestion.IngestionFile

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(failed_record, attrs) do
    failed_record
    |> cast(attrs, [
      :row_number,
      :raw_data,
      :error_reasons,
      :retry_count,
      :status,
      :last_retried_at,
      :ingestion_file_id
    ])
    |> validate_required([:row_number, :raw_data, :error_reasons, :ingestion_file_id])
    |> validate_inclusion(:status, ["pending", "retrying", "succeeded", "failed"])
    |> validate_number(:retry_count, greater_than_or_equal_to: 0)
  end
end
