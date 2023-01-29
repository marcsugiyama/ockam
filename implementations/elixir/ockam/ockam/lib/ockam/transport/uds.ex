defmodule Ockam.Transport.UDS do
  @moduledoc """
  UDS (Unix Domain Socket) transport
  """

  alias Ockam.Transport.UDS.Listener
  alias Ockam.Transport.UDSAddress

  alias Ockam.Message
  alias Ockam.Router
  alias Ockam.Transport.UDS.Client

  require Logger

  @packed_size_limit 65_000

  def packed_size_limit() do
    @packed_size_limit
  end

  def child_spec(options) do
    id = id(options)

    %{
      id: id,
      start: {__MODULE__, :start, [options]}
    }
  end

  defp id(options) do
    case Keyword.fetch(options, :listen) do
      {:ok, listen} ->
        if Code.ensure_loaded(:ranch) do
          socket_name = Keyword.get(listen, :socket_name, Listener.default_socket_name())
          "UDS_LISTENER_#{socket_name}"
        else
          "UDS_TRANSPORT"
        end

      _other ->
        "UDS"
    end
  end

  ## TODO: rename to start_link
  @doc """
  Start a UDS transport

  ## Parameters
  - options:
      listen: t:Listener.options() - UDS listener options, default is empty (no listener is started)
      implicit_clients: boolean() - start client on receiving UDSAddress message, default is true
      client_options: list() - additional options to pass to implicit clients
  """
  @spec start(Keyword.t()) :: :ignore | {:error, any} | {:ok, any}
  def start(options \\ []) do
    client_options = Keyword.get(options, :client_options, [])
    implicit_clients = Keyword.get(options, :implicit_clients, true)

    case implicit_clients do
      true ->
        ## TODO: do we want to stop transports?
        Router.set_message_handler(
          UDSAddress.type(),
          {__MODULE__, :handle_transport_message, [client_options]}
        )

      false ->
        Router.set_message_handler(
          UDSAddress.type(),
          {__MODULE__, :implicit_connections_disabled, []}
        )
    end

    case Keyword.fetch(options, :listen) do
      {:ok, listen} ->
        if Code.ensure_loaded(:ranch) do
          Listener.start_link(listen)
        else
          {:error, :ranch_not_loaded}
        end

      _other ->
        :ignore
    end
  end

  @spec handle_transport_message(Ockam.Message.t(), Keyword.t()) :: :ok | {:error, any()}
  def handle_transport_message(message, client_options) do
    [destination | _onward_route] = Message.onward_route(message)
    case Client.create([
           {:destination, destination},
           {:restart_type, :temporary} | client_options
         ]) do
      {:ok, client_address} ->
        [_socket_name | onward_route] = Message.onward_route(message)
        Router.route(Message.set_onward_route(message, [client_address | onward_route]))

      {:error, {:worker_init, _worker, reason}} ->
        {:error, reason}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def implicit_connections_disabled(_message) do
    {:error, {:uds_transport, :implicit_connections_disabled}}
  end

end
