defmodule ExUnit.LoggerFormatter do
  @moduledoc false

  use GenEvent

  def init(opts) do
    colors = Keyword.put_new(opts[:colors], :enabled, IO.ANSI.enabled?)
    backends = Logger.Config.backends()
    Enum.map(backends, &remove_console/1)
    {:ok, {backends, colors: colors}}
  end

  def terminate(_reason, {backends, opts}) do
    :ok = add_capture(%{group_leader: nil}, opts)
    Enum.map(backends, &add_console/1)
    case remove_capture(%{group_leader: nil}, :get) do
      {:ok, []} -> nil
      {:ok, output} ->
        IO.puts(["The following output was logged:\n" | output])
    end
    :ok
  end

  def handle_event({:test_started, %ExUnit.Test{} = test}, {_, opts} = state) do
    :ok = add_capture(test, opts)
    {:ok, state}
  end

  def handle_event({:test_finished, %ExUnit.Test{state: {:failed, _reason}} = test}, state) do
    case remove_capture(test, :get) do
      {:ok, []} -> nil
      {:ok, output} ->
        IO.puts(["The following output was logged:\n" | output])
    end
    {:ok, state}
  end

  def handle_event({:test_finished, %ExUnit.Test{} = test}, state) do
    _ = remove_capture(test, nil)
    {:ok, state}
  end

  def handle_event(_event, map) do
    {:ok, map}
  end

  defp add_capture(%{group_leader: pid}, opts) do
    GenEvent.add_handler(Logger, {Logger.Backends.Capture, pid}, {pid, opts})
  end

  defp remove_capture(%{group_leader: pid}, flag) do
    GenEvent.remove_handler(Logger, {Logger.Backends.Capture, pid}, flag)
  end

  defp remove_console(:console) do
    Logger.remove_backend(:console)
  end

  defp remove_console(_other), do: nil

  defp add_console(:console) do
    Logger.add_backend(:console)
  end

  defp add_console(_other), do: nil
end
