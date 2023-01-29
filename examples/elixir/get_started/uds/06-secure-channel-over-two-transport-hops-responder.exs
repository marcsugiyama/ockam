["../setup.exs", "../echoer.exs"] |> Enum.map(&Code.require_file/1)

# Create a Echoer type worker at address "echoer".
{:ok, _echoer} = Echoer.create(address: "echoer")

# Create a vault and an identity keypair.
{:ok, vault} = Ockam.Vault.Software.init()
{:ok, identity} = Ockam.Vault.secret_generate(vault, type: :curve25519)

# Create a secure channel listener that will wait for requests to initiate an Authenticated Key Exchange.
Ockam.SecureChannel.create_listener(vault: vault, identity_keypair: identity, address: "secure_channel_listener")

# Start the UDS Transport Add-on for Ockam Routing and a UDS listener on port 4000.
Ockam.Transport.UDS.start(listen: [port: 4000])
