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

  @doc """
  Get all distinct categories from products that have orders.
  """
  def available_categories do
    from(p in Sales.Product,
      join: oi in assoc(p, :order_items),
      join: o in assoc(oi, :order),
      where: not is_nil(o.id),
      distinct: p.category,
      select: p.category,
      order_by: p.category
    )
    |> Repo.all()
  end

  @doc """
  Get all distinct payment methods from orders.
  """
  def available_payment_methods do
    from(o in Sales.Order,
      distinct: o.payment_method,
      select: o.payment_method,
      order_by: o.payment_method
    )
    |> Repo.all()
  end

  @doc """
  Get customer cohort retention data.
  Groups customers by their first order month and calculates retention rates.
  Returns data in format: [{cohort_month, period_index, retention_rate, customer_count}, ...]
  """
  def cohort_retention(start_date, end_date) do
    start_date = normalize_date(start_date)
    end_date = normalize_date(end_date)

    # Get all customers with their first order date
    customers =
      from(c in Sales.Customer,
        where: not is_nil(c.first_order_at) and c.first_order_at >= ^start_date and c.first_order_at <= ^end_date,
        select: %{
          customer_id: c.id,
          cohort_month: fragment("DATE_TRUNC('month', ?)", c.first_order_at)
        }
      )
      |> Repo.all()

    # Get all orders for these customers within the date range
    customer_ids = Enum.map(customers, & &1.customer_id)

    orders =
      if Enum.empty?(customer_ids) do
        []
      else
        from(o in Sales.Order,
          where: o.customer_id in ^customer_ids and o.order_date >= ^start_date and o.order_date <= ^end_date,
          select: %{
            customer_id: o.customer_id,
            order_month: fragment("DATE_TRUNC('month', ?)", o.order_date)
          },
          distinct: [o.customer_id, fragment("DATE_TRUNC('month', ?)", o.order_date)]
        )
        |> Repo.all()
      end

    # Create a map of customer_id -> cohort_month
    customer_cohorts = Map.new(customers, fn c -> {c.customer_id, c.cohort_month} end)

    # Group orders by cohort and order month
    cohort_order_map =
      orders
      |> Enum.group_by(fn order ->
        cohort_month = Map.get(customer_cohorts, order.customer_id)
        {cohort_month, order.order_month}
      end)

    # Group customers by cohort
    cohort_customers_map =
      customers
      |> Enum.group_by(& &1.cohort_month)

    # Calculate retention for each cohort
    cohort_customers_map
    |> Enum.map(fn {cohort_month, cohort_customers} ->
      cohort_size = length(cohort_customers)
      cohort_customer_ids = MapSet.new(Enum.map(cohort_customers, & &1.customer_id))

      # Get orders for this cohort
      cohort_orders =
        cohort_order_map
        |> Enum.filter(fn {{cohort, _order_month}, _orders} -> cohort == cohort_month end)
        |> Enum.flat_map(fn {_key, orders} -> orders end)

      # Group by order month and calculate retention
      periods =
        cohort_orders
        |> Enum.group_by(& &1.order_month)
        |> Enum.map(fn {order_month, orders} ->
          active_customer_ids = MapSet.new(Enum.map(orders, & &1.customer_id))
          active_count = MapSet.size(MapSet.intersection(cohort_customer_ids, active_customer_ids))
          period_index = calculate_period_index(cohort_month, order_month)
          retention_rate = if cohort_size > 0, do: active_count / cohort_size, else: 0.0

          %{
            cohort_month: cohort_month,
            period_index: period_index,
            retention_rate: retention_rate,
            customer_count: active_count
          }
        end)
        |> Enum.sort_by(& &1.period_index)

      # Always include period 0 (cohort month itself) with 100% retention
      [
        %{
          cohort_month: cohort_month,
          period_index: 0,
          retention_rate: 1.0,
          customer_count: cohort_size
        }
        | periods
      ]
    end)
    |> List.flatten()
  end

  defp calculate_period_index(cohort_month, order_month) do
    cohort_date = extract_date(cohort_month)
    order_date = extract_date(order_month)
    diff_months = (order_date.year - cohort_date.year) * 12 + (order_date.month - cohort_date.month)
    max(0, diff_months)
  end

  defp extract_date(%Date{} = date), do: date
  defp extract_date(%DateTime{} = dt), do: DateTime.to_date(dt)
  defp extract_date({year, month, _day}), do: Date.new!(year, month, 1)
  defp extract_date(_), do: Date.utc_today()

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
