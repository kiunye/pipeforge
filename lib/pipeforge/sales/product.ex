defmodule PipeForge.Sales.Product do
  @moduledoc """
  Product schema for catalog items.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "products" do
    field :sku, :string
    field :name, :string
    field :category, :string
    field :base_price, :decimal

    has_many :order_items, PipeForge.Sales.OrderItem

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(product, attrs) do
    product
    |> cast(attrs, [:sku, :name, :category, :base_price])
    |> validate_required([:sku, :name, :category, :base_price])
    |> unique_constraint(:sku)
  end
end
