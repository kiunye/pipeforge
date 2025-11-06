defmodule PipeForge.Alerts.EmailNotifier do
  @moduledoc """
  Sends alerts via email using Swoosh.
  """

  require Logger
  use Swoosh.Mailer, otp_app: :pipeforge

  alias Swoosh.Email

  @doc """
  Sends a sales alert email.
  """
  def send_sales_alert(alert_type, current_value, previous_value, date, change_percent, recipients \\ nil) do
    recipients = recipients || get_alert_recipients()

    if recipients && length(recipients) > 0 do
      direction = if change_percent < 0, do: "dropped", else: "spiked"
      subject = "Sales Alert: #{String.upcase(alert_type)} - Revenue #{direction} by #{abs(change_percent) |> :erlang.float_to_binary(decimals: 1)}%"

      email =
        Email.new()
        |> Email.to(recipients)
        |> Email.from({"PipeForge Alerts", get_from_email()})
        |> Email.subject(subject)
        |> Email.html_body(build_html_body(alert_type, current_value, previous_value, date, change_percent))
        |> Email.text_body(build_text_body(alert_type, current_value, previous_value, date, change_percent))

      case deliver(email) do
        {:ok, _} ->
          Logger.info("Successfully sent sales alert email to #{length(recipients)} recipients")
          :ok

        {:error, reason} ->
          Logger.error("Failed to send sales alert email: #{inspect(reason)}")
          {:error, reason}
      end
    else
      Logger.warning("No email recipients configured, skipping email alert")
      :ok
    end
  end

  @doc """
  Sends a product performance spike alert email.
  """
  def send_product_spike_alert(product_name, category, current_units, previous_units, date, change_percent, recipients \\ nil) do
    recipients = recipients || get_alert_recipients()

    if recipients && length(recipients) > 0 do
      subject = "Product Performance Spike: #{product_name} - #{change_percent |> :erlang.float_to_binary(decimals: 1)}% increase"

      html_body = build_product_html_body(product_name, category, current_units, previous_units, date, change_percent)
      text_body = build_product_text_body(product_name, category, current_units, previous_units, date, change_percent)

      email =
        Email.new()
        |> Email.to(recipients)
        |> Email.from({"PipeForge Alerts", get_from_email()})
        |> Email.subject(subject)
        |> Email.html_body(html_body)
        |> Email.text_body(text_body)

      case deliver(email) do
        {:ok, _} ->
          Logger.info("Successfully sent product spike alert email")
          :ok

        {:error, reason} ->
          Logger.error("Failed to send product spike alert email: #{inspect(reason)}")
          {:error, reason}
      end
    else
      Logger.warning("No email recipients configured, skipping email alert")
      :ok
    end
  end

  defp build_html_body(alert_type, current_value, previous_value, date, change_percent) do
    direction = if change_percent < 0, do: "dropped", else: "spiked"
    color = if change_percent < 0, do: "#dc2626", else: "#16a34a"

    """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <style>
        body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
        .container { max-width: 600px; margin: 0 auto; padding: 20px; }
        .header { background-color: #{color}; color: white; padding: 20px; text-align: center; }
        .content { padding: 20px; background-color: #f9fafb; }
        .metric { display: flex; justify-content: space-between; padding: 10px; background-color: white; margin: 10px 0; border-radius: 4px; }
        .label { font-weight: bold; }
        .value { color: #{color}; }
      </style>
    </head>
    <body>
      <div class="container">
        <div class="header">
          <h1>Sales Alert: #{String.upcase(alert_type)}</h1>
        </div>
        <div class="content">
          <p>Revenue #{direction} by <strong>#{abs(change_percent) |> :erlang.float_to_binary(decimals: 1)}%</strong></p>
          <div class="metric">
            <span class="label">Date:</span>
            <span class="value">#{Date.to_iso8601(date)}</span>
          </div>
          <div class="metric">
            <span class="label">Current Revenue:</span>
            <span class="value">#{format_currency(current_value)}</span>
          </div>
          <div class="metric">
            <span class="label">Previous Revenue:</span>
            <span class="value">#{format_currency(previous_value)}</span>
          </div>
          <div class="metric">
            <span class="label">Change:</span>
            <span class="value">#{format_currency(current_value - previous_value)} (#{if change_percent < 0, do: "-", else: "+"}#{abs(change_percent) |> :erlang.float_to_binary(decimals: 1)}%)</span>
          </div>
        </div>
      </div>
    </body>
    </html>
    """
  end

  defp build_text_body(alert_type, current_value, previous_value, date, change_percent) do
    direction = if change_percent < 0, do: "dropped", else: "spiked"

    """
    Sales Alert: #{String.upcase(alert_type)}

    Revenue #{direction} by #{abs(change_percent) |> :erlang.float_to_binary(decimals: 1)}%

    Date: #{Date.to_iso8601(date)}
    Current Revenue: #{format_currency(current_value)}
    Previous Revenue: #{format_currency(previous_value)}
    Change: #{format_currency(current_value - previous_value)} (#{if change_percent < 0, do: "-", else: "+"}#{abs(change_percent) |> :erlang.float_to_binary(decimals: 1)}%)
    """
  end

  defp build_product_html_body(product_name, category, current_units, previous_units, date, change_percent) do
    """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <style>
        body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
        .container { max-width: 600px; margin: 0 auto; padding: 20px; }
        .header { background-color: #16a34a; color: white; padding: 20px; text-align: center; }
        .content { padding: 20px; background-color: #f9fafb; }
        .metric { display: flex; justify-content: space-between; padding: 10px; background-color: white; margin: 10px 0; border-radius: 4px; }
        .label { font-weight: bold; }
        .value { color: #16a34a; }
      </style>
    </head>
    <body>
      <div class="container">
        <div class="header">
          <h1>Product Performance Spike</h1>
        </div>
        <div class="content">
          <p><strong>#{product_name}</strong> (#{category}) saw a <strong>#{change_percent |> :erlang.float_to_binary(decimals: 1)}%</strong> increase in units sold</p>
          <div class="metric">
            <span class="label">Date:</span>
            <span class="value">#{Date.to_iso8601(date)}</span>
          </div>
          <div class="metric">
            <span class="label">Current Units:</span>
            <span class="value">#{current_units}</span>
          </div>
          <div class="metric">
            <span class="label">Previous Units:</span>
            <span class="value">#{previous_units}</span>
          </div>
          <div class="metric">
            <span class="label">Change:</span>
            <span class="value">+#{current_units - previous_units} units</span>
          </div>
        </div>
      </div>
    </body>
    </html>
    """
  end

  defp build_product_text_body(product_name, category, current_units, previous_units, date, change_percent) do
    """
    Product Performance Spike

    #{product_name} (#{category}) saw a #{change_percent |> :erlang.float_to_binary(decimals: 1)}% increase in units sold

    Date: #{Date.to_iso8601(date)}
    Current Units: #{current_units}
    Previous Units: #{previous_units}
    Change: +#{current_units - previous_units} units
    """
  end

  defp get_alert_recipients do
    recipients =
      Application.get_env(:pipeforge, :alert_email_recipients) ||
        System.get_env("ALERT_EMAIL_RECIPIENTS")

    if recipients do
      String.split(recipients, ",") |> Enum.map(&String.trim/1)
    else
      []
    end
  end

  defp get_from_email do
    Application.get_env(:pipeforge, :alert_from_email) ||
      System.get_env("ALERT_FROM_EMAIL") ||
      "alerts@pipeforge.com"
  end

  defp format_currency(%Decimal{} = value) do
    "KES #{value |> Decimal.to_float() |> :erlang.float_to_binary(decimals: 2)}"
  end

  defp format_currency(value) when is_number(value) do
    "KES #{value |> :erlang.float_to_binary(decimals: 2)}"
  end

  defp format_currency(value), do: inspect(value)
end
