defmodule PipeForge.Ingestion.Pipeline do
  @moduledoc """
  Broadway pipeline for processing CSV ingestion files from RabbitMQ.
  """

  use Broadway

  alias Broadway.Message
  alias PipeForge.Ingestion.{CSVValidator, FailedRecord, IngestionFile, SalesInserter}
  alias PipeForge.{Repo, Storage}

  def start_link(_opts) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module:
          {BroadwayRabbitMQ.Producer,
           [
             queue: "csv_ingestion",
             connection: rabbitmq_connection_options(),
             declare: [durable: true],
             on_failure: :reject
           ]},
        concurrency: 1
      ],
      processors: [
        default: [concurrency: 10]
      ],
      batchers: [
        default: [batch_size: 50, batch_timeout: 1000]
      ]
    )
  end

  @impl true
  def handle_message(_processor, %Message{data: data} = message, _context) do
    require Logger

    case Jason.decode(data) do
      {:ok, %{"file_id" => file_id_string, "file_path" => file_path, "filename" => filename}} ->
        # Convert UUID string back to binary for Ecto
        case Ecto.UUID.cast(file_id_string) do
          {:ok, file_id} ->
            Logger.info("Processing ingestion file: #{filename} (#{file_id_string})")

            case process_file(file_id, file_path, filename) do
              {:ok, _result} ->
                Logger.info("Successfully processed file: #{filename}")
                message

              {:error, reason} ->
                Logger.error("Failed to process file #{filename}: #{inspect(reason)}")
                # Mark as failed and don't requeue
                Message.failed(message, reason)
            end

          :error ->
            Logger.error("Invalid file_id format: #{file_id_string}")
            Message.failed(message, "Invalid file_id format: #{file_id_string}")
        end

      {:ok, _} ->
        Logger.error("Invalid message format")
        Message.failed(message, "Invalid message format")

      {:error, reason} ->
        Logger.error("Failed to decode JSON: #{inspect(reason)}")
        Message.failed(message, "Failed to decode JSON: #{inspect(reason)}")
    end
  end

  @impl true
  def handle_batch(_batcher, messages, _batch_info, _context) do
    Enum.each(messages, &process_batch_message/1)
    messages
  end

  defp process_batch_message(%{status: :ok}), do: :ok

  defp process_batch_message(%{status: {:failed, reason}, data: %{file_id: file_id}}) do
    update_ingestion_file_status(file_id, "failed", inspect(reason))
  end

  defp process_batch_message(_), do: :ok

  defp process_file(file_id, file_path, _filename) do
    require Logger

    with {:ok, ingestion_file} <- get_ingestion_file(file_id),
         {:ok, temp_path} <- Storage.download_file(file_path) do
      # Verify downloaded file has content
      case File.read(temp_path) do
        {:ok, content} ->
          Logger.info("Downloaded file size: #{byte_size(content)} bytes")
          preview = String.slice(content, 0..500)
          Logger.info("First 500 bytes of downloaded file: #{inspect(preview)}")

          # Check if file starts with header
          if String.starts_with?(content, "order_ref") or String.starts_with?(content, "order_ref,order_date") do
            Logger.info("File appears to have header row")
            process_file_with_path(file_id, temp_path, ingestion_file)
          else
            Logger.error("Downloaded file does not start with expected header. First 100 chars: #{String.slice(content, 0..100)}")
            File.rm(temp_path)
            update_ingestion_file_status(file_id, "failed", "Downloaded file is missing header row")
            {:error, "Downloaded file is missing header row"}
          end

        {:error, reason} ->
          Logger.error("Failed to read downloaded file: #{inspect(reason)}")
          File.rm(temp_path)
          update_ingestion_file_status(file_id, "failed", "Failed to read downloaded file: #{inspect(reason)}")
          {:error, "Failed to read downloaded file: #{inspect(reason)}"}
      end
    else
      {:error, reason} ->
        update_ingestion_file_status(file_id, "failed", inspect(reason))
        {:error, reason}
    end
  end

  defp process_file_with_path(file_id, temp_path, ingestion_file) do
    with {:ok, rows} <- parse_csv(temp_path),
         {:ok, {valid_rows, invalid_rows}} <- validate_rows(rows),
         :ok <- update_ingestion_file_started(file_id),
         {:ok, processed_count} <- insert_records({valid_rows, invalid_rows}, ingestion_file) do
      total_rows = length(rows) - 1 # Subtract header row
      failed_count = length(invalid_rows)

      File.rm(temp_path)
      update_ingestion_file_completed(file_id, total_rows, processed_count, failed_count)
      {:ok, file_id}
    else
      {:error, reason} ->
        File.rm(temp_path)
        update_ingestion_file_status(file_id, "failed", inspect(reason))
        {:error, reason}
    end
  rescue
    e ->
      File.rm(temp_path)
      update_ingestion_file_status(file_id, "failed", inspect(e))
      {:error, e}
  end

  defp persist_failed_records(invalid_rows, ingestion_file_id) when is_list(invalid_rows) do
    Enum.each(invalid_rows, fn {row_number, raw_row, errors} ->
      %FailedRecord{}
      |> FailedRecord.changeset(%{
        ingestion_file_id: ingestion_file_id,
        row_number: row_number,
        raw_data: Enum.with_index(raw_row) |> Enum.into(%{}),
        error_reasons: List.wrap(errors),
        retry_count: 0,
        status: "pending"
      })
      |> Repo.insert()
      |> case do
        {:ok, _} -> :ok
        {:error, _changeset} -> :ok
      end
    end)
  end

  defp persist_failed_records(_, _), do: :ok

  defp get_ingestion_file(file_id) do
    case Repo.get(IngestionFile, file_id) do
      nil -> {:error, "Ingestion file not found"}
      file -> {:ok, file}
    end
  end

  defp parse_csv(file_path) do
    require Logger

    case File.read(file_path) do
      {:ok, content} ->
        if byte_size(content) == 0 do
          Logger.error("CSV file is empty: #{file_path}")
          {:error, "CSV file is empty"}
        else
          # Remove BOM if present (UTF-8 BOM is EF BB BF)
          content = remove_bom(content)

          # Log first 200 bytes for debugging
          preview = String.slice(content, 0..200)
          Logger.info("CSV file preview (first 200 bytes): #{inspect(preview)}")

          rows = NimbleCSV.RFC4180.parse_string(content)
          Logger.info("Parsed CSV: #{length(rows)} rows found (including header)")

          if Enum.empty?(rows) do
            Logger.error("CSV parsing resulted in empty rows")
            {:error, "CSV file appears to be empty or invalid"}
          else
            header_row = Enum.at(rows, 0)
            Logger.info("First row (header): #{inspect(header_row)}")
            Logger.info("Header row length: #{length(header_row)}")
            {:ok, rows}
          end
        end

      {:error, reason} ->
        Logger.error("Failed to read CSV file: #{inspect(reason)}")
        {:error, "Failed to read file: #{inspect(reason)}"}
    end
  end

  defp remove_bom(<<0xEF, 0xBB, 0xBF, rest::binary>>), do: rest
  defp remove_bom(content), do: content

  defp validate_rows([]) do
    require Logger
    Logger.error("CSV file has no rows")
    {:error, "CSV file has no rows"}
  end

  defp validate_rows([header | rows]) do
    require Logger
    Logger.info("Validating header: #{inspect(header)}")

    case CSVValidator.validate_header(header) do
      {:ok, header_map} ->
        Logger.info("Header validation passed. Found columns: #{inspect(Map.keys(header_map))}")
        validated = validate_rows_with_header(rows, header_map)
        {:ok, validated}

      {:error, :missing_columns, missing} ->
        Logger.error("Missing required columns: #{inspect(missing)}. Header was: #{inspect(header)}")
        {:error, "Missing required columns: #{inspect(missing)}"}
    end
  end

  defp validate_rows_with_header(rows, header_map) do
    rows
    |> Enum.with_index(1)
    |> Enum.reduce({[], []}, fn {row, idx}, {valid, invalid} ->
      validate_single_row(row, idx, header_map, valid, invalid)
    end)
  end

  defp validate_single_row(row, idx, header_map, valid, invalid) do
    case CSVValidator.validate_row(row, header_map) do
      {:ok, mapped} -> {[mapped | valid], invalid}
      {:error, errors} -> {valid, [{idx, row, errors} | invalid]}
    end
  end

  defp insert_records({valid_rows, invalid_rows}, ingestion_file) do
    # Persist failed records
    persist_failed_records(invalid_rows, ingestion_file.id)

    # Insert valid records
    case SalesInserter.insert_records(valid_rows, ingestion_file) do
      {:ok, count} -> {:ok, count}
      {:error, reason} -> {:error, "Failed to insert records: #{inspect(reason)}"}
    end
  end

  defp update_ingestion_file_status(file_id, status, error_message) do
    case Repo.get(IngestionFile, file_id) do
      nil ->
        :ok

      file ->
        changeset =
          IngestionFile.changeset(file, %{
            status: status,
            error_message: error_message,
            started_at: if(status == "processing", do: DateTime.utc_now(), else: file.started_at),
            completed_at: if(status in ["completed", "failed"], do: DateTime.utc_now(), else: file.completed_at)
          })

        case Repo.update(changeset) do
          {:ok, _} -> :ok
          {:error, _} -> :ok
        end
    end
  end

  defp update_ingestion_file_started(file_id) do
    case Repo.get(IngestionFile, file_id) do
      nil ->
        :ok

      file ->
        changeset =
          IngestionFile.changeset(file, %{
            status: "processing",
            started_at: DateTime.utc_now()
          })

        case Repo.update(changeset) do
          {:ok, _} -> :ok
          {:error, _} -> :ok
        end
    end
  end

  defp update_ingestion_file_completed(file_id, total_rows, processed_rows, failed_rows) do
    case Repo.get(IngestionFile, file_id) do
      nil ->
        :ok

      file ->
        changeset =
          IngestionFile.changeset(file, %{
            status: "completed",
            total_rows: total_rows,
            processed_rows: processed_rows,
            failed_rows: failed_rows,
            completed_at: DateTime.utc_now()
          })

        case Repo.update(changeset) do
          {:ok, _} -> :ok
          {:error, _} -> :ok
        end
    end
  end

  defp rabbitmq_connection_options do
    [
      host: System.get_env("RABBITMQ_HOST") || "localhost",
      port: String.to_integer(System.get_env("RABBITMQ_PORT") || "5672"),
      username: System.get_env("RABBITMQ_USER") || "guest",
      password: System.get_env("RABBITMQ_PASSWORD") || "guest",
      virtual_host: System.get_env("RABBITMQ_VHOST") || "/"
    ]
  end
end
