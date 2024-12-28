include("../src/Websockets.jl")

@testset "Websockets tests" begin
    @testset "Binance connection" begin
        Websockets.open(
            "wss://stream.binance.com:9443/stream?streams=adausdt@depth20@100ms/btcusdt@depth20@100ms",
            Dict("sec-websocket-extensions" => "permessage-deflate"),
            true,
            60,
            3,
            false,
            1,
            3,
        ) do conn
            @test Websockets.is_open(conn) == true
            msg = Websockets.recv(conn)
            @test msg !== nothing
            @test length(msg) > 0

            Websockets.close(conn)
            @test Websockets.is_open(conn) == false
        end
    end
end
