Code.require_file "../test_helper.exs", __DIR__

defmodule ExUnit.CaptureLogTest do
  use ExUnit.Case

  require Logger

  import ExUnit.CaptureLog

  test "no output" do
    assert capture_log(fn -> end) == ""
  end

  test "assert inside" do
    group_leader = Process.group_leader()

    try do
      capture_log(fn ->
        assert false
      end)
    rescue
      error in [ExUnit.AssertionError] ->
        assert error.message == "Expected truthy, got false"
    end

    # Ensure no leakage on failures
    assert group_leader == Process.group_leader()
  end

  test "log tracking" do
    events =
      assert capture_log(fn ->
        Logger.info "one"
        capture_log(fn -> Logger.error "one" end)
        Logger.warn "two"
        parent = self()
        spawn(fn ->
          Logger.debug "three"
          send(parent, :done)
        end)
        receive do: (:done -> :ok)
      end)

    assert events =~ "[info]  one\n\e[0m"
    assert events =~ "[warn]  two\n\e[0m"
    assert events =~ "[debug] three\n\e[0m"
    refute events =~ "[error] one\n\e[0m"
  end
end
