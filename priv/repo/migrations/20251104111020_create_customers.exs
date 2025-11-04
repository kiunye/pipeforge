defmodule PipeForge.Repo.Migrations.CreateCustomers do
  use Ecto.Migration

  def change do
    create table(:customers, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :email_hash, :text, null: false
      add :region, :text
      add :first_order_at, :utc_datetime
      add :last_order_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:customers, [:email_hash])
    create index(:customers, [:region])
  end
end
