"""
    serve_zarr(path::String; host::String = "127.0.0.1")

Serve a local Zarr store as an HTTP server.
"""
function serve_zarr(path::String; host::String = "127.0.0.1")
    path = abspath(path)
    synthetic_metadata = _has_consolidated_metadata(path) ? nothing : _generate_metadata(path)

    CORS_HEADERS = [
        "Access-Control-Allow-Origin" => "*",
        "Access-Control-Allow-Methods" => "GET, OPTIONS",
        "Access-Control-Allow-Headers" => "Content-Type",
    ]

    function handler(req::HTTP.Request)
        req.method == "OPTIONS" && return HTTP.Response(200, CORS_HEADERS)

        target_path = _unescapeuri(_uri(req.target).path)
        rel = lstrip(target_path, '/')
        contains(rel, "..") && return HTTP.Response(403, CORS_HEADERS, "Forbidden")
        fpath = abspath(joinpath(path, rel))

        base = joinpath(path, "")
        if !startswith(fpath, base)
            return HTTP.Response(403, CORS_HEADERS, "Forbidden")
        end

        if !isnothing(synthetic_metadata) && !isfile(fpath)
            headers = [
                CORS_HEADERS...,
                "Content-Type" => "application/json",
                "Content-Length" => string(length(synthetic_metadata)),
            ]
            req.method == "HEAD" && return HTTP.Response(200, headers)
            return HTTP.Response(200, headers; body = synthetic_metadata)
        end

        isfile(fpath) || return HTTP.Response(404, CORS_HEADERS, "Not found")

        filesize = stat(fpath).size
        mime = endswith(fpath, ".json") || startswith(basename(fpath), ".z") ?
            "application/json" : "application/octet-stream"
        headers = [
            CORS_HEADERS..., "Content-Type" => mime,
            "Accept-Ranges" => "bytes", "Content-Length" => string(filesize),
        ]

        req.method == "HEAD" && return HTTP.Response(200, headers)

        range_hdr = HTTP.header(req, "Range", "")
        if !isempty(range_hdr)
            m = match(r"bytes=(\d+)-(\d*)", range_hdr)
            if !isnothing(m)
                start = parse(Int64, m[1])
                stop = isempty(m[2]) ? filesize - 1 : parse(Int64, m[2])
                if start >= filesize || stop < start
                    return HTTP.Response(416, [CORS_HEADERS..., "Content-Range" => "bytes */$filesize"])
                end
                stop = min(stop, filesize - 1)
                len = stop - start + 1
                body = open(fpath, "r") do io
                    seek(io, start)
                    read(io, len)
                end
                return HTTP.Response(206, [
                    headers...,
                    "Content-Range" => "bytes $start-$stop/$filesize",
                    "Content-Length" => string(len),
                ]; body)
            end
        end
        return HTTP.Response(200, headers; body = read(fpath))
    end

    s = _serve!(handler, host, 0)
    port = _port(s)
    server = _get_server(s)

    srv = ZarrServer(server, host, port, path)
    lock(SERVERS_LOCK) do
        ZARR_SERVERS[port] = srv
    end
    atexit(() -> stop_zarr!(port))
    @info "Zarr HTTP server started" url = "http://$host:$port"
    return srv
end

function _has_consolidated_metadata(path::String)
    zarr_json = joinpath(path, "zarr.json")
    if isfile(zarr_json)
        root = Zarr.JSON.parsefile(zarr_json; dicttype=Dict{String,Any})
        return haskey(root, "consolidated_metadata")
    end
    return isfile(joinpath(path, ".zmetadata"))
end

function _generate_metadata(path::String)
    store = DirectoryStore(path)
    d = Dict{String, Any}()
    Zarr.consolidate_metadata(store, d, "") # this should work for v2 and v3 stores, check support in Zarr.jl
    isempty(d) && return nothing
    @info "Serving synthesized metadata for unconsolidated Zarr store" path
    buf = IOBuffer()
    Zarr.JSON.print(buf, Dict("metadata" => d, "zarr_consolidated_format" => 1), 4)
    return take!(buf)
end

function stop_zarr!(srv::ZarrServer)
    _forceclose(srv.server)
    return @info "Zarr server stopped" port = srv.port
end

"""
    stop_zarr!(port)

Stop the Zarr HTTP server running on `port`.
"""
function stop_zarr!(port::Integer)
    return lock(SERVERS_LOCK) do
        srv = get(ZARR_SERVERS, port, nothing)
        srv === nothing && return
        stop_zarr!(srv)
        pop!(ZARR_SERVERS, port, nothing)
    end
end

"""
    stop_all_zarr!()

Stop all Zarr HTTP servers.
"""
function stop_all_zarr!()
    servers = lock(SERVERS_LOCK) do
        s = collect(values(ZARR_SERVERS))
        empty!(ZARR_SERVERS)
        s
    end
    for srv in servers
        try
            stop_zarr!(srv)
        catch e
            @warn "Failed to stop Zarr server" port = srv.port exception = e
        end
    end
    return @info "All Zarr servers stopped"
end

running_zarr_servers() = lock(SERVERS_LOCK) do
    collect(values(ZARR_SERVERS))
end

get_zarr_server(port::Integer) = lock(SERVERS_LOCK) do
    get(ZARR_SERVERS, port, nothing)
end
