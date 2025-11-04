defmodule PipeForge.Ingestion.FileHasher do
  @moduledoc """
  Generates content hashes for files to detect duplicates.
  """

  @doc """
  Generates SHA256 hash of file content.
  """
  def hash_file(file_path) do
    :crypto.hash(:sha256, File.read!(file_path))
    |> Base.encode16(case: :lower)
  end

  @doc """
  Generates SHA256 hash from binary content.
  """
  def hash_content(content) when is_binary(content) do
    :crypto.hash(:sha256, content)
    |> Base.encode16(case: :lower)
  end
end
