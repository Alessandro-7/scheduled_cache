defmodule :scheduled_cache_erl do
  funs =
    ScheduledCache.module_info()[:exports]
    |> Enum.filter(fn {fun, _arity} -> not (fun in [:__info__, :module_info]) end)

  for {fun, arity} <- funs do
    defdelegate unquote(fun)(unquote_splicing(ScheduledCache.Utils.make_args(arity))),
      to: ScheduledCache
  end
end
