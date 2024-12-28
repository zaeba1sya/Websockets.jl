# Websockets.jl

---

Abstraction for fast and easy websocket implementation in your project

## Installation

To install Websockets, simply use the Julia package manager:

```julia
] add Websockets
```

## Usage

```julia
using Websockets

Websockets.open(
    "wss://stream.binance.com:9443/stream?streams=adausdt@depth20@100ms/btcusdt@depth20@100ms",
    Dict("sec-websocket-extensions" => "permessage-deflate"),
    true, 60, 3, false, 5, 3
) do conn
    Websockets.send(conn, "Hello Binance!")

    count = 0

    while Websockets.isopen(conn) && count < 10
        Websockets.recv(conn)
        count += 1
    end

    Websockets.close(conn)
end
```

## Contributing

Contributions to Websockets are welcome! If you encounter a bug, have a feature request, or would like to contribute code, please open an issue or a pull request on GitHub.
