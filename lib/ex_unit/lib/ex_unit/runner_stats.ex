defmodule ExUnit.RunnerStats do
  @moduledoc false

  use GenServer

  def init(_opts) do
    {:ok, %{total: 0, failures: 0, skipped: 0}}
  end

  def stats(pid) do
    GenServer.call(pid, :stats, :infinity)
  end

  def handle_call(:stats, _from, stats) do
    {:reply, stats, stats}
  end

  def handle_cast({:test_finished, %ExUnit.Test{state: {tag, _}}},
                  %{total: total, failures: failures} = stats) when tag in [:failed, :invalid] do
    {:noreply, %{stats | total: total + 1, failures: failures + 1}}
  end

  def handle_cast({:test_finished, %ExUnit.Test{state: {:skip, _}}},
                  %{total: total, skipped: skipped} = stats) do
    {:noreply, %{stats | total: total + 1, skipped: skipped + 1}}
  end

  def handle_cast({:case_finished, %ExUnit.TestCase{state: {:failed, _failures}} = test_case},
                  %{failures: failures, total: total} = stats) do
    test_count = length(test_case.tests)
    {:noreply, %{stats | failures: failures + test_count, total: total + test_count}}
  end

  def handle_cast({:test_finished, _}, %{total: total} = stats) do
    {:noreply, %{stats | total: total + 1}}
  end

  def handle_cast(_, stats) do
    {:noreply, stats}
  end
end
