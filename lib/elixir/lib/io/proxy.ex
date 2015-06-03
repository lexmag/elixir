defmodule IO.Proxy do
  use GenServer

  def start_link() do
    GenServer.start_link(__MODULE__, nil)
  end

  def stop(proxy, timeout \\ 5000) do
    GenServer.call(proxy, :stop, timeout)
  end

  def handle_info({:io_request, from, ref, req}, state) do
    reply = :io.request(Process.group_leader(), req)
    send(from, {:io_reply, ref, reply})
    {:noreply, state}
  end

  def handle_call(:stop, _from, state) do
    {:stop, :normal, :ok, state}
  end
end
