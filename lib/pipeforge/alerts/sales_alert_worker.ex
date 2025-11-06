defmodule PipeForge.Alerts.SalesAlertWorker do
  @moduledoc """
  Oban worker that checks for sales drops/spikes and sends alerts.
  Runs after daily rollups complete to compare current day vs previous day and YOY.
  """

  use Oban.Worker, queue: :alerts, max_attempts: 3

  require Logger
  import Ecto.Query
  alias PipeForge.Alerts
  alias PipeForge.Repo
  alias PipeForge.Rollups.SalesAggregateDaily
  alias PipeForge.Sales.Order

  # Thresholds for alerts (configurable)
  @drop_threshold -10.0  # Alert if revenue drops by 10% or more
  @spike_threshold 20.0  # Alert if revenue spikes by 20% or more
  @product_spike_threshold 30.0  # Alert if product units spike by 30% or more

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"date" => date_string}}) do
    date = Date.from_iso8601!(date_string)
    Logger.info("Starting sales alert check for date: #{date}")

    check_sales_alerts(date)
  end

  def perform(%Oban.Job{args: %{}}) do
    # Default to yesterday if no date provided
    yesterday = Date.add(Date.utc_today(), -1)
    perform(%Oban.Job{args: %{"date" => Date.to_iso8601(yesterday)}})
  end

  @doc """
  Checks for sales drops/spikes and sends alerts.
  """
  def check_sales_alerts(date) do
    with :ok <- check_day_over_day(date),
         :ok <- check_year_over_year(date),
         :ok <- check_product_spikes(date) do
      Logger.info("Completed sales alert checks for date: #{date}")
      :ok
    else
      {:error, reason} ->
        Logger.error("Error checking sales alerts: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp check_day_over_day(date) do
    previous_date = Date.add(date, -1)

    current_revenue = get_total_revenue_for_date(date)
    previous_revenue = get_total_revenue_for_date(previous_date)

    if previous_revenue > 0 do
      change_percent = ((current_revenue - previous_revenue) / previous_revenue) * 100

      cond do
        change_percent <= @drop_threshold ->
          Logger.warning("Day-over-day revenue drop detected: #{change_percent |> :erlang.float_to_binary(decimals: 1)}%")
          send_alerts("Day-over-Day Drop", current_revenue, previous_revenue, date, change_percent)
          :ok

        change_percent >= @spike_threshold ->
          Logger.info("Day-over-day revenue spike detected: #{change_percent |> :erlang.float_to_binary(decimals: 1)}%")
          send_alerts("Day-over-Day Spike", current_revenue, previous_revenue, date, change_percent)
          :ok

        true ->
          :ok
      end
    else
      Logger.info("No previous day data for comparison")
      :ok
    end
  end

  defp check_year_over_year(date) do
    same_date_last_year = %{date | year: date.year - 1}

    current_revenue = get_total_revenue_for_date(date)
    yoy_revenue = get_total_revenue_for_date(same_date_last_year)

    if yoy_revenue > 0 do
      change_percent = ((current_revenue - yoy_revenue) / yoy_revenue) * 100

      cond do
        change_percent <= @drop_threshold ->
          Logger.warning("Year-over-year revenue drop detected: #{change_percent |> :erlang.float_to_binary(decimals: 1)}%")
          send_alerts("Year-over-Year Drop", current_revenue, yoy_revenue, date, change_percent)
          :ok

        change_percent >= @spike_threshold ->
          Logger.info("Year-over-year revenue spike detected: #{change_percent |> :erlang.float_to_binary(decimals: 1)}%")
          send_alerts("Year-over-Year Spike", current_revenue, yoy_revenue, date, change_percent)
          :ok

        true ->
          :ok
      end
    else
      Logger.info("No year-over-year data for comparison")
      :ok
    end
  end

  defp check_product_spikes(date) do
    previous_date = Date.add(date, -1)

    # Get top products by units for current day
    current_products = get_top_products_by_units(date, 10)
    previous_products = get_top_products_by_units(previous_date, 10)

    # Create a map of previous day products for quick lookup
    previous_map =
      previous_products
      |> Enum.into(%{}, fn %{product_id: id, total_units: units} -> {id, units} end)

    # Check each current product for spikes
    Enum.each(current_products, fn %{
                                     product_id: product_id,
                                     total_units: current_units,
                                     product_name: name,
                                     category: category
                                   } ->
      previous_units = Map.get(previous_map, product_id, 0)

      if previous_units > 0 do
        change_percent = ((current_units - previous_units) / previous_units) * 100

        if change_percent >= @product_spike_threshold do
          change_str = change_percent |> :erlang.float_to_binary(decimals: 1)
          Logger.info("Product performance spike detected: #{name} - #{change_str}%")
          Alerts.EmailNotifier.send_product_spike_alert(name, category, current_units, previous_units, date, change_percent)
          Alerts.SlackNotifier.send_product_spike_alert(name, category, current_units, previous_units, date, change_percent)
        end
      end
    end)

    :ok
  end

  defp get_total_revenue_for_date(date) do
    start_datetime = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
    end_datetime = DateTime.new!(date, ~T[23:59:59], "Etc/UTC")

    query =
      from(o in Order,
        where: o.order_date >= ^start_datetime and o.order_date <= ^end_datetime,
        select: sum(o.total_amount)
      )

    result = Repo.one(query)

    decimal_value =
      case result do
        nil -> Decimal.new("0")
        value -> value
      end

    Decimal.to_float(decimal_value)
  end

  defp get_top_products_by_units(date, limit) do
    from(sa in SalesAggregateDaily,
      inner_join: p in assoc(sa, :product),
      where: sa.date == ^date,
      group_by: [sa.product_id, p.name, p.category],
      select: %{
        product_id: sa.product_id,
        total_units: sum(sa.total_units),
        product_name: p.name,
        category: p.category
      },
      order_by: [desc: sum(sa.total_units)],
      limit: ^limit
    )
    |> Repo.all()
  end

  defp send_alerts(alert_type, current_value, previous_value, date, change_percent) do
    current_decimal = Decimal.from_float(current_value)
    previous_decimal = Decimal.from_float(previous_value)

    Alerts.EmailNotifier.send_sales_alert(alert_type, current_decimal, previous_decimal, date, change_percent)
    Alerts.SlackNotifier.send_sales_alert(alert_type, current_decimal, previous_decimal, date, change_percent)
  end
end
