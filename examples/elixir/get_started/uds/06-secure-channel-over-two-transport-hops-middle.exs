["../setup.exs", "../hop.exs"] |> Enum.map(&Code.require_file/1)

{:ok, _h1} = Hop.create(address: "h1")

# Start the UDS Transport Add-on for Ockam Routing and a UDS listener on port 3000.
Ockam.Transport.UDS.start(listen: [port: 3000])
