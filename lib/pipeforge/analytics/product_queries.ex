defmodule PipeForge.Analytics.ProductQueries do
  @moduledoc """
  Optimized queries for product/SKU analytics.
  """

  import Ecto.Query
  alias PipeForge.{Repo, Sales}

  @doc """
  Get top products by revenue with pagination.
  """
  def top_products_by_revenue(limit \\ 50, offset \\ 0, filters \\ %{}) do
    base_query =
      from(p in Sales.Product,
        left_join: oi in assoc(p, :order_items),
        left_join: o in assoc(oi, :order),
        where: not is_nil(o.id),
        group_by: [p.id, p.sku, p.name, p.category],
        select: %{
          id: p.id,
          sku: p.sku,
          name: p.name,
          category: p.category,
          total_revenue: sum(oi.subtotal),
          total_units: sum(oi.quantity),
          order_count: count(o.id, :distinct)
        },
        order_by: [desc: sum(oi.subtotal)],
        limit: ^limit,
        offset: ^offset
      )

    query =
      base_query
      |> maybe_filter_by_category(filters[:category])
      |> maybe_filter_by_payment_method(filters[:payment_method])

    Repo.all(query)
  end

  @doc """
  Get top products by units sold with pagination.
  """
  def top_products_by_units(limit \\ 50, offset \\ 0, filters \\ %{}) do
    base_query =
      from(p in Sales.Product,
        left_join: oi in assoc(p, :order_items),
        left_join: o in assoc(oi, :order),
        where: not is_nil(o.id),
        group_by: [p.id, p.sku, p.name, p.category],
        select: %{
          id: p.id,
          sku: p.sku,
          name: p.name,
          category: p.category,
          total_revenue: sum(oi.subtotal),
          total_units: sum(oi.quantity),
          order_count: count(o.id, :distinct)
        },
        order_by: [desc: sum(oi.quantity)],
        limit: ^limit,
        offset: ^offset
      )

    query =
      base_query
      |> maybe_filter_by_category(filters[:category])
      |> maybe_filter_by_payment_method(filters[:payment_method])

    Repo.all(query)
  end

  @doc """
  Get total count of products for pagination.
  """
  def total_product_count(filters \\ %{}) do
    base_query =
      from(p in Sales.Product,
        left_join: oi in assoc(p, :order_items),
        left_join: o in assoc(oi, :order),
        where: not is_nil(o.id),
        distinct: p.id
      )

    query =
      base_query
      |> maybe_filter_by_category(filters[:category])
      |> maybe_filter_by_payment_method(filters[:payment_method])

    Repo.aggregate(query, :count)
  end

  defp maybe_filter_by_category(query, nil), do: query

  defp maybe_filter_by_category(query, category) do
    where(query, [p], p.category == ^category)
  end

  defp maybe_filter_by_payment_method(query, nil), do: query

  defp maybe_filter_by_payment_method(query, method) do
    where(query, [p, oi, o], o.payment_method == ^method)
  end
end

