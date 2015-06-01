defmodule ExUnit.ProxyIO do
  use GenServer

  def proxy(pid, leader) do
    GenServer.start_link(__MODULE__, {pid, leader})
  end

  def init({pid, leader} = state) do
    Process.group_leader(self(), leader)
    Process.group_leader(pid, self())
    {:ok, state}
  end

  def handle_info({:io_request, from, ref, req}, {_pid, leader} = state) do
    send(from, {:io_reply, ref, :io.request(leader, req)})
    {:noreply, state}
  end
end
