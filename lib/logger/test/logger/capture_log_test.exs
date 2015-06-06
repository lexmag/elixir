Code.require_file "../test_helper.exs", __DIR__

defmodule Logger.CaptureLogTest do
  use ExUnit.Case

  require Logger

  import Logger.CaptureLog

  test "no output" do
    assert capture_log(fn -> end) == ""
  end

  test "assert inside" do
    try do
      capture_log(fn ->
        assert false
      end)
    rescue
      error in [ExUnit.AssertionError] ->
        assert error.message == "Expected truthy, got false"
    end
  end

  test "no leakage on failures" do
    group_leader = Process.group_leader()

    test = self()
    assert_raise ArgumentError, fn ->
      capture_log(fn ->
        send(test, {:proxy_io, Process.group_leader()})
        raise ArgumentError
      end)
    end

    receive do
      {:proxy_io, pid} ->
        ref = Process.monitor(pid)
        assert_receive {:DOWN, ^ref, _, _, _}
    end
    assert Process.group_leader() == group_leader
  end

  test "log tracking" do
    captured =
      assert capture_log(fn ->
        Logger.info "one"

        captured = capture_log(fn -> Logger.error "one" end)
        send(test = self(), {:nested, captured})

        Logger.warn "two"

        spawn(fn ->
          Logger.debug "three"
          send(test, :done)
        end)
        receive do: (:done -> :ok)
      end)

    assert captured =~ "[info]  one\n\e[0m"
    assert captured =~ "[warn]  two\n\e[0m"
    assert captured =~ "[debug] three\n\e[0m"
    refute captured =~ "[error] one\n\e[0m"

    receive do
      {:nested, captured} ->
        assert captured =~ "[error] one\n\e[0m"
    end
  end
end
