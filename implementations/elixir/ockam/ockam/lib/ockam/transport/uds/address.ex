defmodule Ockam.Transport.UDSAddress do
  @moduledoc """
  Functions to work with UDS transport address
  """
  alias Ockam.Address

  @address_type 3

  @type t :: Address.t(1)

  def type(), do: @address_type

  @spec new(String.t()) :: t()
  def new(socket_name) when is_binary(socket_name) do
    %Address{type: @address_type, value: socket_name}
  end

  def is_uds_address(address) do
    Address.type(address) == @address_type
  end

  def socket_name(address) do
    Address.value(address)
  end
end
