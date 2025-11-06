defmodule PipeForge.Rollups.DailyRollupWorker do
  @moduledoc """
  Oban worker that aggregates daily sales data into sales_aggregates_daily table.
  Runs daily via cron to pre-compute aggregations for fast dashboard queries.
  """

  use Oban.Worker, queue: :rollups, max_attempts: 3

  require Logger
  import Ecto.Query
  alias PipeForge.{Repo, Rollups.SalesAggregateDaily}
  alias PipeForge.Sales.Order

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"date" => date_string}}) do
    date = Date.from_iso8601!(date_string)
    Logger.info("Starting daily rollup for date: #{date}")

    case aggregate_daily_sales(date) do
      {:ok, count} ->
        Logger.info("Successfully aggregated #{count} records for date: #{date}")
        :ok

      {:error, reason} ->
        Logger.error("Failed to aggregate daily sales for #{date}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def perform(%Oban.Job{args: %{}}) do
    # Default to yesterday if no date provided
    yesterday = Date.add(Date.utc_today(), -1)
    perform(%Oban.Job{args: %{"date" => Date.to_iso8601(yesterday)}})
  end

  @doc """
  Aggregates sales data for a specific date.
  Groups by product_id, category, and payment_method.
  """
  def aggregate_daily_sales(date) do
    start_datetime = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
    end_datetime = DateTime.new!(date, ~T[23:59:59], "Etc/UTC")

    # Query to aggregate sales by product, category, and payment method
    aggregates =
      from(o in Order,
        inner_join: oi in assoc(o, :order_items),
        inner_join: p in assoc(oi, :product),
        where:
          o.order_date >= ^start_datetime and
            o.order_date <= ^end_datetime,
        group_by: [p.id, p.category, o.payment_method],
        select: %{
          date: ^date,
          product_id: p.id,
          category: p.category,
          payment_method: o.payment_method,
          total_revenue: sum(oi.subtotal),
          total_units: sum(oi.quantity),
          order_count: count(o.id, :distinct),
          unique_customers: count(o.customer_id, :distinct)
        }
      )
      |> Repo.all()

    Logger.info("Found #{length(aggregates)} aggregation groups for date: #{date}")

    # Upsert aggregates using ON CONFLICT
    result =
      Repo.transaction(fn ->
        Enum.reduce_while(aggregates, 0, fn attrs, acc ->
          changeset = SalesAggregateDaily.changeset(%SalesAggregateDaily{}, attrs)

          case Repo.insert(
                 changeset,
                 on_conflict: {:replace_all_except, [:date, :product_id, :category, :payment_method]},
                 conflict_target: [:date, :product_id, :category, :payment_method]
               ) do
            {:ok, _} -> {:cont, acc + 1}
            {:error, changeset} -> {:halt, {:error, changeset}}
          end
        end)
      end)

    case result do
      {:ok, count} -> {:ok, count}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Backfill aggregates for a date range.
  Useful for initial setup or fixing missing data.
  """
  def backfill_aggregates(start_date, end_date) do
    dates = Date.range(start_date, end_date) |> Enum.to_list()

    Logger.info("Backfilling aggregates for #{length(dates)} days")

    results =
      Enum.map(dates, fn date ->
        case aggregate_daily_sales(date) do
          {:ok, count} -> {:ok, date, count}
          {:error, reason} -> {:error, date, reason}
        end
      end)

    successful = Enum.count(results, fn r -> match?({:ok, _, _}, r) end)
    failed = Enum.count(results, fn r -> match?({:error, _, _}, r) end)

    Logger.info("Backfill complete: #{successful} successful, #{failed} failed")

    results
  end
end

