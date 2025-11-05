defmodule PipeForge.Ingestion.FileHasher do
  @moduledoc """
  Generates content hashes for files to detect duplicates.
  """

  @doc """
  Generates SHA256 hash of file content.
  """
  def hash_file(file_path) when is_binary(file_path) do
    case File.read(file_path) do
      {:ok, content} when is_binary(content) ->
        hash_content(content)

      {:ok, content} ->
        {:error, "File content is not binary: #{inspect(content)}"}

      {:error, reason} ->
        {:error, "Failed to read file: #{inspect(reason)}"}
    end
  end

  def hash_file(file_path) do
    {:error, "Invalid file path: #{inspect(file_path)}"}
  end

  @doc """
  Generates SHA256 hash from binary content.
  """
  def hash_content(content) when is_binary(content) do
    :crypto.hash(:sha256, content)
    |> Base.encode16(case: :lower)
  end
end
