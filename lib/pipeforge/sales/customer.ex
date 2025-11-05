defmodule PipeForge.Sales.Customer do
  @moduledoc """
  Customer schema with hashed email for PII protection.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "customers" do
    field :email_hash, :string
    field :region, :string
    field :first_order_at, :utc_datetime
    field :last_order_at, :utc_datetime

    has_many :orders, PipeForge.Sales.Order

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(customer, attrs) do
    customer
    |> cast(attrs, [:email_hash, :region, :first_order_at, :last_order_at])
    |> validate_required([:email_hash])
    |> unique_constraint(:email_hash)
  end
end
