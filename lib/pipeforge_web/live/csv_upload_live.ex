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
    case uploaded_entries(socket, :csv) do
      {entries, []} when entries != [] ->
        socket = assign(socket, :uploading, true)

        result = process_upload(entries, socket)

        case result do
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

          other ->
            require Logger
            Logger.error("Unexpected result from process_upload: #{inspect(other)}")
            socket =
              socket
              |> assign(:uploading, false)
              |> assign(:upload_errors, ["Unexpected error occurred"])
              |> put_flash(:error, "Upload failed: unexpected error")

            {:noreply, socket}
        end

      {[], _errors} ->
        {:noreply, put_flash(socket, :error, "Please select a CSV file to upload")}

      {_entries, errors} when errors != [] ->
        {:noreply,
         socket
         |> assign(:upload_errors, errors)
         |> put_flash(:error, "Upload validation failed")}

      _ ->
        {:noreply, put_flash(socket, :error, "Please select a CSV file to upload")}
    end
  end

  defp process_upload([entry | _], socket) do
    require Logger

    result =
      try do
        consume_uploaded_entry(socket, entry, fn %{path: path} ->
          Logger.info("Processing upload: #{entry.client_name}")

          with {:ok, content_hash} <- hash_file(path),
               {:ok, existing_file} <- check_duplicate_or_existing(content_hash),
               {:ok, file_key} <- upload_to_storage(path, entry.client_name),
               {:ok, ingestion_file} <- get_or_update_ingestion_record(existing_file, entry, file_key, content_hash),
               :ok <- Producer.publish_file(ingestion_file.id, file_key, entry.client_name) do
            Logger.info("Successfully uploaded and queued: #{entry.client_name}")
            {:ok, ingestion_file}
          else
            {:error, {:duplicate, existing_file}} ->
              status_msg = format_status_message(existing_file)
              Logger.warning("Duplicate file detected: #{entry.client_name}")
              {:error, "File with this content has already been uploaded. #{status_msg}"}

            {:error, reason} = error ->
              Logger.error("Upload failed for #{entry.client_name}: #{inspect(reason)}")
              error

            error ->
              Logger.error("Unexpected error uploading #{entry.client_name}: #{inspect(error)}")
              {:error, "Upload failed: #{inspect(error)}"}
          end
        end)
      catch
        kind, error ->
          Logger.error("Exception during upload: #{inspect(kind)} - #{inspect(error)}")
          {:error, "Upload failed: #{inspect(error)}"}
      end

    # Ensure we always return {:ok, _} or {:error, _}
    case result do
      {:ok, _} = ok -> ok
      {:error, _} = error -> error
      other ->
        Logger.error("process_upload returned unexpected value: #{inspect(other)}")
        {:error, "Upload failed: unexpected error"}
    end
  end

  defp process_upload([], socket) do
    {:error, "No entries to process"}
  end

  defp hash_file(path) when is_binary(path) do
    case FileHasher.hash_file(path) do
      hash when is_binary(hash) -> {:ok, hash}
      {:error, reason} -> {:error, "Failed to hash file: #{inspect(reason)}"}
      other -> {:error, "Unexpected result from hash_file: #{inspect(other)}"}
    end
  end

  defp hash_file(path) do
    {:error, "Invalid path provided: #{inspect(path)}"}
  end

  defp check_duplicate_or_existing(content_hash) do
    case Repo.get_by(IngestionFile, content_hash: content_hash) do
      nil ->
        {:ok, nil}

      existing_file ->
        # Allow re-upload if previous upload failed or stuck in pending for > 5 minutes
        cond do
          existing_file.status == "failed" ->
            {:ok, existing_file}

          existing_file.status == "pending" and stale_pending?(existing_file) ->
            {:ok, existing_file}

          true ->
            {:error, {:duplicate, existing_file}}
        end
    end
  end

  defp stale_pending?(file) do
    case file.inserted_at do
      nil -> false
      inserted_at -> DateTime.diff(DateTime.utc_now(), inserted_at, :second) > 300 # 5 minutes
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

  defp get_or_update_ingestion_record(nil, entry, file_key, content_hash) do
    # Create new record
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

  defp get_or_update_ingestion_record(existing_file, entry, file_key, _content_hash) do
    # Update existing record to retry processing
    existing_file
    |> IngestionFile.changeset(%{
      filename: entry.client_name,
      file_path: file_key,
      status: "pending",
      total_rows: 0,
      processed_rows: 0,
      failed_rows: 0,
      error_message: nil,
      started_at: nil,
      completed_at: nil
    })
    |> Repo.update()
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

  defp format_status_message(file) do
    status = String.capitalize(file.status || "unknown")
    uploaded_at = format_datetime(file.inserted_at)

    case file.status do
      "completed" ->
        rows_info = if file.total_rows, do: " (#{file.processed_rows}/#{file.total_rows} rows processed)", else: ""
        "Previous upload was #{status} on #{uploaded_at}#{rows_info}."

      "processing" ->
        "Previous upload is currently #{status} (started #{uploaded_at})."

      "pending" ->
        if stale_pending?(file) do
          "Previous upload is #{status} (uploaded #{uploaded_at}) and appears stuck. You can re-upload to retry."
        else
          "Previous upload is #{status} (uploaded #{uploaded_at}). It should start processing shortly."
        end

      "failed" ->
        error_info = if file.error_message, do: " Error: #{String.slice(file.error_message, 0..100)}", else: ""
        "Previous upload #{status} on #{uploaded_at}.#{error_info}"

      _ ->
        "Previous upload status: #{status} (uploaded #{uploaded_at})."
    end
  end

  defp format_datetime(nil), do: "unknown date"
  defp format_datetime(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
  defp format_datetime(_), do: "unknown date"
end
