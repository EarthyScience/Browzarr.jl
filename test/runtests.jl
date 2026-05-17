using Browzarr
using Test
using HTTP
using Zarr
using JSON

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

@testset "serve_zarr skips v2 metadata for v3 stores" begin
    mktempdir() do dir
        write(
            joinpath(dir, "zarr.json"),
            """{"zarr_format":3,"node_type":"group","attributes":{}}""",
        )
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

@testset "serve_zarr unconsolidated v3 store" begin
    mktempdir() do dir
        store = DirectoryStore(dir)
        g = zgroup(store, "", Zarr.ZarrFormat(3))
        zcreate(g, "temp", Float32, (4, 4))

        root = JSON.parse(read(joinpath(dir, "zarr.json"), String))
        @test get(root, "consolidated_metadata", nothing) === nothing

        url = serve_zarr(dir)
        port = parse(Int, HTTP.URIs.URI(url).port)
        try
            resp = HTTP.get("$url/zarr.json"; retry = false)
            @test resp.status == 200
            served = JSON.parse(String(resp.body))
            cons = served["consolidated_metadata"]
            @test cons["kind"] == "inline"
            @test haskey(cons["metadata"], "temp")
            @test cons["metadata"]["temp"]["node_type"] == "array"
        finally
            stop_zarr!(port)
        end
    end
end

@testset "serve_zarr preserves v3 inline consolidation" begin
    mktempdir() do dir
        write(
            joinpath(dir, "zarr.json"),
            """{
              "zarr_format": 3,
              "node_type": "group",
              "consolidated_metadata": {
                "kind": "inline",
                "must_understand": false,
                "metadata": {"existing": {"node_type": "array", "zarr_format": 3}}
              }
            }""",
        )
        url = serve_zarr(dir)
        port = parse(Int, HTTP.URIs.URI(url).port)
        try
            resp = HTTP.get("$url/zarr.json"; retry = false)
            served = JSON.parse(String(resp.body))
            @test served["consolidated_metadata"]["metadata"] == Dict(
                "existing" => Dict("node_type" => "array", "zarr_format" => 3),
            )
        finally
            stop_zarr!(port)
        end
    end
end
