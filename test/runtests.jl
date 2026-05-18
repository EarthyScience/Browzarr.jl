using Browzarr
using Test
using HTTP
using Zarr

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

@testset "serve_zarr unconsolidated store" begin
    mktempdir() do dir
        g = zgroup(dir)
        zcreate(g, "temp", Float32, (4, 4))
        @test !isfile(joinpath(dir, ".zmetadata"))

        url = serve_zarr(dir)
        port = parse(Int, HTTP.URIs.URI(url).port)
        try
            meta = HTTP.get("$url/.zmetadata"; retry = false)
            @test meta.status == 200
            @test occursin("zarr_consolidated_format", String(meta.body))
            @test occursin("temp/.zarray", String(meta.body))

            group = HTTP.get("$url/.zgroup"; retry = false)
            @test group.status == 200
        finally
            stop_zarr!(port)
        end
    end
end

@testset "serve_zarr does not synthesize .zmetadata when zarr.json exists" begin
    mktempdir() do dir
        write(joinpath(dir, "zarr.json"), "{}")
        url = serve_zarr(dir)
        port = parse(Int, HTTP.URIs.URI(url).port)
        try
            meta = HTTP.get("$url/.zmetadata"; retry = false, status_exception = false)
            @test meta.status == 404
        finally
            stop_zarr!(port)
        end
    end
end
