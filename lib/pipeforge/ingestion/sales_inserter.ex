defmodule PipeForge.Ingestion.SalesInserter do
  @moduledoc """
  Handles idempotent insertion of sales data from CSV rows.
  """

  alias PipeForge.{Repo, Sales}
  alias PipeForge.Sales.{Customer, Order, OrderItem, Product}
  alias PipeForge.Ingestion.FileHasher

  @doc """
  Inserts validated CSV rows into the database.
  Returns the count of successfully inserted records.
  """
  def insert_records(valid_rows, _ingestion_file) when is_list(valid_rows) do
    Repo.transaction(fn ->
      Enum.reduce(valid_rows, 0, fn row_data, acc ->
        case insert_order(row_data) do
          {:ok, _} -> acc + 1
          {:error, _} -> acc
        end
      end)
    end)
  end

  defp insert_order(row_data) do
    with {:ok, customer} <- get_or_create_customer(row_data),
         {:ok, product} <- get_or_create_product(row_data),
         {:ok, order} <- get_or_create_order(row_data, customer),
         {:ok, _order_item} <- get_or_create_order_item(row_data, order, product) do
      {:ok, order}
    else
      error -> error
    end
  end

  defp get_or_create_customer(%{"customer_email" => email, "region" => region}) do
    email_hash = FileHasher.hash_content(email)

    case Repo.get_by(Customer, email_hash: email_hash) do
      nil ->
        %Customer{}
        |> Customer.changeset(%{
          email_hash: email_hash,
          region: region,
          first_order_at: nil,
          last_order_at: nil
        })
        |> Repo.insert()

      customer ->
        {:ok, customer}
    end
  end

  defp get_or_create_product(%{
         "product_sku" => sku,
         "product_name" => name,
         "product_category" => category,
         "unit_price" => unit_price
       }) do
    case Repo.get_by(Product, sku: sku) do
      nil ->
        %Product{}
        |> Product.changeset(%{
          sku: sku,
          name: name,
          category: category,
          base_price: parse_decimal(unit_price)
        })
        |> Repo.insert()

      product ->
        {:ok, product}
    end
  end

  defp get_or_create_order(
         %{
           "order_ref" => order_ref,
           "order_date" => order_date,
           "total_amount" => total_amount,
           "payment_method" => payment_method
         },
         customer
       ) do
    case Repo.get_by(Order, order_ref: order_ref) do
      nil ->
        order_date_dt = parse_datetime(order_date)

        %Order{}
        |> Order.changeset(%{
          order_ref: order_ref,
          order_date: order_date_dt,
          total_amount: parse_decimal(total_amount),
          payment_method: normalize_payment_method(payment_method),
          customer_id: customer.id
        })
        |> Repo.insert()
        |> case do
          {:ok, order} ->
            update_customer_order_dates(customer, order_date_dt)
            {:ok, order}

          error ->
            error
        end

      order ->
        {:ok, order}
    end
  end

  defp get_or_create_order_item(
         %{
           "order_ref" => order_ref,
           "quantity" => quantity,
           "unit_price" => unit_price,
           "total_amount" => total_amount
         },
         order,
         product
       ) do
    # Check if order item already exists
    case Repo.get_by(OrderItem, order_id: order.id, product_id: product.id) do
      nil ->
        %OrderItem{}
        |> OrderItem.changeset(%{
          order_id: order.id,
          product_id: product.id,
          quantity: parse_integer(quantity),
          price: parse_decimal(unit_price),
          subtotal: parse_decimal(total_amount)
        })
        |> Repo.insert()

      order_item ->
        {:ok, order_item}
    end
  end

  defp update_customer_order_dates(customer, order_date) do
    updates = %{}

    updates =
      if is_nil(customer.first_order_at) or order_date < customer.first_order_at do
        Map.put(updates, :first_order_at, order_date)
      else
        updates
      end

    updates =
      if is_nil(customer.last_order_at) or order_date > customer.last_order_at do
        Map.put(updates, :last_order_at, order_date)
      else
        updates
      end

    if map_size(updates) > 0 do
      customer
      |> Customer.changeset(updates)
      |> Repo.update()
    else
      {:ok, customer}
    end
  end

  defp parse_decimal(value) when is_binary(value) do
    case Float.parse(value) do
      {float, _} -> Decimal.from_float(float)
      :error -> Decimal.new(0)
    end
  end

  defp parse_decimal(value), do: Decimal.new(value || 0)

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> 0
    end
  end

  defp parse_integer(value), do: value || 0

  defp parse_datetime(date_string) when is_binary(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} ->
        date
        |> DateTime.new!(~T[00:00:00], "Etc/UTC")

      :error ->
        DateTime.utc_now()
    end
  end

  defp parse_datetime(value), do: value || DateTime.utc_now()

  defp normalize_payment_method(method) when is_binary(method) do
    method
    |> String.downcase()
    |> String.trim()
    |> case do
      "mpesa" -> "mpesa"
      "paystack" -> "paystack"
      "card" -> "card"
      "bank_transfer" -> "bank_transfer"
      _ -> "other"
    end
  end

  defp normalize_payment_method(_), do: "other"
end

