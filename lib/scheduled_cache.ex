defmodule ScheduledCache do
  @moduledoc """
    Public API to create and access scheduled cache.
  """
  alias ScheduledCache.CacheServer

  @typedoc """
    A crontab-like string, e.g. "0 5 * * 1"
  """
  @type schedule :: String.t()

  @typedoc """
      `name` - cache name (must be unique)
      `schedule` - cache clear schedule
      `expired_cache_ttl` - time to live of cache
      `db_path` - path for storing RocksDB files must be "./{name}" by default
      `db_opts` - options directly passed into RocksDB.open/1,2
  """
  @type opts :: %{
          required(:name) => atom(),
          required(:schedule) => schedule(),
          optional(:expired_cache_ttl) => pos_integer(),
          optional(:db_path) => charlist() | String.t(),
          optional(:db_opts) => Rocksdb.opts()
        }

  @doc """
  Builds and overrides a child specification.
  """
  @spec child_spec(opts :: opts()) :: Supervisor.child_spec()
  def child_spec(opts) do
    CacheServer.child_spec(opts)
  end

  @doc """
  Starts the cache as a supervised process.
  """
  @spec start_link(opts :: opts()) :: Supervisor.on_start()
  def start_link(opts) do
    CacheServer.start_link(opts)
  end

  @doc """
  Puts timestamp with value (nil if value is not provided) by key to the cache.
  Returns previous timestamp with value.

  ## Examples

      iex> put(:cache, "key")
      {:ok, nil, nil}

      iex> put(:cache, "key")
      {:ok, ~N[2020-06-16 11:15:55.940306], nil}

      iex> put(:cache, "key", "value")
      {:ok, nil, nil}

      iex> put(:cache, "key", "new value")
      {:ok, ~N[2020-06-16 11:12:55.940306], "value"}

      iex> put("bad cache", "key", "value")
      {:error, "Cache bad cache doesnt exist"}

  """
  @spec put(cache :: atom(), key :: any(), value :: any()) ::
          {:ok, prev_ts :: nil | NaiveDateTime.t(), prev_value :: nil | any()}
          | {:error, reason :: any()}
  def put(cache, key, value \\ nil) do
    CacheServer.put(cache, key, value)
  end

  @doc """
  Gets timestamp with value by key from the cache.
  Returns timestamp with value.

  ## Examples

      iex> get(:cache, "exsisting key")
      {:ok, ~N[2020-06-16 11:15:55.940306], "value"}

      iex> get(:cache, "nonexistent key")
      {:ok, nil, nil}

      iex> get("bad cache", "key")
      {:error, "Cache bad cache doesnt exist"}

  """
  @spec get(cache :: atom(), key :: any()) ::
          {:ok, ts :: nil | NaiveDateTime.t(), value :: nil | any()}
          | {:error, reason :: any()}
  def get(cache, key) do
    CacheServer.get(cache, key)
  end
end
