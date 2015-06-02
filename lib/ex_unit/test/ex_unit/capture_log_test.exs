Code.require_file "../test_helper.exs", __DIR__

defmodule ExUnit.CaptureLogTest do
  use ExUnit.Case

  import ExUnit.CaptureLog

  test "no output" do
    assert capture_log(fn -> end) == []
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

  test "log levels" do
    # ...
  end

  test "capture nesting" do
    # ...
  end
end
