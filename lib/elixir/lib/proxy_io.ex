defmodule ProxyIO do
  use GenServer

  def open() do
    GenServer.start_link(__MODULE__, nil)
  end

  def close(proxy, timeout \\ 5000) do
    GenServer.call(proxy, :close, timeout)
  end

  def handle_info({:io_request, from, ref, req}, state) do
    reply = :io.request(Process.group_leader(), req)
    send(from, {:io_reply, ref, reply})
    {:noreply, state}
  end

  def handle_call(:close, _from, state) do
    {:stop, :normal, :ok, state}
  end
end
