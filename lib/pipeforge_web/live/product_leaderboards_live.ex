defmodule PipeForgeWeb.ProductLeaderboardsLive do
  use PipeForgeWeb, :live_view

  alias PipeForge.Analytics.ProductQueries

  @per_page 25

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:products, [])
      |> assign(:sort_by, "revenue")
      |> assign(:page, 1)
      |> assign(:per_page, @per_page)
      |> assign(:total_count, 0)
      |> assign(:loading, false)
      |> assign(:filters, %{category: nil, payment_method: nil})
      |> load_products()

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    sort_by = params["sort_by"] || socket.assigns.sort_by
    page = String.to_integer(params["page"] || "1")

    filters = %{
      category: params["category"],
      payment_method: params["payment_method"]
    }

    socket =
      socket
      |> assign(:sort_by, sort_by)
      |> assign(:page, page)
      |> assign(:filters, filters)
      |> load_products()

    {:noreply, socket}
  end

  @impl true
  def handle_event("sort", %{"sort_by" => sort_by}, socket) do
    socket =
      socket
      |> assign(:sort_by, sort_by)
      |> assign(:page, 1)
      |> load_products()

    {:noreply, push_patch(socket, to: build_leaderboard_path(socket.assigns))}
  end

  @impl true
  def handle_event("export_csv", _params, socket) do
    products = get_all_products_for_export(socket.assigns)
    csv_content = generate_csv(products)

    {:noreply,
     socket
     |> put_flash(:info, "CSV export ready")
     |> push_event("download_csv", %{content: csv_content, filename: "product_leaderboard.csv"})}
  end

  @impl true
  def handle_event("apply_filter", %{"filter" => filter, "value" => value}, socket) do
    filters = Map.put(socket.assigns.filters, String.to_atom(filter), value)

    socket =
      socket
      |> assign(:filters, filters)
      |> assign(:page, 1)
      |> load_products()

    {:noreply, push_patch(socket, to: build_leaderboard_path(socket.assigns))}
  end

  defp load_products(socket) do
    sort_by = socket.assigns.sort_by
    page = socket.assigns.page
    filters = socket.assigns.filters
    offset = (page - 1) * @per_page

    socket = assign(socket, :loading, true)

    products =
      case sort_by do
        "revenue" -> ProductQueries.top_products_by_revenue(@per_page, offset, filters)
        "units" -> ProductQueries.top_products_by_units(@per_page, offset, filters)
        _ -> ProductQueries.top_products_by_revenue(@per_page, offset, filters)
      end

    total_count = ProductQueries.total_product_count(filters)

    socket
    |> assign(:products, products)
    |> assign(:total_count, total_count)
    |> assign(:total_pages, div(total_count + @per_page - 1, @per_page))
    |> assign(:loading, false)
  end

  defp get_all_products_for_export(assigns) do
    filters = assigns.filters

    case assigns.sort_by do
      "revenue" -> ProductQueries.top_products_by_revenue(1000, 0, filters)
      "units" -> ProductQueries.top_products_by_units(1000, 0, filters)
      _ -> ProductQueries.top_products_by_revenue(1000, 0, filters)
    end
  end

  defp generate_csv(products) do
    headers = ["SKU", "Name", "Category", "Total Revenue", "Total Units", "Order Count"]

    rows =
      Enum.map(products, fn p ->
        [
          p.sku,
          p.name,
          p.category || "",
          format_decimal(p.total_revenue),
          Integer.to_string(p.total_units || 0),
          Integer.to_string(p.order_count || 0)
        ]
      end)

    ([headers] ++ rows)
    |> Enum.map(&Enum.join(&1, ","))
    |> Enum.join("\n")
  end

  defp format_decimal(%Decimal{} = value) do
    value
    |> Decimal.to_float()
    |> :erlang.float_to_binary(decimals: 2)
  end

  defp format_decimal(value), do: to_string(value || 0)

  defp build_leaderboard_path(assigns) do
    params = [
      {"sort_by", assigns.sort_by},
      {"page", assigns.page}
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

    ~p"/dashboard/leaderboards?#{URI.encode_query(params)}"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="download-csv-hook" phx-hook="DownloadCSV">
      <Layouts.app flash={@flash}>
      <div class="min-h-screen bg-gray-50">
        <div class="w-full px-4 sm:px-6 lg:px-8 py-6">
          <!-- Header Section -->
          <div class="mb-6">
            <div class="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4 mb-6">
              <div>
                <h1 class="text-3xl font-bold text-gray-900 mb-1">Product Leaderboards</h1>
                <p class="text-gray-600 text-sm">Top performing products ranked by revenue and sales</p>
              </div>
              <button
                phx-click="export_csv"
                class="px-4 py-2 bg-gray-900 text-white font-medium rounded-lg hover:bg-gray-800 transition-colors flex items-center gap-2"
              >
                <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 10v6m0 0l-3-3m3 3l3-3m2 8H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"></path>
                </svg>
                Export CSV
              </button>
            </div>

            <!-- Sort Controls Card -->
            <div class="bg-white rounded-lg shadow-sm border border-gray-200 p-4 mb-6">
              <div class="flex flex-wrap items-center gap-4">
                <span class="text-sm font-medium text-gray-700">Sort by:</span>
                <div class="flex gap-2">
                  <button
                    phx-click="sort"
                    phx-value-sort_by="revenue"
                    class={[
                      "px-4 py-2 rounded-lg font-medium transition-colors",
                      if(@sort_by == "revenue",
                        do: "bg-gray-900 text-white",
                        else: "bg-gray-100 text-gray-700 hover:bg-gray-200"
                      )
                    ]}
                  >
                    Revenue
                  </button>
                  <button
                    phx-click="sort"
                    phx-value-sort_by="units"
                    class={[
                      "px-4 py-2 rounded-lg font-medium transition-colors",
                      if(@sort_by == "units",
                        do: "bg-gray-900 text-white",
                        else: "bg-gray-100 text-gray-700 hover:bg-gray-200"
                      )
                    ]}
                  >
                    Units Sold
                  </button>
                </div>
              </div>
            </div>

            <!-- Main Table Card -->
            <div class="bg-white rounded-lg shadow-sm border border-gray-200 overflow-hidden">
              <div :if={@loading} class="text-center py-16">
                <div class="inline-block animate-spin rounded-full h-10 w-10 border-4 border-gray-300 border-t-gray-900"></div>
                <p class="mt-4 text-gray-600">Loading products...</p>
              </div>

              <div :if={not @loading}>
                <div class="overflow-x-auto">
                  <table class="min-w-full divide-y divide-gray-200">
                    <thead class="bg-gray-50">
                      <tr>
                        <th class="px-6 py-3 text-left text-xs font-semibold text-gray-700 uppercase tracking-wider">Rank</th>
                        <th class="px-6 py-3 text-left text-xs font-semibold text-gray-700 uppercase tracking-wider">SKU</th>
                        <th class="px-6 py-3 text-left text-xs font-semibold text-gray-700 uppercase tracking-wider">Name</th>
                        <th class="px-6 py-3 text-left text-xs font-semibold text-gray-700 uppercase tracking-wider">Category</th>
                        <th class="px-6 py-3 text-right text-xs font-semibold text-gray-700 uppercase tracking-wider">Total Revenue</th>
                        <th class="px-6 py-3 text-right text-xs font-semibold text-gray-700 uppercase tracking-wider">Units Sold</th>
                        <th class="px-6 py-3 text-right text-xs font-semibold text-gray-700 uppercase tracking-wider">Orders</th>
                      </tr>
                    </thead>
                    <tbody class="bg-white divide-y divide-gray-200">
                      <tr
                        :for={{product, idx} <- Enum.with_index(@products, 1)}
                        class="hover:bg-gray-50 transition-colors"
                      >
                        <td class="px-6 py-4 whitespace-nowrap">
                          <div class="flex items-center gap-2">
                            <span class={[
                              "text-sm font-semibold",
                              if(idx <= 3, do: "text-gray-900", else: "text-gray-700")
                            ]}>
                              <%= (@page - 1) * @per_page + idx %>
                            </span>
                          </div>
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap">
                          <span class="text-sm font-mono text-gray-600 bg-gray-100 px-2 py-1 rounded">
                            <%= product.sku %>
                          </span>
                        </td>
                        <td class="px-6 py-4">
                          <div class="text-sm font-medium text-gray-900">
                            <%= product.name %>
                          </div>
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap">
                          <span class={[
                            "inline-flex items-center px-2.5 py-1 rounded text-xs font-medium",
                            category_badge_class(product.category)
                          ]}>
                            <%= product.category || "-" %>
                          </span>
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap text-right">
                          <div class="text-sm font-semibold text-gray-900">
                            <%= format_currency(product.total_revenue) %>
                          </div>
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap text-right">
                          <span class="text-sm font-medium text-gray-900">
                            <%= format_number(product.total_units || 0) %>
                          </span>
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap text-right">
                          <span class="text-sm text-gray-700">
                            <%= product.order_count || 0 %>
                          </span>
                        </td>
                      </tr>
                    </tbody>
                  </table>
                </div>

                <div :if={@products == []} class="text-center py-16">
                  <p class="text-gray-500">No products found.</p>
                </div>

                <!-- Pagination -->
                <div :if={@products != []} class="bg-gray-50 px-6 py-4 border-t border-gray-200">
                  <div class="flex flex-col sm:flex-row items-center justify-between gap-4">
                    <div class="text-sm text-gray-700">
                      Showing <span class="font-medium"><%= (@page - 1) * @per_page + 1 %></span> to
                      <span class="font-medium"><%= min(@page * @per_page, @total_count) %></span> of
                      <span class="font-medium"><%= @total_count %></span> products
                    </div>
                    <div class="flex gap-2">
                      <a
                        :if={@page > 1}
                        href={build_leaderboard_path(%{@assigns | page: @page - 1})}
                        class="px-4 py-2 bg-white border border-gray-300 text-gray-700 font-medium rounded-lg hover:bg-gray-50 transition-colors"
                      >
                        Previous
                      </a>
                      <a
                        :if={@page < @total_pages}
                        href={build_leaderboard_path(%{@assigns | page: @page + 1})}
                        class="px-4 py-2 bg-gray-900 text-white font-medium rounded-lg hover:bg-gray-800 transition-colors"
                      >
                        Next
                      </a>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
      </Layouts.app>
    </div>
    """
  end

  defp category_badge_class("Electronics"), do: "bg-blue-100 text-blue-800"
  defp category_badge_class("Home & Kitchen"), do: "bg-orange-100 text-orange-800"
  defp category_badge_class("Clothing"), do: "bg-pink-100 text-pink-800"
  defp category_badge_class("Books"), do: "bg-purple-100 text-purple-800"
  defp category_badge_class(_), do: "bg-gray-100 text-gray-800"

  defp format_currency(%Decimal{} = amount) do
    amount
    |> Decimal.to_float()
    |> Float.round(2)
    |> :erlang.float_to_binary(decimals: 2)
    |> then(&"$#{&1}")
  end

  defp format_currency(amount) when is_number(amount) do
    "$#{:erlang.float_to_binary(amount / 1.0, decimals: 2)}"
  end

  defp format_currency(amount), do: "$#{amount || "0.00"}"

  defp format_number(number) when is_integer(number) do
    number
    |> Integer.to_string()
    |> String.replace(~r/(\d)(?=(\d{3})+(?!\d))/, "\\1,")
  end

  defp format_number(number), do: to_string(number || 0)
end
