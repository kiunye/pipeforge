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
      |> assign(:cohort_data, [])
      |> assign(:total_revenue, Decimal.new("0"))
      |> assign(:filters, %{category: nil, payment_method: nil})
      |> assign(:categories, RevenueQueries.available_categories())
      |> assign(:payment_methods, RevenueQueries.available_payment_methods())
      |> load_revenue_data()
      |> load_cohort_data()

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
      |> load_cohort_data()

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
      |> load_cohort_data()

    {:noreply, push_patch(socket, to: build_dashboard_path(socket.assigns))}
  end

  @impl true
  def handle_event("apply_filter", %{"filter" => filter, "value" => value}, socket) do
    filter_value = if value == "", do: nil, else: value
    filters = Map.put(socket.assigns.filters, String.to_atom(filter), filter_value)

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

  defp load_cohort_data(socket) do
    start_date = socket.assigns.start_date
    end_date = socket.assigns.end_date

    cohort_data = RevenueQueries.cohort_retention(start_date, end_date)

    assign(socket, :cohort_data, cohort_data)
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
      <div class="min-h-screen bg-gray-50">
        <div class="w-full px-4 sm:px-6 lg:px-8 py-6">
          <!-- Header Section -->
          <div class="mb-6">
            <h1 class="text-3xl font-bold text-gray-900 mb-1">Revenue Dashboard</h1>
            <p class="text-gray-600 text-sm">Track revenue trends and customer cohort retention</p>
          </div>

          <!-- Total Revenue Card -->
          <div class="bg-white rounded-lg shadow-sm border border-gray-200 p-6 mb-6">
            <div class="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4">
              <div>
                <p class="text-sm font-medium text-gray-600 mb-1">Total Revenue</p>
                <p class="text-3xl font-bold text-gray-900">
                  <%= format_currency(@total_revenue) %>
                </p>
              </div>
              <div class="flex items-center gap-6">
                <div class="text-right">
                  <p class="text-sm text-gray-600">Query Time</p>
                  <p class="text-lg font-semibold font-mono text-gray-900"><%= @query_time_ms %>ms</p>
                </div>
                <div :if={@query_time_ms < 300} class="flex items-center gap-2 px-3 py-1.5 bg-green-50 rounded-lg border border-green-200">
                  <svg class="w-4 h-4 text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path>
                  </svg>
                  <span class="text-sm font-medium text-green-700">Target Met</span>
                </div>
                <div :if={@query_time_ms >= 300} class="flex items-center gap-2 px-3 py-1.5 bg-yellow-50 rounded-lg border border-yellow-200">
                  <svg class="w-4 h-4 text-yellow-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"></path>
                  </svg>
                  <span class="text-sm font-medium text-yellow-700">Above Target</span>
                </div>
              </div>
            </div>
          </div>

          <!-- Filters Card -->
          <div class="bg-white rounded-lg shadow-sm border border-gray-200 p-6 mb-6">
            <form phx-change="update_date_range" class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-5 gap-4">
              <div>
                <label class="block text-sm font-medium text-gray-700 mb-2">Start Date</label>
                <input
                  type="date"
                  name="start_date"
                  value={Date.to_iso8601(@start_date)}
                  class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:border-gray-500 focus:ring-1 focus:ring-gray-500 transition-all"
                />
              </div>
              <div>
                <label class="block text-sm font-medium text-gray-700 mb-2">End Date</label>
                <input
                  type="date"
                  name="end_date"
                  value={Date.to_iso8601(@end_date)}
                  class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:border-gray-500 focus:ring-1 focus:ring-gray-500 transition-all"
                />
              </div>
              <div>
                <label class="block text-sm font-medium text-gray-700 mb-2">Category</label>
                <select
                  name="category"
                  phx-change="apply_filter"
                  phx-value-filter="category"
                  class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:border-gray-500 focus:ring-1 focus:ring-gray-500 transition-all bg-white"
                >
                  <option value="">All Categories</option>
                  <%= for category <- @categories do %>
                    <option value={category} selected={@filters.category == category}>
                      <%= category %>
                    </option>
                  <% end %>
                </select>
              </div>
              <div>
                <label class="block text-sm font-medium text-gray-700 mb-2">Payment Method</label>
                <select
                  name="payment_method"
                  phx-change="apply_filter"
                  phx-value-filter="payment_method"
                  class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:border-gray-500 focus:ring-1 focus:ring-gray-500 transition-all bg-white capitalize"
                >
                  <option value="">All Methods</option>
                  <%= for method <- @payment_methods do %>
                    <option value={method} selected={@filters.payment_method == method}>
                      <%= String.replace(method, "_", " ") |> String.capitalize() %>
                    </option>
                  <% end %>
                </select>
              </div>
              <div class="flex items-end">
                <button
                  type="submit"
                  class="w-full px-4 py-2 bg-gray-900 text-white font-medium rounded-lg hover:bg-gray-800 transition-colors"
                >
                  Update
                </button>
              </div>
            </form>
          </div>

          <!-- Charts Grid -->
          <div class="grid grid-cols-1 xl:grid-cols-2 gap-6">
            <!-- Revenue Trend Chart -->
            <div class="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
              <div class="mb-6">
                <h2 class="text-xl font-semibold text-gray-900">Revenue Trend</h2>
              </div>
              <div :if={@loading} class="text-center py-16">
                <div class="inline-block animate-spin rounded-full h-10 w-10 border-4 border-gray-300 border-t-gray-900"></div>
                <p class="mt-4 text-gray-600">Loading revenue data...</p>
              </div>
              <div :if={not @loading} id="revenue-chart-container" class="h-80">
                <canvas id="revenue-chart" phx-hook="RevenueChart" data-chart-data={Jason.encode!(@revenue_data)}></canvas>
              </div>
            </div>

            <!-- Cohort Chart -->
            <div class="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
              <div class="mb-6">
                <h2 class="text-xl font-semibold text-gray-900">Customer Cohort Retention</h2>
              </div>
              <div :if={@loading} class="text-center py-16">
                <div class="inline-block animate-spin rounded-full h-10 w-10 border-4 border-gray-300 border-t-gray-900"></div>
                <p class="mt-4 text-gray-600">Loading cohort data...</p>
              </div>
              <div :if={not @loading} id="cohort-chart-container" class="h-80">
                <canvas id="cohort-chart" phx-hook="CohortChart" data-chart-data={Jason.encode!(@cohort_data)}></canvas>
              </div>
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
    |> then(&"KES #{&1}")
  end

  defp format_currency(amount), do: "KES #{amount}"
end
