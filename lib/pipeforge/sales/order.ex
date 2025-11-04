defmodule PipeForge.Sales.Order do
  @moduledoc """
  Order schema representing customer purchases.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "orders" do
    field :order_ref, :string
    field :order_date, :utc_datetime
    field :total_amount, :decimal
    field :payment_method, :string

    belongs_to :customer, PipeForge.Sales.Customer, type: :binary_id
    has_many :order_items, PipeForge.Sales.OrderItem

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(order, attrs) do
    order
    |> cast(attrs, [:order_ref, :order_date, :total_amount, :payment_method, :customer_id])
    |> validate_required([:order_ref, :order_date, :total_amount, :payment_method, :customer_id])
    |> unique_constraint(:order_ref)
  end
end
