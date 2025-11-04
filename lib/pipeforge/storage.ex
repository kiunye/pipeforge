defmodule PipeForge.Storage do
  @moduledoc """
  Handles file storage operations using MinIO/S3-compatible storage.
  """

  alias ExAws.S3

  @doc """
  Uploads a file to MinIO/S3 storage.
  """
  def upload_file(file_path, key, bucket \\ bucket()) do
    file_path
    |> S3.Upload.stream_file()
    |> S3.upload(bucket, key)
    |> ExAws.request()
  end

  @doc """
  Generates a presigned URL for file access.
  """
  def presigned_url(key, bucket \\ bucket(), expires_in \\ 3600) do
    ExAws.S3.presigned_url(ExAws.Config.new(:s3), :get, bucket, key, expires_in: expires_in)
  end

  @doc """
  Deletes a file from storage.
  """
  def delete_file(key, bucket \\ bucket()) do
    bucket
    |> S3.delete_object(key)
    |> ExAws.request()
  end

  @doc """
  Checks if a file exists in storage.
  """
  def file_exists?(key, bucket \\ bucket()) do
    case bucket |> S3.head_object(key) |> ExAws.request() do
      {:ok, _} -> true
      {:error, {:http_error, 404, _}} -> false
      {:error, _} -> false
    end
  end

  defp bucket do
    Application.get_env(:pipeforge, :storage)[:bucket] || "pipeforge-uploads"
  end
end

