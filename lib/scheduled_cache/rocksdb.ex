defmodule ScheduledCache.Rocksdb do
  @moduledoc """
    RocksDB wrapper.
  """
  require Logger

  @type opts :: :rocksdb.opts()

  @spec open(binary | charlist, [
          {atom,
           atom
           | binary
           | [char | {any, any} | {any, any, any}]
           | number
           | {:bitset_merge_operator, non_neg_integer}
           | {:capped_prefix_transform, integer}
           | {:fixed_prefix_transform, integer}
           | :rocksdb.env()
           | :rocksdb.rate_limiter_handle()
           | :rocksdb.sst_file_manager()
           | :rocksdb.write_buffer_manager()}
        ]) :: {:error, any} | {:ok, :rocksdb.db_handle()}
  def open(path, options \\ [])

  def open(path, options) when is_binary(path) do
    path
    |> to_charlist()
    |> open(options)
  end

  def open(path, options) when is_list(path) do
    :rocksdb.open(path, options)
  end

  @spec close(:rocksdb.db_handle()) :: :ok | {:error, any()}
  def close(db) do
    :rocksdb.close(db)
  end

  @spec get(:rocksdb.db_handle(), binary, any) :: {:error, any} | {:ok, any}
  def get(db, key, default \\ nil) do
    case :rocksdb.get(db, key, []) do
      {:ok, <<131, _rest::binary>> = value} -> {:ok, :erlang.binary_to_term(value)}
      {:ok, value} -> {:ok, value}
      :not_found -> {:ok, default}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec put(:rocksdb.db_handle(), binary, any) :: :ok | {:error, any}
  def put(db, key, value) when is_binary(key) do
    :rocksdb.put(db, key, process_value(value), [])
  end

  @spec del(:rocksdb.db_handle(), binary) :: :ok | {:error, any}
  def del(db, key) when is_binary(key) do
    :rocksdb.delete(db, key, [])
  end

  @spec put_batch(:rocksdb.db_handle(), nonempty_maybe_improper_list) :: :ok
  def put_batch(db, [_ | _] = items) do
    items =
      Enum.map(items, fn
        {k, v} -> {:put, k, v}
        _ -> nil
      end)

    process_batch(db, items)
  end

  @spec del_batch(:rocksdb.db_handle(), nonempty_maybe_improper_list) :: :ok
  def del_batch(db, [_ | _] = items) do
    items =
      Enum.map(items, fn
        k -> {:del, k}
      end)

    process_batch(db, items)
  end

  @spec process_batch(:rocksdb.db_handle(), nonempty_maybe_improper_list) :: :ok
  def process_batch(db, [_ | _] = items) do
    {:ok, batch} = :rocksdb.batch()

    items
    |> Stream.map(fn
      {:put, k, v} when is_binary(k) ->
        {:put, k, process_value(v)}

      {:del, k} when is_binary(k) ->
        {:del, k}

      _ ->
        nil
    end)
    |> Enum.each(fn
      {:put, k, v} ->
        :rocksdb.batch_put(batch, k, v)

      {:del, k} ->
        :rocksdb.batch_delete(batch, k)

      _ ->
        :ok
    end)

    case :rocksdb.write_batch(db, batch, []) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.error("put_batch: #{inspect(reason)}")
    end

    :rocksdb.release_batch(batch)
  end

  @spec iterate(:rocksdb.db_handle()) :: Enumerable.t()
  def iterate(db) do
    Stream.resource(iterate_start(db), &iterate_step/1, &iterate_end/1)
  end

  ### Iterator helpers functions

  defp iterate_start(db) do
    fn ->
      case :rocksdb.iterator(db, []) do
        {:ok, iter} -> {:first, iter}
        {:error, _reason} -> :final
      end
    end
  end

  defp iterate_step({move, iter}) do
    case :rocksdb.iterator_move(iter, move) do
      {:ok, k, <<131, _rest::binary>> = v} -> {[{k, :erlang.binary_to_term(v)}], {:next, iter}}
      {:ok, k, v} -> {[{k, v}], {:next, iter}}
      {:error, _reason} -> {:halt, {:final, iter}}
    end
  end

  defp iterate_step(:final) do
    nil
  end

  defp iterate_end(nil) do
    nil
  end

  defp iterate_end({_, iter}) do
    :rocksdb.iterator_close(iter)
  end

  defp process_value(value) when is_binary(value), do: value
  defp process_value(value), do: :erlang.term_to_binary(value)
end
