defmodule PipeForgeWeb.CSVUploadLive do
  use PipeForgeWeb, :live_view

  alias PipeForge.Ingestion.{FileHasher, IngestionFile, Producer}
  alias PipeForge.{Repo, Storage}

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:uploaded_files, [])
      |> assign(:upload_errors, [])
      |> assign(:uploading, false)
      |> allow_upload(:csv,
        accept: ~w(.csv),
        max_entries: 1,
        max_file_size: 100_000_000,
        chunk_size: 64_000
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :csv, ref)}
  end

  @impl true
  def handle_event("save", _params, socket) do
    if uploaded_entries = uploaded_entries(socket, :csv) do
      socket = assign(socket, :uploading, true)

      case process_upload(uploaded_entries, socket) do
        {:ok, _ingestion_file} ->
          socket =
            socket
            |> assign(:uploading, false)
            |> put_flash(:info, "File uploaded successfully. Processing will begin shortly.")

          {:noreply, socket}

        {:error, reason} ->
          socket =
            socket
            |> assign(:uploading, false)
            |> assign(:upload_errors, [reason])
            |> put_flash(:error, "Upload failed: #{inspect(reason)}")

          {:noreply, socket}
      end
    else
      {:noreply, put_flash(socket, :error, "Please select a CSV file to upload")}
    end
  end

  defp process_upload([{entry, _}], socket) do
    consume_uploaded_entry(socket, entry, fn %{path: path} ->
      with {:ok, content_hash} <- hash_file(path),
           :ok <- check_duplicate(content_hash),
           {:ok, file_key} <- upload_to_storage(path, entry.client_name),
           {:ok, ingestion_file} <- create_ingestion_record(entry, file_key, content_hash),
           :ok <- Producer.publish_file(ingestion_file.id, file_key, entry.client_name) do
        {:ok, ingestion_file}
      else
        {:error, :duplicate} ->
          {:error, "File with this content has already been uploaded"}

        error ->
          error
      end
    end)
  end

  defp hash_file(path) do
    hash = FileHasher.hash_file(path)
    {:ok, hash}
  rescue
    e -> {:error, "Failed to hash file: #{inspect(e)}"}
  end

  defp check_duplicate(content_hash) do
    case Repo.get_by(IngestionFile, content_hash: content_hash) do
      nil -> :ok
      _ -> {:error, :duplicate}
    end
  end

  defp upload_to_storage(path, filename) do
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    key = "uploads/#{timestamp}_#{filename}"

    case Storage.upload_file(path, key) do
      {:ok, _} -> {:ok, key}
      error -> {:error, "Failed to upload to storage: #{inspect(error)}"}
    end
  end

  defp create_ingestion_record(entry, file_key, content_hash) do
    %IngestionFile{}
    |> IngestionFile.changeset(%{
      filename: entry.client_name,
      file_path: file_key,
      content_hash: content_hash,
      status: "pending",
      total_rows: 0,
      processed_rows: 0,
      failed_rows: 0
    })
    |> Repo.insert()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="max-w-4xl mx-auto px-4 py-8">
        <h1 class="text-3xl font-bold mb-8">CSV Upload</h1>

        <div class="bg-white rounded-lg shadow-md p-6 mb-6">
          <form
            id="upload-form"
            phx-submit="save"
            phx-change="validate"
            class="space-y-6"
          >
            <div
              class="border-2 border-dashed border-gray-300 rounded-lg p-8 text-center hover:border-gray-400 transition-colors"
              phx-drop-target={@uploads.csv.ref}
            >
              <.live_file_input upload={@uploads.csv} class="hidden" />
              <div class="space-y-4">
                <svg
                  class="mx-auto h-12 w-12 text-gray-400"
                  stroke="currentColor"
                  fill="none"
                  viewBox="0 0 48 48"
                >
                  <path
                    d="M28 8H12a4 4 0 00-4 4v20m32-12v8m0 0v8a4 4 0 01-4 4H12a4 4 0 01-4-4v-4m32-4l-3.172-3.172a4 4 0 00-5.656 0L28 28M8 32l9.172-9.172a4 4 0 015.656 0L28 28m0 0l4 4m4-24h8m-4-4v8m-12 4h.02"
                    stroke-width="2"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  />
                </svg>
                <div>
                  <label
                    for={@uploads.csv.ref}
                    class="cursor-pointer text-blue-600 hover:text-blue-800 font-medium"
                  >
                    Click to upload
                  </label>
                  <span class="text-gray-600"> or drag and drop</span>
                </div>
                <p class="text-sm text-gray-500">CSV files only (max 100MB)</p>
              </div>
            </div>

            <div :for={entry <- @uploads.csv.entries} class="mt-4">
              <div class="flex items-center justify-between p-4 bg-gray-50 rounded-lg">
                <div class="flex items-center space-x-4">
                  <.icon name="hero-document" class="w-8 h-8 text-gray-400" />
                  <div>
                    <p class="font-medium"><%= entry.client_name %></p>
                    <p class="text-sm text-gray-500">
                      <%= format_file_size(entry.client_size) %>
                    </p>
                  </div>
                </div>
                <div class="flex items-center space-x-2">
                  <progress
                    value={entry.progress}
                    max="100"
                    class="w-32 h-2 bg-gray-200 rounded-full"
                  >
                    <%= entry.progress %>%
                  </progress>
                  <button
                    type="button"
                    phx-click="cancel-upload"
                    phx-value-ref={entry.ref}
                    class="text-red-600 hover:text-red-800"
                  >
                    <.icon name="hero-x-mark" class="w-5 h-5" />
                  </button>
                </div>
              </div>
            </div>

            <div :if={@upload_errors != []} class="bg-red-50 border border-red-200 rounded-lg p-4">
              <ul class="list-disc list-inside text-red-800">
                <li :for={error <- @upload_errors}><%= error %></li>
              </ul>
            </div>

            <div class="flex justify-end">
              <button
                type="submit"
                disabled={@uploading || @uploads.csv.entries == []}
                class={[
                  "px-6 py-2 rounded-lg font-medium transition-colors",
                  if(@uploading || @uploads.csv.entries == [],
                    do: "bg-gray-300 text-gray-500 cursor-not-allowed",
                    else: "bg-blue-600 text-white hover:bg-blue-700"
                  )
                ]}
              >
                <%= if @uploading, do: "Uploading...", else: "Upload CSV" %>
              </button>
            </div>
          </form>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp format_file_size(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_file_size(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_file_size(bytes) when bytes < 1_073_741_824, do: "#{Float.round(bytes / 1_048_576, 1)} MB"
  defp format_file_size(bytes), do: "#{Float.round(bytes / 1_073_741_824, 1)} GB"
end
