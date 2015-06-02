defmodule IO.Proxy do
  use GenServer

  def start_link() do
    GenServer.start_link(__MODULE__, nil)
  end

  def handle_info({:io_request, from, ref, req}, state) do
    reply = :io.request(Process.group_leader(), req)
    send(from, {:io_reply, ref, reply})
    {:noreply, state}
  end
end
