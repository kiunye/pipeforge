#!/usr/bin/env elixir
# Script to patch rabbit_common for OTP 28 compatibility
# Run this after mix deps.get if rabbit_common fails to compile

Code.require_file("../../mix.exs", __DIR__)

deps_path = Path.join([File.cwd!(), "deps"])
rabbit_cert_file = Path.join([deps_path, "rabbit_common", "src", "rabbit_cert_info.erl"])

if File.exists?(rabbit_cert_file) do
  content = File.read!(rabbit_cert_file)
  
  if String.contains?(content, "?'street-address'") do
    patched_content = String.replace(
      content,
      "{?'street-address'               , \"STREET\"},",
      "{{2,5,4,9}                       , \"STREET\"}, %% streetAddress OID (OTP 28 compatibility)"
    )
    
    File.write!(rabbit_cert_file, patched_content)
    IO.puts("✓ Patched rabbit_cert_info.erl for OTP 28 compatibility")
  else
    IO.puts("✓ rabbit_cert_info.erl already patched or doesn't need patching")
  end
else
  IO.puts("⚠ rabbit_cert_info.erl not found at #{rabbit_cert_file}")
  IO.puts("  Run 'mix deps.get' first")
end
