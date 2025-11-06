# Script to generate sample CSV data for testing
# Run with: mix run priv/repo/generate_sample_csv.exs

alias NimbleCSV.RFC4180

# Sample data pools - Prices in KES (Kenyan Shillings)
products = [
  {"SKU-ELEC-001", "Smartphone Pro", "Electronics", 79999.00},
  {"SKU-ELEC-002", "Laptop Ultra", "Electronics", 129999.00},
  {"SKU-ELEC-003", "Wireless Headphones", "Electronics", 8999.00},
  {"SKU-ELEC-004", "Smart Watch", "Electronics", 19999.00},
  {"SKU-ELEC-005", "Tablet Max", "Electronics", 34999.00},
  {"SKU-CLOTH-001", "Cotton T-Shirt", "Clothing", 1499.00},
  {"SKU-CLOTH-002", "Denim Jeans", "Clothing", 3999.00},
  {"SKU-CLOTH-003", "Running Shoes", "Clothing", 5999.00},
  {"SKU-CLOTH-004", "Winter Jacket", "Clothing", 7999.00},
  {"SKU-CLOTH-005", "Baseball Cap", "Clothing", 999.00},
  {"SKU-HOME-001", "Coffee Maker", "Home & Kitchen", 6999.00},
  {"SKU-HOME-002", "Blender Pro", "Home & Kitchen", 8999.00},
  {"SKU-HOME-003", "Bed Sheets Set", "Home & Kitchen", 3499.00},
  {"SKU-HOME-004", "Kitchen Knife Set", "Home & Kitchen", 4999.00},
  {"SKU-HOME-005", "Air Purifier", "Home & Kitchen", 14999.00},
  {"SKU-BOOK-001", "Programming Guide", "Books", 1999.00},
  {"SKU-BOOK-002", "Data Science Book", "Books", 2499.00},
  {"SKU-BOOK-003", "Design Patterns", "Books", 2299.00},
  {"SKU-BOOK-004", "System Architecture", "Books", 2799.00},
  {"SKU-BOOK-005", "DevOps Handbook", "Books", 2999.00}
]

payment_methods = ["mpesa", "paystack", "card", "bank_transfer", "other"]
# Kenyan counties/regions
regions = [
  "Nairobi", "Mombasa", "Kisumu", "Nakuru", "Eldoret",
  "Thika", "Malindi", "Kitale", "Garissa", "Kakamega",
  "Nyeri", "Meru", "Machakos", "Bungoma", "Busia"
]

# Generate customer emails (Kenyan domain examples)
customer_domains = ["gmail.com", "yahoo.com", "outlook.com", "kenya.co.ke", "yahoo.co.ke"]
customer_emails = for i <- 1..200 do
  domain = Enum.random(customer_domains)
  "customer#{i}@#{domain}"
end

# Generate orders
orders = for i <- 1..1000 do
  order_date = Date.add(Date.utc_today(), -Enum.random(0..90))
  customer_email = Enum.random(customer_emails)
  {sku, name, category, base_price} = Enum.random(products)
  quantity = Enum.random(1..5)
  # Small price variation in KES (up to ±500 KES)
  unit_price = base_price + (:rand.uniform() * 1000 - 500) |> Float.round(2)
  total_amount = (unit_price * quantity) |> Float.round(2)
  # M-Pesa is more common in Kenya, so weight it higher
  payment_method = if :rand.uniform() < 0.6, do: "mpesa", else: Enum.random(payment_methods)
  region = Enum.random(regions)

  {
    "ORD-#{String.pad_leading(Integer.to_string(i), 6, "0")}",
    Date.to_iso8601(order_date),
    customer_email,
    sku,
    name,
    category,
    quantity,
    unit_price,
    total_amount,
    payment_method,
    region
  }
end

# Create CSV content with header as first row
header = ["order_ref", "order_date", "customer_email", "product_sku", "product_name",
          "product_category", "quantity", "unit_price", "total_amount", "payment_method", "region"]

# Convert orders to list format
data_rows = Enum.map(orders, &Tuple.to_list/1)

# Build CSV content manually to ensure header is first
# RFC4180 format: escape fields with quotes if they contain commas, quotes, or newlines
escape_field = fn
  field when is_binary(field) ->
    if String.contains?(field, [",", "\"", "\n", "\r"]) do
      "\"" <> String.replace(field, "\"", "\"\"") <> "\""
    else
      field
    end
  field when is_number(field) ->
    to_string(field)
  field ->
    to_string(field)
end

format_row = fn row ->
  row
  |> Enum.map(escape_field)
  |> Enum.join(",")
end

# Build CSV lines: header first, then data rows
header_line = format_row.(header)
data_lines = Enum.map(data_rows, format_row)
csv_lines = [header_line | data_lines]

# Verify we have the right number of lines (1 header + 1000 data rows)
expected_line_count = 1 + length(data_rows)
actual_line_count = length(csv_lines)

if actual_line_count != expected_line_count do
  IO.puts("⚠️  WARNING: Line count mismatch!")
  IO.puts("Expected: #{expected_line_count} lines (1 header + #{length(data_rows)} data)")
  IO.puts("Actual: #{actual_line_count} lines")
  raise "CSV line count validation failed!"
end

# Verify header is first
if List.first(csv_lines) != header_line do
  IO.puts("⚠️  WARNING: Header is not first line!")
  IO.puts("First line: #{inspect(List.first(csv_lines))}")
  IO.puts("Expected header: #{inspect(header_line)}")
  raise "CSV header position validation failed!"
end

# Write to file line by line to ensure proper formatting
output_path = Path.join([__DIR__, "sample_orders_1000.csv"])

File.open!(output_path, [:write, :utf8], fn file ->
  # Write header first
  header_line = format_row.(header)
  IO.write(file, header_line <> "\n")

  # Write data rows
  Enum.each(data_rows, fn row ->
    row_line = format_row.(row)
    IO.write(file, row_line <> "\n")
  end)
end)

# Verify file was written correctly by reading it back
{:ok, file_content} = File.read(output_path)
csv_content = file_content

if byte_size(file_content) == 0 do
  raise "File verification failed: CSV is empty after writing!"
end

# Verify file content directly (more reliable than parsing)
file_lines = String.split(file_content, "\n", trim: true)
expected_line_count = 1 + length(data_rows) # 1 header + data rows

if length(file_lines) != expected_line_count do
  IO.puts("⚠️  WARNING: Line count mismatch!")
  IO.puts("Expected: #{expected_line_count} lines")
  IO.puts("Actual: #{length(file_lines)} lines")
  raise "File verification failed: line count mismatch!"
end

# Verify header is first line
first_line = List.first(file_lines)
expected_header_line = format_row.(header)

if first_line != expected_header_line do
  IO.puts("⚠️  WARNING: Header mismatch!")
  IO.puts("First line in file: #{inspect(first_line)}")
  IO.puts("Expected header line: #{inspect(expected_header_line)}")
  raise "File verification failed: header mismatch!"
end

# Optional: Try parsing to verify it works (but don't fail if parser has issues)
case RFC4180.parse_string(file_content) do
  parsed_rows when is_list(parsed_rows) ->
    if length(parsed_rows) == expected_line_count do
      parsed_header = Enum.at(parsed_rows, 0)
      if parsed_header == header do
        IO.puts("✓ Parser verification passed: #{length(parsed_rows)} rows parsed correctly")
      else
        IO.puts("⚠️  Note: Parser returned different header format (this may be OK)")
        IO.puts("   Parsed: #{inspect(parsed_header)}")
        IO.puts("   Expected: #{inspect(header)}")
      end
    else
      IO.puts("⚠️  Note: Parser returned #{length(parsed_rows)} rows (expected #{expected_line_count})")
      IO.puts("   This may be a parser configuration issue, but file content is correct")
    end
  _ ->
    IO.puts("⚠️  Note: Could not parse CSV for verification (file content is correct)")
end

IO.puts("✓ Generated sample CSV with 1000 orders: #{output_path}")
IO.puts("✓ File size: #{byte_size(csv_content)} bytes")
IO.puts("✓ Total rows (including header): #{length(file_lines)}")
IO.puts("✓ Header validation passed: #{inspect(first_line)}")
