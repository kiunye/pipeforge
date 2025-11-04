defmodule PipeForge.Ingestion.CSVValidator do
  @moduledoc """
  Validates CSV files and maps columns to schema.
  """

  @expected_columns [
    "order_ref",
    "order_date",
    "customer_email",
    "product_sku",
    "product_name",
    "product_category",
    "quantity",
    "unit_price",
    "total_amount",
    "payment_method",
    "region"
  ]

  @doc """
  Validates CSV header row and returns column mapping.
  """
  def validate_header(header_row) do
    header_map =
      header_row
      |> Enum.with_index()
      |> Enum.into(%{}, fn {col, idx} -> {normalize_column(col), idx} end)

    missing_required = @expected_columns -- Map.keys(header_map)
    unexpected = Map.keys(header_map) -- @expected_columns

    case {missing_required, unexpected} do
      {[], _} ->
        {:ok, header_map}

      {[_ | _] = missing, _} ->
        {:error, :missing_columns, missing}

      _ ->
        {:ok, header_map}
    end
  end

  @doc """
  Validates a CSV data row against the schema.
  """
  def validate_row(row, header_map) do
    errors = []

    errors =
      if missing_value?(row, header_map, "order_ref") do
        ["order_ref is required" | errors]
      else
        errors
      end

    errors =
      if missing_value?(row, header_map, "order_date") do
        ["order_date is required" | errors]
      else
        errors
      end

    errors =
      if invalid_date?(row, header_map, "order_date") do
        ["order_date must be a valid date" | errors]
      else
        errors
      end

    errors =
      if invalid_number?(row, header_map, "quantity") do
        ["quantity must be a valid number" | errors]
      else
        errors
      end

    errors =
      if invalid_number?(row, header_map, "unit_price") do
        ["unit_price must be a valid number" | errors]
      else
        errors
      end

    errors =
      if invalid_number?(row, header_map, "total_amount") do
        ["total_amount must be a valid number" | errors]
      else
        errors
      end

    case errors do
      [] -> {:ok, map_row(row, header_map)}
      _ -> {:error, errors}
    end
  end

  defp normalize_column(col) when is_binary(col) do
    col
    |> String.downcase()
    |> String.trim()
    |> String.replace(~r/[_\s]+/, "_")
  end

  defp normalize_column(_), do: ""

  defp missing_value?(row, header_map, column) do
    idx = Map.get(header_map, column)
    value = Enum.at(row, idx, "")
    is_nil(idx) or value == "" or value == nil
  end

  defp invalid_date?(row, header_map, column) do
    idx = Map.get(header_map, column)
    value = Enum.at(row, idx, "")

    if value == "" or is_nil(value) do
      false
    else
      case Date.from_iso8601(value) do
        {:ok, _} -> false
        _ -> true
      end
    end
  end

  defp invalid_number?(row, header_map, column) do
    idx = Map.get(header_map, column)
    value = Enum.at(row, idx, "")

    if value == "" or is_nil(value) do
      false
    else
      case Float.parse(value) do
        {_num, _} -> false
        :error -> true
      end
    end
  end

  defp map_row(row, header_map) do
    Enum.reduce(header_map, %{}, fn {column, idx}, acc ->
      value = Enum.at(row, idx, "")
      Map.put(acc, column, value)
    end)
  end
end
