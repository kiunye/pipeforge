defmodule PipeForge.Repo.Migrations.CreateFailedRecords do
  use Ecto.Migration

  def change do
    create table(:failed_records) do
      add :row_number, :integer
      add :raw_data, :map
      add :error_reasons, :map
      add :retry_count, :integer
      add :status, :string
      add :last_retried_at, :utc_datetime
      add :ingestion_file_id, references(:ingestion_files, on_delete: :nothing)

      timestamps(type: :utc_datetime)
    end

    create index(:failed_records, [:ingestion_file_id])
  end
end
