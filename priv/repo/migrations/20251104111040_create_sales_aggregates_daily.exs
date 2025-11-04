defmodule PipeForge.Repo.Migrations.CreateSalesAggregatesDaily do
  use Ecto.Migration

  def up do
    # Create table with date as part of composite primary key
    # TimescaleDB requires the partitioning column (date) to be in the primary key
    create table(:sales_aggregates_daily, primary_key: false) do
      add :date, :date, null: false, primary_key: true
      add :product_id, references(:products, type: :uuid, on_delete: :restrict), primary_key: true
      add :category, :text, primary_key: true
      add :payment_method, :text, primary_key: true
      add :total_revenue, :decimal, precision: 12, scale: 2, null: false, default: 0
      add :total_units, :integer, null: false, default: 0
      add :order_count, :integer, null: false, default: 0
      add :unique_customers, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    # Convert to TimescaleDB hypertable for time-series optimization
    # date is already in the primary key, so this will work
    execute("SELECT create_hypertable('sales_aggregates_daily', 'date', if_not_exists => true);")

    # Create additional indexes for query optimization
    create index(:sales_aggregates_daily, [:date])
    create index(:sales_aggregates_daily, [:product_id])
    create index(:sales_aggregates_daily, [:category])
    create index(:sales_aggregates_daily, [:payment_method])
  end

  def down do
    drop table(:sales_aggregates_daily)
  end
end
