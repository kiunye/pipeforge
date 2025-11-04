defmodule PipeForge.Analytics.RevenueQueries do
  @moduledoc """
  Optimized queries for revenue analytics using TimescaleDB.
  """

  import Ecto.Query
  alias PipeForge.{Repo, Sales}

  @doc """
  Get daily revenue time-series data optimized for < 300ms queries.
  Uses TimescaleDB hypertable for fast time-range queries.
  """
  def daily_revenue(start_date, end_date, filters \\ %{}) do
    start_date = normalize_date(start_date)
    end_date = normalize_date(end_date)

    base_query =
      from(o in Sales.Order,
        where: o.order_date >= ^start_date and o.order_date <= ^end_date,
        select: %{
          date: fragment("DATE(?)", o.order_date),
          revenue: sum(o.total_amount),
          order_count: count(o.id),
          unique_customers: count(o.customer_id, :distinct)
        },
        group_by: fragment("DATE(?)", o.order_date),
        order_by: fragment("DATE(?)", o.order_date)
      )

    query =
      base_query
      |> maybe_filter_by_category(filters[:category])
      |> maybe_filter_by_payment_method(filters[:payment_method])

    Repo.all(query)
  end

  @doc """
  Get total revenue for a date range.
  """
  def total_revenue(start_date, end_date, filters \\ %{}) do
    start_date = normalize_date(start_date)
    end_date = normalize_date(end_date)

    base_query =
      from(o in Sales.Order,
        where: o.order_date >= ^start_date and o.order_date <= ^end_date,
        select: sum(o.total_amount)
      )

    query =
      base_query
      |> maybe_filter_by_category(filters[:category])
      |> maybe_filter_by_payment_method(filters[:payment_method])

    Repo.one(query) || Decimal.new("0")
  end

  defp maybe_filter_by_category(query, nil), do: query

  defp maybe_filter_by_category(query, category) do
    query
    |> join(:inner, [o], oi in assoc(o, :order_items))
    |> join(:inner, [o, oi], p in assoc(oi, :product))
    |> where([o, oi, p], p.category == ^category)
    |> distinct([o], o.id)
  end

  defp maybe_filter_by_payment_method(query, nil), do: query
  defp maybe_filter_by_payment_method(query, method), do: where(query, [o], o.payment_method == ^method)

  defp normalize_date(%Date{} = date), do: DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
  defp normalize_date(%DateTime{} = dt), do: dt
  defp normalize_date(date_string) when is_binary(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} -> DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
      :error -> DateTime.utc_now()
    end
  end
  defp normalize_date(_), do: DateTime.utc_now()
end
