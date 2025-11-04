defmodule PipeForge.Ingestion.Producer do
  @moduledoc """
  Publishes ingestion file messages to RabbitMQ for processing.
  """

  alias AMQP.Connection
  alias AMQP.Channel
  alias AMQP.Queue
  alias AMQP.Basic

  @exchange "pipeforge.ingestion"
  @queue "csv_ingestion"
  @routing_key "csv.file"

  @doc """
  Publishes a message to RabbitMQ when a CSV file is ready for processing.
  """
  def publish_file(file_id, file_path, filename) do
    with {:ok, conn} <- get_connection(),
         {:ok, chan} <- Channel.open(conn),
         :ok <- setup_exchange_and_queue(chan),
         :ok <- publish_message(chan, file_id, file_path, filename) do
      Channel.close(chan)
      Connection.close(conn)
      :ok
    else
      error ->
        {:error, error}
    end
  end

  defp get_connection do
    case Application.get_env(:pipeforge, :rabbitmq_connection) do
      nil ->
        # Use default RabbitMQ connection from environment
        Connection.open(
          host: System.get_env("RABBITMQ_HOST") || "localhost",
          port: String.to_integer(System.get_env("RABBITMQ_PORT") || "5672"),
          username: System.get_env("RABBITMQ_USER") || "guest",
          password: System.get_env("RABBITMQ_PASSWORD") || "guest",
          virtual_host: System.get_env("RABBITMQ_VHOST") || "/"
        )

      conn ->
        {:ok, conn}
    end
  end

  defp setup_exchange_and_queue(chan) do
    :ok = AMQP.Exchange.declare(chan, @exchange, :direct, durable: true)
    {:ok, _} = Queue.declare(chan, @queue, durable: true)
    :ok = Queue.bind(chan, @queue, @exchange, routing_key: @routing_key)
  end

  defp publish_message(chan, file_id, file_path, filename) do
    message = Jason.encode!(%{file_id: file_id, file_path: file_path, filename: filename})

    Basic.publish(chan, @exchange, @routing_key, message,
      persistent: true,
      content_type: "application/json"
    )
  end
end

