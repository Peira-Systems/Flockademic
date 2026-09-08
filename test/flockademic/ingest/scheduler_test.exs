defmodule Flockademic.Ingest.SchedulerTest do
  use Flockademic.DataCase

  alias Flockademic.Ingest.Scheduler

  describe "enabled?/0" do
    test "reflects application config" do
      original = Application.get_env(:flockademic, Scheduler, [])

      Application.put_env(:flockademic, Scheduler, enabled: true)
      assert Scheduler.enabled?()

      Application.put_env(:flockademic, Scheduler, enabled: false)
      refute Scheduler.enabled?()

      Application.put_env(:flockademic, Scheduler, original)
    end
  end

  describe "start_link/1" do
    test "does not start when disabled (the default)" do
      Application.put_env(:flockademic, Scheduler, enabled: false)
      assert :ignore = Scheduler.init([])
    end
  end

  describe "handle_info(:tick, ...)" do
    setup do
      original = Application.get_env(:flockademic, Scheduler, [])
      Application.put_env(:flockademic, Scheduler, enabled: true)
      on_exit(fn -> Application.put_env(:flockademic, Scheduler, original) end)
      :ok
    end

    test "runs the ingest function for the current region, then advances the rotation" do
      test_pid = self()

      ingest_fun = fn bbox ->
        send(test_pid, {:ingested, bbox})
        %{ingested: 3, failed_tiles: []}
      end

      regions = [{"Alpha", {1, 2, 3, 4}}, {"Beta", {5, 6, 7, 8}}]

      {:ok, state} =
        Scheduler.init(regions: regions, ingest_fun: ingest_fun, interval_ms: :timer.hours(1))

      Phoenix.PubSub.subscribe(Flockademic.PubSub, "camera_updates")

      {:noreply, state} = Scheduler.handle_info(:tick, state)

      assert_received {:ingested, {1, 2, 3, 4}}
      assert_received {:snapshot_complete, _stats}
      assert state.index == 1

      {:noreply, state} = Scheduler.handle_info(:tick, state)

      assert_received {:ingested, {5, 6, 7, 8}}
      assert state.index == 0, "rotation should wrap back to the first region"
    end

    test "logs a warning but keeps rotating when some tiles fail" do
      ingest_fun = fn _bbox -> %{ingested: 1, failed_tiles: [{{0, 0, 1, 1}, :timeout}]} end
      regions = [{"Alpha", {1, 2, 3, 4}}]

      {:ok, state} = Scheduler.init(regions: regions, ingest_fun: ingest_fun, interval_ms: 1)

      assert {:noreply, %{index: 0}} = Scheduler.handle_info(:tick, state)
    end

    test "does not crash with an empty region list" do
      {:ok, state} = Scheduler.init(regions: [], ingest_fun: fn _ -> flunk("should not run") end)

      assert {:noreply, ^state} = Scheduler.handle_info(:tick, state)
    end
  end
end
