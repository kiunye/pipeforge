defmodule PipeForge.Rollups.SalesAggregateDaily do
  @moduledoc """
  Schema for daily sales aggregates stored in TimescaleDB hypertable.
  """

  use Ecto.Schema
  import Ecto.Changeset
  alias PipeForge.Sales.Product

  @primary_key false
  schema "sales_aggregates_daily" do
    field :date, :date, primary_key: true
    belongs_to :product, Product, type: :binary_id, primary_key: true
    field :category, :string, primary_key: true
    field :payment_method, :string, primary_key: true
    field :total_revenue, :decimal
    field :total_units, :integer
    field :order_count, :integer
    field :unique_customers, :integer

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(aggregate, attrs) do
    aggregate
    |> cast(attrs, [
      :date,
      :product_id,
      :category,
      :payment_method,
      :total_revenue,
      :total_units,
      :order_count,
      :unique_customers
    ])
    |> validate_required([
      :date,
      :product_id,
      :category,
      :payment_method,
      :total_revenue,
      :total_units,
      :order_count,
      :unique_customers
    ])
    |> validate_number(:total_revenue, greater_than_or_equal_to: 0)
    |> validate_number(:total_units, greater_than_or_equal_to: 0)
    |> validate_number(:order_count, greater_than_or_equal_to: 0)
    |> validate_number(:unique_customers, greater_than_or_equal_to: 0)
  end
end

