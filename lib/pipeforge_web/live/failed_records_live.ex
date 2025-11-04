defmodule PipeForgeWeb.FailedRecordsLive do
  use PipeForgeWeb, :live_view

  import Ecto.Query

  alias PipeForge.{Ingestion, Repo}
  alias PipeForge.Ingestion.{FailedRecord, IngestionFile, Producer}

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:failed_records, [])
      |> assign(:loading, false)
      |> assign(:filters, %{status: "all", ingestion_file_id: nil})
      |> assign(:page, 1)
      |> assign(:per_page, 25)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = %{
      status: params["status"] || "all",
      ingestion_file_id: params["file_id"]
    }

    socket =
      socket
      |> assign(:filters, filters)
      |> assign(:page, String.to_integer(params["page"] || "1"))
      |> load_failed_records()

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter", %{"status" => status}, socket) do
    socket =
      socket
      |> assign(:filters, Map.put(socket.assigns.filters, :status, status))
      |> assign(:page, 1)
      |> load_failed_records()

    {:noreply, push_patch(socket, to: ~p"/ingestion/failures?#{build_query_params(socket.assigns)}")}
  end

  @impl true
  def handle_event("replay", %{"id" => id}, socket) do
    case Repo.get(FailedRecord, id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Failed record not found")}

      failed_record ->
        case replay_failed_record(failed_record) do
          :ok ->
            socket =
              socket
              |> put_flash(:info, "Failed record queued for retry")
              |> load_failed_records()

            {:noreply, socket}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to replay: #{inspect(reason)}")}
        end
    end
  end

  @impl true
  def handle_event("replay_selected", %{"selected" => selected_ids}, socket) do
    ids = String.split(selected_ids, ",") |> Enum.map(&String.to_integer/1)

    results =
      ids
      |> Enum.map(fn id ->
        case Repo.get(FailedRecord, id) do
          nil -> {:error, :not_found}
          record -> replay_failed_record(record)
        end
      end)

    success_count = Enum.count(results, &(&1 == :ok))
    total_count = length(results)

    socket =
      socket
      |> put_flash(
        :info,
        "Queued #{success_count} of #{total_count} failed records for retry"
      )
      |> load_failed_records()

    {:noreply, socket}
  end

  defp load_failed_records(socket) do
    filters = socket.assigns.filters
    page = socket.assigns.page
    per_page = socket.assigns.per_page

    query = build_query(filters)

    total_count = Repo.aggregate(query, :count)
    entries = paginated_entries(query, page, per_page)
    preloaded_entries = preload_ingestion_files(entries)

    failed_records = %{
      entries: preloaded_entries,
      page_number: page,
      page_size: per_page,
      total_pages: div(total_count + per_page - 1, per_page),
      total_entries: total_count
    }

    assign(socket, :failed_records, failed_records)
  end

  defp build_query(filters) do
    FailedRecord
    |> maybe_filter_by_status(filters.status)
    |> maybe_filter_by_file(filters.ingestion_file_id)
    |> order_by([fr], desc: fr.inserted_at)
  end

  defp maybe_filter_by_status(query, "all"), do: query
  defp maybe_filter_by_status(query, status), do: where(query, [fr], fr.status == ^status)

  defp maybe_filter_by_file(query, nil), do: query
  defp maybe_filter_by_file(query, file_id), do: where(query, [fr], fr.ingestion_file_id == ^file_id)

  defp paginated_entries(query, page, per_page) do
    offset = (page - 1) * per_page

    query
    |> limit(^per_page)
    |> offset(^offset)
    |> Repo.all()
  end

  defp preload_ingestion_files(records) do
    records
    |> Repo.preload(:ingestion_file)
  end

  defp replay_failed_record(%FailedRecord{ingestion_file: %IngestionFile{} = ingestion_file} = failed_record) do
    # Update failed record status
    failed_record
    |> FailedRecord.changeset(%{
      status: "retrying",
      retry_count: failed_record.retry_count + 1,
      last_retried_at: DateTime.utc_now()
    })
    |> Repo.update()
    |> case do
      {:ok, _} ->
        # Republish the file for processing
        Producer.publish_file(ingestion_file.id, ingestion_file.file_path, ingestion_file.filename)

      error ->
        error
    end
  end

  defp replay_failed_record(_), do: {:error, :ingestion_file_not_found}

  defp build_query_params(assigns) do
    filters = assigns.filters
    params = []

    params =
      if filters.status != "all" do
        [{"status", filters.status} | params]
      else
        params
      end

    params =
      if filters.ingestion_file_id do
        [{"file_id", filters.ingestion_file_id} | params]
      else
        params
      end

    params =
      if assigns.page > 1 do
        [{"page", assigns.page} | params]
      else
        params
      end

    URI.encode_query(params)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="max-w-7xl mx-auto px-4 py-8">
        <div class="flex justify-between items-center mb-8">
          <h1 class="text-3xl font-bold">Failed Records</h1>
        </div>

        <div class="bg-white rounded-lg shadow-md p-6 mb-6">
          <div class="flex items-center space-x-4 mb-6">
            <select
              id="status-filter"
              phx-change="filter"
              class="px-4 py-2 border border-gray-300 rounded-lg"
            >
              <option value="all" selected={@filters.status == "all"}>All Status</option>
              <option value="pending" selected={@filters.status == "pending"}>Pending</option>
              <option value="retrying" selected={@filters.status == "retrying"}>Retrying</option>
              <option value="succeeded" selected={@filters.status == "succeeded"}>Succeeded</option>
              <option value="failed" selected={@filters.status == "failed"}>Failed</option>
            </select>
          </div>

          <div class="overflow-x-auto">
            <table class="min-w-full divide-y divide-gray-200">
              <thead class="bg-gray-50">
                <tr>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    <input type="checkbox" id="select-all" />
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    File
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Row
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Errors
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Retries
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Status
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Actions
                  </th>
                </tr>
              </thead>
              <tbody class="bg-white divide-y divide-gray-200">
                <tr :for={record <- @failed_records.entries} class="hover:bg-gray-50">
                  <td class="px-6 py-4 whitespace-nowrap">
                    <input type="checkbox" value={record.id} class="record-checkbox" />
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap">
                    <div class="text-sm text-gray-900">
                      <%= record.ingestion_file.filename %>
                    </div>
                    <div class="text-sm text-gray-500">
                      <%= Calendar.strftime(record.inserted_at, "%Y-%m-%d %H:%M") %>
                    </div>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    <%= record.row_number %>
                  </td>
                  <td class="px-6 py-4">
                    <div class="text-sm text-gray-900">
                      <ul class="list-disc list-inside">
                        <li :for={error <- record.error_reasons}><%= error %></li>
                      </ul>
                    </div>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    <%= record.retry_count %>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap">
                    <span
                      class={[
                        "px-2 inline-flex text-xs leading-5 font-semibold rounded-full",
                        status_color(record.status)
                      ]}
                    >
                      <%= String.capitalize(record.status) %>
                    </span>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm font-medium">
                    <button
                      phx-click="replay"
                      phx-value-id={record.id}
                      class="text-blue-600 hover:text-blue-900"
                    >
                      Replay
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <div class="mt-4 flex justify-between items-center">
            <button
              phx-click="replay_selected"
              phx-value-selected=""
              id="replay-selected-btn"
              class="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 disabled:bg-gray-300 disabled:cursor-not-allowed"
              disabled
            >
              Replay Selected
            </button>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp status_color("pending"), do: "bg-yellow-100 text-yellow-800"
  defp status_color("retrying"), do: "bg-blue-100 text-blue-800"
  defp status_color("succeeded"), do: "bg-green-100 text-green-800"
  defp status_color("failed"), do: "bg-red-100 text-red-800"
  defp status_color(_), do: "bg-gray-100 text-gray-800"
end

