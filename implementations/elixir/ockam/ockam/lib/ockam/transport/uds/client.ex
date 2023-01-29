defmodule Ockam.Transport.UDS.Client do
  @moduledoc false
  use Ockam.Worker

  alias Ockam.Message
  alias Ockam.Transport.UDS
  alias Ockam.Wire

  require Logger

  @impl true
  def address_prefix(_options), do: "UDS_C_"

  @impl true
  def setup(options, state) do
    {host, port} = Keyword.fetch!(options, :destination)
    heartbeat = Keyword.get(options, :heartbeat)

    {protocol, inet_address} =
      case host do
        string when is_binary(string) ->
          {:inet, to_charlist(string)}

        ipv4 when is_tuple(ipv4) and tuple_size(ipv4) == 4 ->
          {:inet, ipv4}

        ipv6 when is_tuple(ipv6) and tuple_size(ipv6) == 8 ->
          {:inet6, ipv6}
      end

    # TODO: connect/3 and controlling_process/2 should be in a callback.
    case :gen_tcp.connect(inet_address, port, [
           :binary,
           protocol,
           active: true,
           packet: 2,
           nodelay: true
         ]) do
      {:ok, socket} ->
        :gen_tcp.controlling_process(socket, self())

        state =
          Map.merge(state, %{
            socket: socket,
            inet_address: inet_address,
            port: port,
            heartbeat: heartbeat
          })

        schedule_heartbeat(state)
        {:ok, state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def handle_info({:tcp, socket, data}, %{socket: socket} = state) do
    ## TODO: send/receive message in multiple UDS packets
    case Wire.decode(data, :tcp) do
      {:ok, message} ->
        forwarded_message =
          message
          |> Message.trace(state.address)

        Ockam.Router.route(forwarded_message)

      {:error, %Wire.DecodeError{} = e} ->
        raise e

      e ->
        raise e
    end

    {:noreply, state}
  end

  def handle_info({:tcp_closed, _}, state) do
    {:stop, :normal, state}
  end

  def handle_info({:tcp_error, _}, state) do
    {:stop, :normal, state}
  end

  def handle_info(:heartbeat, state) do
    case heartbeat_enabled?(state) do
      true ->
        empty_message = %Message{
          onward_route: [state.address],
          return_route: [],
          payload: ""
        }

        encode_and_send_over_tcp(empty_message, state)
        schedule_heartbeat(state)

      false ->
        :ok
    end

    {:noreply, state}
  end

  def heartbeat_enabled?(%{heartbeat: heartbeat}) do
    is_integer(heartbeat) and heartbeat > 0
  end

  def schedule_heartbeat(%{heartbeat: heartbeat} = state) do
    case heartbeat_enabled?(state) do
      true ->
        Process.send_after(self(), :heartbeat, heartbeat)

      false ->
        :ok
    end
  end

  @impl true
  def handle_message(%{payload: _payload} = message, state) do
    with :ok <- encode_and_send_over_tcp(message, state) do
      {:ok, state}
    end
  end

  defp encode_and_send_over_tcp(message, state) do
    forwarded_message = Message.forward(message)

    with {:ok, encoded_message} <- Wire.encode(forwarded_message) do
      ## TODO: send/receive message in multiple UDS packets
      case byte_size(encoded_message) <= UDS.packed_size_limit() do
        true ->
          send_over_tcp(encoded_message, state)

        false ->
          Logger.error("Message to big for UDS: #{inspect(message)}")
          {:error, {:message_too_big, message}}
      end
    end
  end

  defp send_over_tcp(data, %{socket: socket}) do
    :gen_tcp.send(socket, data)
  end
end
