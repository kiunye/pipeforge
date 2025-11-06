defmodule PipeForge.Alerts.SlackNotifier do
  @moduledoc """
  Sends alerts to Slack via webhook.
  """

  require Logger

  @doc """
  Sends a message to Slack via webhook.
  """
  def send_message(message, webhook_url \\ nil) do
    webhook_url = webhook_url || get_webhook_url()

    if webhook_url do
      payload = %{
        text: message,
        username: "PipeForge Alerts",
        icon_emoji: ":chart_with_upwards_trend:"
      }

      case Finch.build(:post, webhook_url, [], Jason.encode!(payload)) |> Finch.request(PipeForge.Finch) do
        {:ok, %{status: 200}} ->
          Logger.info("Successfully sent Slack alert")
          :ok

        {:ok, %{status: status}} ->
          Logger.error("Slack webhook returned status #{status}")
          {:error, "Slack webhook returned status #{status}"}

        {:error, reason} ->
          Logger.error("Failed to send Slack alert: #{inspect(reason)}")
          {:error, reason}
      end
    else
      Logger.warning("Slack webhook URL not configured, skipping alert")
      :ok
    end
  end

  @doc """
  Sends a formatted sales alert to Slack.
  """
  def send_sales_alert(alert_type, current_value, previous_value, date, change_percent) do
    emoji = if change_percent < 0, do: ":warning:", else: ":rocket:"
    direction = if change_percent < 0, do: "dropped", else: "spiked"

    message = """
    #{emoji} *Sales Alert: #{String.upcase(alert_type)}*
    
    Revenue #{direction} by #{abs(change_percent) |> :erlang.float_to_binary(decimals: 1)}%
    
    *Date:* #{Date.to_iso8601(date)}
    *Current:* #{format_currency(current_value)}
    *Previous:* #{format_currency(previous_value)}
    *Change:* #{format_currency(current_value - previous_value)} (#{if change_percent < 0, do: "-", else: "+"}#{abs(change_percent) |> :erlang.float_to_binary(decimals: 1)}%)
    """

    send_message(message)
  end

  @doc """
  Sends a product performance spike alert.
  """
  def send_product_spike_alert(product_name, category, current_units, previous_units, date, change_percent) do
    message = """
    :rocket: *Product Performance Spike*
    
    #{product_name} (#{category}) saw a #{change_percent |> :erlang.float_to_binary(decimals: 1)}% increase in units sold
    
    *Date:* #{Date.to_iso8601(date)}
    *Current Units:* #{current_units}
    *Previous Units:* #{previous_units}
    *Change:* +#{current_units - previous_units} units
    """

    send_message(message)
  end

  defp get_webhook_url do
    Application.get_env(:pipeforge, :slack_webhook_url) ||
      System.get_env("SLACK_WEBHOOK_URL")
  end

  defp format_currency(value) when is_decimal(value) do
    "KES #{value |> Decimal.to_float() |> :erlang.float_to_binary(decimals: 2)}"
  end

  defp format_currency(value) when is_number(value) do
    "KES #{value |> :erlang.float_to_binary(decimals: 2)}"
  end

  defp format_currency(value), do: inspect(value)
end

