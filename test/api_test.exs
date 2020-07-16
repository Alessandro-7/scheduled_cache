defmodule ApiTest do
  use ExUnit.Case
  use PropCheck

  @name :test_api

  setup_all do
    File.rm_rf!("./test_api")
    {:ok, _pid} = ScheduledCache.start_link(%{:name => @name, :schedule => "* * * * *"})

    {:ok, name: @name}
  end

  test "put without value", %{name: name} do
    assert {:ok, nil, nil} == ScheduledCache.put(name, "just a key")
  end

  test "put by new key", %{name: name} do
    assert {:ok, nil, nil} == ScheduledCache.put(name, "new key", 1)
  end

  test "put by existing key", %{name: name} do
    {:ok, nil, nil} = ScheduledCache.put(name, "some key", 1)
    assert {:ok, prev_ts, 1} = ScheduledCache.put(name, "some key", 2)
  end

  test "get value", %{name: name} do
    {:ok, nil, nil} = ScheduledCache.put(name, "known key")
    assert {:ok, nil, nil} == ScheduledCache.get(name, "unknown key")
    assert {:ok, ts, value} = ScheduledCache.get(name, "known key")
  end

  property "put any() value by any() key" do
    quickcheck(
      forall [key <- any(), value <- any()] do
        {res, _prev_ts, _prev_val} = ScheduledCache.put(@name, key, value)
        assert res == :ok
      end
    )
  end

  property "get by any() key" do
    quickcheck(
      forall key <- any() do
        {res, _ts, _value} = ScheduledCache.get(@name, key)
        assert res == :ok
      end
    )
  end
end
