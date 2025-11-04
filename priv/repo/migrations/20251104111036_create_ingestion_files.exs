defmodule PipeForge.Repo.Migrations.CreateIngestionFiles do
  use Ecto.Migration

  def change do
    create table(:ingestion_files, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :filename, :text, null: false
      add :file_path, :text, null: false
      add :content_hash, :text, null: false
      add :status, :text, null: false, default: "pending"
      add :total_rows, :integer
      add :processed_rows, :integer, default: 0
      add :failed_rows, :integer, default: 0
      add :error_message, :text
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:ingestion_files, [:content_hash])
    create index(:ingestion_files, [:status])
    create index(:ingestion_files, [:inserted_at])
  end
end
