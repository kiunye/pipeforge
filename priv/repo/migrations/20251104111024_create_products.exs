defmodule PipeForge.Repo.Migrations.CreateProducts do
  use Ecto.Migration

  def change do
    create table(:products, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :sku, :text, null: false
      add :name, :text, null: false
      add :category, :text
      add :base_price, :decimal, precision: 10, scale: 2, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:products, [:sku])
    create index(:products, [:category])
  end
end
