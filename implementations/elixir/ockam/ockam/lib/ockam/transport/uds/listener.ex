if Code.ensure_loaded?(:ranch) do
  defmodule Ockam.Transport.UDS.Listener do
    @moduledoc """
    UDS listener GenServer for UDS transport
    Wrapper for ranch listener
    """

    ## TODO: is it possible to use ranch listener as a supervised process?
    use GenServer

    require Logger

    @typedoc """
    UDS listener options
    - socket_name: t::String.t() - Unix Domain Socket file name
    """
    @type options :: Keyword.t()

    def start_link(options) do
      GenServer.start_link(__MODULE__, options)
    end

    @doc false
    @impl true
    def init(options) do
      socket_name = Keyword.get_lazy(options, :socket_name, &default_socket_name/0)

      handler_options = Keyword.get(options, :handler_options, [])

      ref = make_ref()
      transport = :ranch_tcp
      transport_options = [ifaddr: {:local, socket_name}]
      protocol = Ockam.Transport.UDS.Handler
      protocol_options = [packet: 2, nodelay: true, handler_options: handler_options]

      with {:ok, _apps} <- Application.ensure_all_started(:ranch),
           {:ok, ranch_listener} <-
             start_listener(ref, transport, transport_options, protocol, protocol_options) do
        {:ok, %{ranch_listener: ranch_listener}}
      end
    end

    defp start_listener(ref, transport, transport_options, protocol, protocol_options) do
      r = :ranch.start_listener(ref, transport, transport_options, protocol, protocol_options)

      case r do
        {:ok, child} -> {:ok, child}
        {:ok, child, _info} -> {:ok, child}
        {:error, reason} -> {:error, {:could_not_start_ranch_listener, reason}}
      end
    end

    def default_socket_name, do: "/tmp/ockam"
  end
end
