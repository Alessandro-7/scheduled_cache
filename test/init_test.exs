defmodule InitTest do
  use ExUnit.Case

  setup do
    File.rm_rf!("./test_init")
    name = :test_init
    schedule = "* * * * *"
    {:ok, pid} = ScheduledCache.start_link(%{:name => name, :schedule => schedule})
    Process.exit(pid, :normal)
    {:ok, [name: name, schedule: schedule]}
  end

  test "start existing cache with other opts", %{name: name} do
    assert {:error, _e} = ScheduledCache.start_link(%{:name => name, :schedule => "1 * * * *"})
  end

  test "bad cache name", %{schedule: schedule} do
    assert {:error, _e} = ScheduledCache.start_link(%{:name => "bad name", :schedule => schedule})
  end

  test "bad cache schedule", %{name: name} do
    assert {:error, _e} = ScheduledCache.start_link(%{:name => name, :schedule => :bad_schedule})
  end
end
