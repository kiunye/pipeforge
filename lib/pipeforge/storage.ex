defmodule PipeForge.Storage do
  @moduledoc """
  Handles file storage operations using MinIO/S3-compatible storage.
  Falls back to local file storage if MinIO is unavailable.
  """

  alias ExAws.S3

  @doc """
  Checks if MinIO/S3 storage is available.
  """
  def minio_available? do
    case ensure_bucket(bucket()) do
      :ok -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  @doc """
  Ensures the bucket exists, creating it if necessary.
  """
  def ensure_bucket(bucket_name \\ bucket()) do
    case S3.head_bucket(bucket_name) |> ExAws.request() do
      {:ok, _} ->
        :ok

      {:error, {:http_error, 404, _}} ->
        # Bucket doesn't exist, create it
        region = Application.get_env(:pipeforge, :storage)[:region] || "us-east-1"
        case S3.put_bucket(bucket_name, region) |> ExAws.request() do
          {:ok, _} -> :ok
          error -> {:error, "Failed to create bucket: #{inspect(error)}"}
        end

      error ->
        {:error, "Failed to check bucket: #{inspect(error)}"}
    end
  rescue
    _ -> {:error, :minio_unavailable}
  end

  @doc """
  Uploads a file to MinIO/S3 storage or local file storage as fallback.
  """
  def upload_file(file_path, key, bucket \\ bucket()) do
    # Try MinIO first
    case ensure_bucket(bucket) do
      :ok ->
        result =
          file_path
          |> S3.Upload.stream_file()
          |> S3.upload(bucket, key)
          |> ExAws.request()

        case result do
          {:ok, _} -> result
          _ -> upload_file_local(file_path, key)
        end

      _ ->
        upload_file_local(file_path, key)
    end
  rescue
    _ -> upload_file_local(file_path, key)
  end

  @doc """
  Downloads a file from storage to a temporary location.
  """
  def download_file(key, bucket \\ bucket()) do
    # Try MinIO first
    case bucket |> S3.get_object(key) |> ExAws.request() do
      {:ok, %{body: content}} ->
        temp_path = System.tmp_dir!() |> Path.join("csv_#{System.unique_integer([:positive])}.csv")
        File.write!(temp_path, content)
        {:ok, temp_path}

      _ ->
        download_file_local(key)
    end
  rescue
    _ -> download_file_local(key)
  end

  @doc """
  Checks if a file exists in storage.
  """
  def file_exists?(key, bucket \\ bucket()) do
    # Try MinIO first
    case bucket |> S3.head_object(key) |> ExAws.request() do
      {:ok, _} -> true
      {:error, {:http_error, 404, _}} -> file_exists_local?(key)
      {:error, _} -> file_exists_local?(key)
    end
  rescue
    _ -> file_exists_local?(key)
  end

  @doc """
  Deletes a file from storage.
  """
  def delete_file(key, bucket \\ bucket()) do
    # Try MinIO first
    case bucket |> S3.delete_object(key) |> ExAws.request() do
      {:ok, _} -> :ok
      _ -> delete_file_local(key)
    end
  rescue
    _ -> delete_file_local(key)
  end

  @doc """
  Generates a presigned URL for file access (MinIO only).
  """
  def presigned_url(key, bucket \\ bucket(), expires_in \\ 3600) do
    if minio_available?() do
      ExAws.S3.presigned_url(ExAws.Config.new(:s3), :get, bucket, key, expires_in: expires_in)
    else
      {:error, "Presigned URLs only available with MinIO/S3"}
    end
  end

  # Local file storage fallback functions

  defp upload_file_local(file_path, key) do
    storage_dir = local_storage_dir()
    File.mkdir_p!(storage_dir)

    dest_path = Path.join(storage_dir, sanitize_key(key))

    case File.copy(file_path, dest_path) do
      {:ok, _bytes} -> {:ok, %{}}
      error -> {:error, "Failed to copy file locally: #{inspect(error)}"}
    end
  end

  defp download_file_local(key) do
    storage_dir = local_storage_dir()
    source_path = Path.join(storage_dir, sanitize_key(key))

    if File.exists?(source_path) do
      temp_path = System.tmp_dir!() |> Path.join("csv_#{System.unique_integer([:positive])}.csv")
      case File.copy(source_path, temp_path) do
        {:ok, _bytes} -> {:ok, temp_path}
        error -> {:error, "Failed to copy file: #{inspect(error)}"}
      end
    else
      {:error, "File not found: #{key}"}
    end
  end

  defp file_exists_local?(key) do
    storage_dir = local_storage_dir()
    source_path = Path.join(storage_dir, sanitize_key(key))
    File.exists?(source_path)
  end

  defp delete_file_local(key) do
    storage_dir = local_storage_dir()
    file_path = Path.join(storage_dir, sanitize_key(key))

    if File.exists?(file_path) do
      File.rm(file_path)
      :ok
    else
      :ok
    end
  end

  defp local_storage_dir do
    base_dir = Application.get_env(:pipeforge, :storage)[:local_dir] || "priv/storage"
    Path.expand(base_dir, File.cwd!())
  end

  defp sanitize_key(key) do
    # Remove leading slashes and replace path separators
    key
    |> String.trim_leading("/")
    |> String.replace("/", "_")
  end

  defp bucket do
    Application.get_env(:pipeforge, :storage)[:bucket] || "pipeforge-uploads"
  end
end
