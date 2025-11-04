defmodule PipeForge.Ingestion.FileHasher do
  @moduledoc """
  Generates content hashes for files to detect duplicates.
  """

  @doc """
  Generates SHA256 hash of file content.
  """
  def hash_file(file_path) do
    file_path
    |> File.read!()
    |> hash_content()
  end

  @doc """
  Generates SHA256 hash from binary content.
  """
  def hash_content(content) when is_binary(content) do
    content
    |> :crypto.hash(:sha256)
    |> Base.encode16(case: :lower)
  end
end
