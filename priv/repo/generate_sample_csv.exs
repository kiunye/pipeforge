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

# Create CSV content
header = ["order_ref", "order_date", "customer_email", "product_sku", "product_name",
          "product_category", "quantity", "unit_price", "total_amount", "payment_method", "region"]

rows = [header | Enum.map(orders, &Tuple.to_list/1)]
csv_content = RFC4180.dump_to_iodata(rows) |> IO.iodata_to_binary()

# Write to file
output_path = Path.join([__DIR__, "sample_orders_1000.csv"])
File.write!(output_path, csv_content)

IO.puts("Generated sample CSV with 1000 orders: #{output_path}")
IO.puts("File size: #{byte_size(csv_content)} bytes")
