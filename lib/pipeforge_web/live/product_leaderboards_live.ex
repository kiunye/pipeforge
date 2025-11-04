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
      <div class="max-w-7xl mx-auto px-4 py-8">
        <div class="mb-8">
          <div class="flex justify-between items-center mb-4">
            <h1 class="text-3xl font-bold">Product Leaderboards</h1>
            <button
              phx-click="export_csv"
              class="px-4 py-2 bg-green-600 text-white rounded-lg hover:bg-green-700"
            >
              Export CSV
            </button>
          </div>

          <div class="bg-white rounded-lg shadow-md p-6 mb-6">
            <div class="flex items-center space-x-4 mb-4">
              <span class="text-sm font-medium text-gray-700">Sort by:</span>
              <button
                phx-click="sort"
                phx-value-sort_by="revenue"
                class={[
                  "px-4 py-2 rounded-lg transition-colors",
                  if(@sort_by == "revenue",
                    do: "bg-blue-600 text-white",
                    else: "bg-gray-200 text-gray-700 hover:bg-gray-300"
                  )
                ]}
              >
                Revenue
              </button>
              <button
                phx-click="sort"
                phx-value-sort_by="units"
                class={[
                  "px-4 py-2 rounded-lg transition-colors",
                  if(@sort_by == "units",
                    do: "bg-blue-600 text-white",
                    else: "bg-gray-200 text-gray-700 hover:bg-gray-300"
                  )
                ]}
              >
                Units Sold
              </button>
            </div>
          </div>

          <div class="bg-white rounded-lg shadow-md p-6">
            <div :if={@loading} class="text-center py-8">
              <p class="text-gray-500">Loading products...</p>
            </div>

            <div :if={not @loading}>
              <table class="min-w-full divide-y divide-gray-200">
                <thead class="bg-gray-50">
                  <tr>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                      Rank
                    </th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                      SKU
                    </th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                      Name
                    </th>
                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                      Category
                    </th>
                    <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                      Total Revenue
                    </th>
                    <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                      Units Sold
                    </th>
                    <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                      Orders
                    </th>
                  </tr>
                </thead>
                <tbody class="bg-white divide-y divide-gray-200">
                  <tr :for={{product, idx} <- Enum.with_index(@products, 1)} class="hover:bg-gray-50">
                    <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                      <%= (@page - 1) * @per_page + idx %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                      <%= product.sku %>
                    </td>
                    <td class="px-6 py-4 text-sm text-gray-900">
                      <%= product.name %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                      <%= product.category || "-" %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900 text-right font-medium">
                      <%= format_currency(product.total_revenue) %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900 text-right">
                      <%= product.total_units || 0 %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500 text-right">
                      <%= product.order_count || 0 %>
                    </td>
                  </tr>
                </tbody>
              </table>

              <div :if={@products == []} class="text-center py-8">
                <p class="text-gray-500">No products found.</p>
              </div>

              <div :if={@products != []} class="mt-4 flex items-center justify-between">
                <div class="text-sm text-gray-700">
                  Showing <%= (@page - 1) * @per_page + 1 %> to
                  <%= min(@page * @per_page, @total_count) %> of <%= @total_count %> products
                </div>
                <div class="flex space-x-2">
                  <a
                    :if={@page > 1}
                    href={build_leaderboard_path(%{@assigns | page: @page - 1})}
                    class="px-4 py-2 border border-gray-300 rounded-lg hover:bg-gray-50"
                  >
                    Previous
                  </a>
                  <a
                    :if={@page < @total_pages}
                    href={build_leaderboard_path(%{@assigns | page: @page + 1})}
                    class="px-4 py-2 border border-gray-300 rounded-lg hover:bg-gray-50"
                  >
                    Next
                  </a>
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
end

