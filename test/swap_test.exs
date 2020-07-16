defmodule SwapTest do
  require Logger
  use ExUnit.Case
  @moduletag timeout: 70_000

  setup do
    File.rm_rf!("./test_swap")
    name = :test_swap
    schedule = "* * * * *"
    ScheduledCache.start_link(%{:name => name, :schedule => schedule})
    ScheduledCache.put(name, 1, 2)
    {:ok, [name: name, schedule: schedule]}
  end

  test "try to get value after swap", %{name: name} do
    now = NaiveDateTime.utc_now()
    sleep_time = (60 - now.second + 6) * 1000
    Logger.debug("Starting swap test. Please wait #{div(sleep_time, 1000)} seconds")
    Process.sleep(sleep_time)
    assert {:ok, nil, nil} = ScheduledCache.get(name, 1)
  end
end
