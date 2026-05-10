using Browzarr
using Test
using HTTP

@testset "Browzarr server lifecycle" begin
    server = browzarr(; open = false)

    @testset "Server starts correctly" begin
        @test server isa Browzarr.BrowzarrServer
        @test server.host == "127.0.0.1"
        @test server.port isa Int
    end

    @testset "Server responds to HTTP requests" begin
        url = "http://$(server.host):$(server.port)"
        response = HTTP.get(url; retry = false)
        @test response.status == 200
    end

    Browzarr.stop_all!()

    @testset "Server stops cleanly" begin
        # After stop_all!(), connecting should fail
        @test_throws Exception HTTP.get(
            "http://127.0.0.1:3000"; retry = false, connect_timeout = 2
        )
    end
end
