defmodule PipeForge.Ingestion.Pipeline do
  @moduledoc """
  Broadway pipeline for processing CSV ingestion files from RabbitMQ.
  """

  use Broadway

  alias Broadway.Message
  alias PipeForge.{Repo, Storage}
  alias PipeForge.Ingestion.{CSVValidator, IngestionFile}

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
             on_failure: :reject_and_requeue
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
    case Jason.decode(data) do
      {:ok, %{"file_id" => file_id, "file_path" => file_path, "filename" => filename}} ->
        case process_file(file_id, file_path, filename) do
          {:ok, _result} ->
            message

          {:error, reason} ->
            Message.failed(message, reason)
        end

      {:ok, _} ->
        Message.failed(message, "Invalid message format")

      {:error, _} ->
        Message.failed(message, "Failed to decode JSON")
    end
  end

  @impl true
  def handle_batch(_batcher, messages, _batch_info, _context) do
    Enum.each(messages, fn message ->
      case message.status do
        :ok ->
          # File processed successfully
          :ok

        {:failed, reason} ->
          # Update ingestion file status to failed
          if file_id = message.data[:file_id] do
            update_ingestion_file_status(file_id, "failed", inspect(reason))
          end
      end
    end)

    messages
  end

  defp process_file(file_id, file_path, _filename) do
    with {:ok, ingestion_file} <- get_ingestion_file(file_id),
         {:ok, temp_path} <- Storage.download_file(file_path) do
      process_file_with_path(file_id, temp_path, ingestion_file)
    else
      {:error, reason} ->
        update_ingestion_file_status(file_id, "failed", inspect(reason))
        {:error, reason}
    end
  end

  defp process_file_with_path(file_id, temp_path, ingestion_file) do
    try do
      with {:ok, rows} <- parse_csv(temp_path),
           {:ok, validated_rows} <- validate_rows(rows),
           :ok <- update_ingestion_file_status(file_id, "processing", nil),
           {:ok, _} <- insert_records(validated_rows, ingestion_file) do
        File.rm(temp_path)
        update_ingestion_file_status(file_id, "completed", nil)
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
  end

  defp get_ingestion_file(file_id) do
    case Repo.get(IngestionFile, file_id) do
      nil -> {:error, "Ingestion file not found"}
      file -> {:ok, file}
    end
  end

  defp parse_csv(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        rows = NimbleCSV.RFC4180.parse(content)
        {:ok, rows}

      {:error, reason} ->
        {:error, "Failed to read file: #{inspect(reason)}"}
    end
  end

  defp validate_rows([]), do: {:ok, []}

  defp validate_rows([header | rows]) do
    case CSVValidator.validate_header(header) do
      {:ok, header_map} ->
        validated =
          rows
          |> Enum.with_index(1)
          |> Enum.reduce({[], []}, fn {row, idx}, {valid, invalid} ->
            case CSVValidator.validate_row(row, header_map) do
              {:ok, mapped} -> {[mapped | valid], invalid}
              {:error, errors} -> {valid, [{idx, errors} | invalid]}
            end
          end)

        {:ok, validated}

      {:error, :missing_columns, missing} ->
        {:error, "Missing required columns: #{inspect(missing)}"}
    end
  end

  defp insert_records({valid_rows, _invalid_rows}, _ingestion_file) do
    # TODO: Insert records into database
    # This will be implemented in the next step
    {:ok, length(valid_rows)}
  end

  defp update_ingestion_file_status(file_id, status, error_message) do
    case Repo.get(IngestionFile, file_id) do
      nil ->
        :ok

      file ->
        file
        |> IngestionFile.changeset(%{
          status: status,
          error_message: error_message,
          started_at: if(status == "processing", do: DateTime.utc_now(), else: file.started_at),
          completed_at: if(status in ["completed", "failed"], do: DateTime.utc_now(), else: file.completed_at)
        })
        |> Repo.update()
        |> case do
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

