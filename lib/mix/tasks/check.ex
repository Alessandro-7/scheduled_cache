defmodule Mix.Tasks.Check do
  @moduledoc """
  Run multiple code checks (test, dialyzer, format, etc.)
  with single command
  """

  # credo:disable-for-this-file

  use Mix.Task
  require Logger

  @dialyzer [:no_missing_calls, :no_undefined_callbacks]

  defmacrop catch_all(expr) do
    quote do
      try do
        case unquote(expr) do
          :ok -> :ok
          {:ok, _} = ok -> ok
          value -> {:ok, value}
        end
      catch
        :throw, e -> {:error, e}
        :error, e -> {:error, e}
      end
    end
  end

  @doc "Run mix check task"
  def run(_args) do
    run_tasks([
      {:env, :test},
      {"test", ["--raise"]},
      {:cmd, {"mix", ["dialyzer"]}, ignore_exit: ["Code: 2"]},
      {"format", ["--check-formatted"]},
      "inch",
      {:cmd, {"mix", ["credo", "--color"]}}
    ])
  end

  defp run_tasks([]), do: :ok

  defp run_tasks([task | rest]) do
    {key, args, opts} = parse_task(task)

    key
    |> run_task(args)
    |> process_task_result(opts)
    |> case do
      :ok -> run_tasks(rest)
      {:error, _} = e -> e
    end
  end

  defp parse_task(task) do
    case task do
      mix_task when is_binary(mix_task) -> {:task, mix_task, []}
      {mix_task, _} = r when is_binary(mix_task) -> {:task, r, []}
      {key, args} -> {key, args, []}
      {_key, _args, _opts} = r -> r
    end
  end

  defp run_task(key, args) do
    case {key, args} do
      {:env, env} ->
        Mix.env(env)

      {:cmd, cmd} ->
        launch_cmd(cmd)

      {:task, task} ->
        launch_mix_task(task)
    end
  end

  defp process_task_result(result, opts) do
    ignore_exit = Keyword.get(opts, :ignore_exit, false)

    case result do
      :ok ->
        :ok

      {:ok, _} ->
        :ok

      {:error, reason} = e ->
        ignore_exit =
          case ignore_exit do
            bool when is_boolean(ignore_exit) -> bool
            list when is_list(list) -> reason in list
          end

        case ignore_exit do
          true ->
            :ok

          false ->
            Logger.error(reason_to_string(reason))

            e
        end
    end
  end

  defp reason_to_string(reason) do
    case reason do
      %{message: m} -> m
      b when is_binary(b) -> b
      other -> inspect(other)
    end
  end

  defp launch_mix_task(task) do
    case task do
      {name, args} when is_binary(name) ->
        catch_all(Mix.Task.run(name, args))

      name when is_binary(name) ->
        catch_all(Mix.Task.run(name, []))
    end
  end

  defp launch_cmd(cmd) do
    {cmd, args} =
      case cmd do
        {_cmd, _args} = r -> r
        cmd -> {cmd, []}
      end

    case System.cmd(cmd, args, into: IO.stream(:stdio, :line)) do
      {_data, 0} -> :ok
      {_data, code} -> {:error, "Code: #{code}"}
    end
  end
end
