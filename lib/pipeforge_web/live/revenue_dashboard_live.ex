defmodule PipeForgeWeb.RevenueDashboardLive do
  use PipeForgeWeb, :live_view

  alias PipeForge.Analytics.RevenueQueries

  @default_days 30

  @impl true
  def mount(_params, _session, socket) do
    end_date = Date.utc_today()
    start_date = Date.add(end_date, -@default_days)

    socket =
      socket
      |> assign(:start_date, start_date)
      |> assign(:end_date, end_date)
      |> assign(:loading, false)
      |> assign(:revenue_data, [])
      |> assign(:total_revenue, Decimal.new("0"))
      |> assign(:filters, %{category: nil, payment_method: nil})
      |> load_revenue_data()

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    start_date = parse_date(params["start_date"]) || socket.assigns.start_date
    end_date = parse_date(params["end_date"]) || socket.assigns.end_date

    filters = %{
      category: params["category"],
      payment_method: params["payment_method"]
    }

    socket =
      socket
      |> assign(:start_date, start_date)
      |> assign(:end_date, end_date)
      |> assign(:filters, filters)
      |> load_revenue_data()

    {:noreply, socket}
  end

  @impl true
  def handle_event("update_date_range", %{"start_date" => start_str, "end_date" => end_str}, socket) do
    start_date = parse_date(start_str) || socket.assigns.start_date
    end_date = parse_date(end_str) || socket.assigns.end_date

    socket =
      socket
      |> assign(:start_date, start_date)
      |> assign(:end_date, end_date)
      |> load_revenue_data()

    {:noreply, push_patch(socket, to: build_dashboard_path(socket.assigns))}
  end

  @impl true
  def handle_event("apply_filter", %{"filter" => filter, "value" => value}, socket) do
    filters = Map.put(socket.assigns.filters, String.to_atom(filter), value)

    socket =
      socket
      |> assign(:filters, filters)
      |> load_revenue_data()

    {:noreply, push_patch(socket, to: build_dashboard_path(socket.assigns))}
  end

  defp load_revenue_data(socket) do
    start_date = socket.assigns.start_date
    end_date = socket.assigns.end_date
    filters = socket.assigns.filters

    socket = assign(socket, :loading, true)

    # Measure query time
    {time_ms, results} = :timer.tc(fn ->
      RevenueQueries.daily_revenue(start_date, end_date, filters)
    end)

    total_revenue = RevenueQueries.total_revenue(start_date, end_date, filters)

    socket
    |> assign(:revenue_data, results)
    |> assign(:total_revenue, total_revenue)
    |> assign(:query_time_ms, div(time_ms, 1000))
    |> assign(:loading, false)
  end

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil

  defp parse_date(date_string) when is_binary(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} -> date
      :error -> nil
    end
  end

  defp build_dashboard_path(assigns) do
    params = [
      {"start_date", Date.to_iso8601(assigns.start_date)},
      {"end_date", Date.to_iso8601(assigns.end_date)}
    ]

    params =
      if assigns.filters.category do
        [{"category", assigns.filters.category} | params]
      else
        params
      end

    params =
      if assigns.filters.payment_method do
        [{"payment_method", assigns.filters.payment_method} | params]
      else
        params
      end

    ~p"/dashboard/revenue?#{URI.encode_query(params)}"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="max-w-7xl mx-auto px-4 py-8">
        <div class="mb-8">
          <h1 class="text-3xl font-bold mb-4">Revenue Dashboard</h1>

          <div class="bg-blue-50 border border-blue-200 rounded-lg p-4 mb-4">
            <div class="flex items-center justify-between">
              <div>
                <p class="text-sm text-blue-800 font-medium">Total Revenue</p>
                <p class="text-2xl font-bold text-blue-900">
                  <%= format_currency(@total_revenue) %>
                </p>
              </div>
              <div class="text-sm text-blue-700">
                <p>Query Time: <span class="font-mono"><%= @query_time_ms %>ms</span></p>
                <p :if={@query_time_ms < 300} class="text-green-700">✓ Performance Target Met</p>
                <p :if={@query_time_ms >= 300} class="text-yellow-700">⚠ Above Target</p>
              </div>
            </div>
          </div>

          <div class="bg-white rounded-lg shadow-md p-6 mb-6">
            <form phx-change="update_date_range" class="flex items-end space-x-4">
              <div>
                <label class="block text-sm font-medium text-gray-700 mb-1">Start Date</label>
                <input
                  type="date"
                  name="start_date"
                  value={Date.to_iso8601(@start_date)}
                  class="px-3 py-2 border border-gray-300 rounded-lg"
                />
              </div>
              <div>
                <label class="block text-sm font-medium text-gray-700 mb-1">End Date</label>
                <input
                  type="date"
                  name="end_date"
                  value={Date.to_iso8601(@end_date)}
                  class="px-3 py-2 border border-gray-300 rounded-lg"
                />
              </div>
              <button
                type="submit"
                class="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700"
              >
                Update
              </button>
            </form>
          </div>

          <div class="bg-white rounded-lg shadow-md p-6">
            <div :if={@loading} class="text-center py-8">
              <p class="text-gray-500">Loading revenue data...</p>
            </div>

            <div :if={not @loading} id="revenue-chart-container">
              <canvas id="revenue-chart" phx-hook="RevenueChart" data-chart-data={Jason.encode!(@revenue_data)}></canvas>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp format_currency(%Decimal{} = amount) do
    amount
    |> Decimal.to_float()
    |> :erlang.float_to_binary(decimals: 2)
    |> then(&"$#{&1}")
  end

  defp format_currency(amount), do: "$#{amount}"
end
