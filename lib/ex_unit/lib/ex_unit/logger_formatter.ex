defmodule ExUnit.LoggerFormatter do
  @moduledoc false

  use GenEvent

  def init(_opts) do
    {:ok, nil}
  end

  def handle_event({:test_started, %ExUnit.Test{} = test}, state) do
    :ok = add_capture(test)
    {:ok, state}
  end

  def handle_event({:test_finished, %ExUnit.Test{state: {:failed, _reason}} = test}, state) do
    {:ok, output} = remove_capture(test, :get)
    IO.write(output)
    {:ok, state}
  end

  def handle_event({:test_finished, %ExUnit.Test{} = test}, state) do
    _ = remove_capture(test, nil)
    {:ok, state}
  end

  def handle_event(_event, map) do
    {:ok, map}
  end

  defp add_capture(%{group_leader: pid}) do
    GenEvent.add_handler(Logger, {Logger.Backends.Capture, pid}, {pid, []})
  end

  defp remove_capture(%{group_leader: pid}, flag) do
    GenEvent.remove_handler(Logger, {Logger.Backends.Capture, pid}, flag)
  end
end
