defmodule ScheduledCache.CacheServer do
  @moduledoc false

  require Logger
  use GenServer

  @spec child_spec(opts :: ScheduledCache.opts()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  @spec start_link(opts :: ScheduledCache.opts()) :: Supervisor.on_start()
  def start_link(opts) do
    case is_atom(opts.name) do
      true ->
        GenServer.start_link(__MODULE__, opts)

      false ->
        Logger.error("Provided #{inspect(opts.name)} name isnt an atom")
        {:error, "Cache name error"}
    end
  end

  @impl GenServer
  def init(opts) do
    Process.flag(:trap_exit, true)
    start_server(opts)
  end

  @impl GenServer
  def handle_info({:timeout, _timer, :swap}, state) do
    start_swap(state)
    {:noreply, state}
  end

  def handle_info({:timeout, _timer, :remove}, state) do
    case start_remove(state) do
      {:ok, new_state} ->
        {:noreply, new_state}

      {:error, _e} ->
        {:noreply, state}
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl GenServer
  def terminate(_reason, state) do
    ScheduledCache.Rocksdb.close(state.curr_db_ref)
    ScheduledCache.Rocksdb.close(state.spare_db_ref)
  end

  @spec put(cache :: atom(), key :: any(), value :: any()) ::
          {:ok, prev_ts :: nil | NaiveDateTime.t(), prev_value :: nil | any()}
          | {:error, reason :: any()}
  def put(cache, key, value \\ nil) do
    do_put(cache, key, value)
  end

  @spec get(cache :: atom(), key :: any()) ::
          {:ok, ts :: nil | NaiveDateTime.t(), value :: nil | any()}
          | {:error, reason :: any()}
  def get(cache, key) do
    do_get(cache, key)
  end

  ## private

  defp start_server(opts) do
    with {:ok, curr_opts} <- get_curr_opts(opts),
         {:ok, state} <- init_db(curr_opts, true) do
      {:ok, state}
    else
      {:error, e} ->
        {:stop, e}
    end
  end

  defp start_swap(state) do
    Logger.debug("Triggered timeout for #{state.name}")
    :persistent_term.put({__MODULE__, state.name}, state.spare_db_ref)

    case File.write("#{state.db_path}/cache.idx", String.last(state.spare_db_path)) do
      :ok ->
        timer = :erlang.start_timer(state.expired_cache_ttl, self(), :remove)
        {:ok, timer}

      {:error, e} ->
        {:error, e}
    end
  end

  defp start_remove(state) do
    Logger.debug("Removing #{state.name}")

    with :ok <- ScheduledCache.Rocksdb.close(state.curr_db_ref),
         :ok <- clear_db(state.curr_db_path) do
      curr = state.curr_db_path

      state = %{
        state
        | curr_db_path: state.spare_db_path,
          spare_db_path: curr,
          curr_db_ref: state.spare_db_ref
      }

      init_db(state, false)
    else
      {:error, e} ->
        Logger.error("Could not handle timeout for #{state.name} cache")
        {:error, e}
    end
  end

  defp init_db(opts, is_start) do
    case open_db(opts, is_start) do
      {:ok, new_opts} ->
        {:ok, timer} = start_timer(opts.schedule)
        new_opts = Map.put(new_opts, :timer, timer)
        {:ok, new_opts}

      {:outdate, new_opts} ->
        Logger.warn("Cache #{opts.name} was outdated on the start")
        start_swap(new_opts)
        {:ok, new_opts}

      {:error, e} ->
        Logger.error("Initialization of #{opts.name} cache was failed")
        {:error, e}
    end
  end

  defp get_curr_opts(opts) do
    opts =
      Map.put_new(opts, :db_path, "./#{opts.name}")
      |> Map.put_new(:expired_cache_ttl, 5000)
      |> Map.update(
        :db_opts,
        [create_if_missing: true],
        &Keyword.put(&1, :create_if_missing, true)
      )

    case Crontab.CronExpression.Parser.parse(opts.schedule) do
      {:ok, cron_map} ->
        opts = %{opts | schedule: cron_map}

        case get_curr_idx(opts.db_path) do
          "1" ->
            opts =
              Map.put(opts, :curr_db_path, "#{opts.db_path}/1")
              |> Map.put(:spare_db_path, "#{opts.db_path}/2")

            {:ok, opts}

          "2" ->
            opts =
              Map.put(opts, :curr_db_path, "#{opts.db_path}/2")
              |> Map.put(:spare_db_path, "#{opts.db_path}/1")

            {:ok, opts}

          {:error, e} ->
            Logger.error("Could not get number of current db #{opts.name} from idx file")
            {:error, e}
        end

      {:error, e} ->
        Logger.error("Could not parse #{opts.schedule}")
        {:error, e}
    end
  end

  defp get_curr_idx(db_path) do
    :ok = File.mkdir_p(db_path)

    case File.read("#{db_path}/cache.idx") do
      {:ok, curr_db} ->
        curr_db

      {:error, :enoent} ->
        case File.write("#{db_path}/cache.idx", "1") do
          :ok ->
            Logger.debug("File #{db_path}/cache.idx was created and setted to #{db_path}/1 cache")
            "1"

          {:error, e} ->
            Logger.error("Could not create missing #{db_path}/cache.idx file with #{inspect(e)}")
            {:error, e}
        end

      {:error, e} ->
        Logger.error("Could not open #{db_path}/cache.idx file with #{inspect(e)}")
        {:error, e}
    end
  end

  defp open_db(opts, true) do
    with {:ok, curr_cache} <- ScheduledCache.Rocksdb.open(opts.curr_db_path, opts.db_opts),
         {:ok, spare_cache} <- ScheduledCache.Rocksdb.open(opts.spare_db_path, opts.db_opts) do
      opts =
        Map.put(opts, :spare_db_ref, spare_cache)
        |> Map.put(:curr_db_ref, curr_cache)

      :persistent_term.put({__MODULE__, opts.name}, curr_cache)

      case verify_params(curr_cache, opts) do
        :ok ->
          {:ok, opts}

        :outdate ->
          {:outdate, opts}

        {:error, e} ->
          ScheduledCache.Rocksdb.close(spare_cache)
          ScheduledCache.Rocksdb.close(curr_cache)
          {:error, e}
      end
    else
      {:error, e} ->
        Logger.error("Could not open #{opts.name} cache with #{inspect(e)}")
        {:error, e}
    end
  end

  defp open_db(opts, false) do
    case ScheduledCache.Rocksdb.open(opts.spare_db_path, opts.db_opts) do
      {:ok, spare_cache} ->
        opts = Map.put(opts, :spare_db_ref, spare_cache)

        case update_params(spare_cache, opts, true) do
          :ok ->
            {:ok, opts}

          {:error, e} ->
            ScheduledCache.Rocksdb.close(spare_cache)
            {:error, e}
        end

      {:error, e} ->
        Logger.error("Could not open #{opts.name} cache with #{inspect(e)}")
        {:error, e}
    end
  end

  defp get_params(cache, opts) do
    with {:ok, name} <- ScheduledCache.Rocksdb.get(cache, "/self/name"),
         {:ok, schedule} <- ScheduledCache.Rocksdb.get(cache, "/self/schedule"),
         {:ok, valid_through} <- ScheduledCache.Rocksdb.get(cache, "/self/valid_through") do
      {name, schedule, valid_through}
    else
      {:error, e} ->
        Logger.error("Could not read parameters from #{opts.name} with #{inspect(e)}")
        {:error, e}
    end
  end

  defp update_params(cache, opts, is_spare \\ false) do
    valid_through =
      if is_spare do
        Crontab.Scheduler.get_next_run_dates(opts.schedule)
        |> Enum.at(1)
      else
        Crontab.Scheduler.get_next_run_date!(opts.schedule)
      end

    with :ok <- ScheduledCache.Rocksdb.put(cache, "/self/name", opts.name),
         :ok <- ScheduledCache.Rocksdb.put(cache, "/self/schedule", opts.schedule),
         :ok <- ScheduledCache.Rocksdb.put(cache, "/self/valid_through", valid_through) do
      Logger.debug(
        "Parameters of #{opts.name} were updated with #{
          inspect({opts.name, opts.schedule, valid_through})
        }"
      )

      :ok
    else
      {:error, e} ->
        Logger.error("Could not update parameters of #{opts.name}")
        {:error, e}
    end
  end

  defp verify_params(cache, opts) do
    case get_params(cache, opts) do
      {nil, nil, nil} ->
        update_params(cache, opts)

      {name, schedule, valid_through} ->
        if name !== opts.name or schedule !== opts.schedule do
          Logger.error("Parameters #{inspect({name, schedule})} doesnt equal inputed")
          {:error, "Invalid parameters"}
        else
          case NaiveDateTime.compare(valid_through, NaiveDateTime.utc_now()) do
            :lt ->
              :outdate

            :eq ->
              :outdate

            :gt ->
              :ok
          end
        end

      {:error, e} ->
        {:error, e}
    end
  end

  defp get_next_run(schedule) do
    next_date = Crontab.Scheduler.get_next_run_date!(schedule)
    next_run = NaiveDateTime.diff(next_date, NaiveDateTime.utc_now(), :millisecond)

    if next_run >= 0 do
      {:ok, next_run}
    else
      Logger.error("Got negative time of the next swap with schedule #{schedule}")
      {:error, "Negative time of the next swap"}
    end
  end

  defp start_timer(schedule) do
    case get_next_run(schedule) do
      {:ok, next_run} ->
        timer = :erlang.start_timer(next_run, self(), :swap)
        {:ok, timer}

      {:error, e} ->
        Logger.error("Could not start a timer for a cache")
        {:error, e}
    end
  end

  defp clear_db(db_path) do
    case File.rm_rf(db_path) do
      {:ok, [_ | _]} ->
        Logger.debug("Db #{db_path} was cleared")
        :ok

      {:ok, []} ->
        Logger.warn("Db #{db_path} doesnt exist")
        :ok

      {:error, e, _file} ->
        Logger.error("Could not remove db #{db_path} with #{inspect(e)}")
        {:error, e}
    end
  end

  defp do_put(cache, key, value) do
    case :persistent_term.get({__MODULE__, cache}, nil) do
      nil ->
        {:error, "Cache #{cache} doesnt exist"}

      curr_cache ->
        key_bin = :erlang.term_to_binary(key)

        with {:ok, prev} <- ScheduledCache.Rocksdb.get(curr_cache, key_bin),
             :ok <-
               ScheduledCache.Rocksdb.put(curr_cache, key_bin, {NaiveDateTime.utc_now(), value}) do
          if is_nil(prev) do
            {:ok, nil, nil}
          else
            {prev_ts, prev_value} = prev
            {:ok, prev_ts, prev_value}
          end
        else
          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp do_get(cache, key) do
    case :persistent_term.get({__MODULE__, cache}, nil) do
      nil ->
        {:error, "Cache #{cache} doesnt exist"}

      curr_cache ->
        key_bin = :erlang.term_to_binary(key)

        case ScheduledCache.Rocksdb.get(curr_cache, key_bin) do
          {:ok, {ts, value}} ->
            {:ok, ts, value}

          {:ok, nil} ->
            {:ok, nil, nil}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end
end
