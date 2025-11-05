defmodule PipeForge.Sales.OrderItem do
  @moduledoc """
  Order item schema representing individual products in an order.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "order_items" do
    field :quantity, :integer
    field :price, :decimal
    field :subtotal, :decimal

    belongs_to :order, PipeForge.Sales.Order, type: :binary_id
    belongs_to :product, PipeForge.Sales.Product, type: :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(order_item, attrs) do
    order_item
    |> cast(attrs, [:quantity, :price, :subtotal, :order_id, :product_id])
    |> validate_required([:quantity, :price, :subtotal, :order_id, :product_id])
    |> validate_number(:quantity, greater_than: 0)
    |> validate_number(:price, greater_than: 0)
    |> validate_number(:subtotal, greater_than: 0)
  end
end
