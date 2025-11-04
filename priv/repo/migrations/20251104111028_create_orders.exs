defmodule PipeForge.Repo.Migrations.CreateOrders do
  use Ecto.Migration

  def up do
    # Create payment_method enum type
    execute("CREATE TYPE payment_method AS ENUM ('mpesa', 'paystack', 'card', 'bank_transfer', 'other');")

    create table(:orders, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :order_ref, :text, null: false
      add :order_date, :utc_datetime, null: false
      add :customer_id, references(:customers, type: :uuid, on_delete: :restrict), null: false
      add :total_amount, :decimal, precision: 10, scale: 2, null: false
      add :payment_method, :payment_method, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:orders, [:order_ref])
    create index(:orders, [:order_date])
    create index(:orders, [:customer_id])
    create index(:orders, [:payment_method])
  end

  def down do
    drop table(:orders)
    execute("DROP TYPE IF EXISTS payment_method;")
  end
end
