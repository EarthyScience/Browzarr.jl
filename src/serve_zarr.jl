"""
    serve_zarr(path; host="127.0.0.1")

Spin up a local HTTP server exposing a Zarr store at `path`.
Returns the URL string to pass to `browzarr(; store=...)`.
"""
function serve_zarr(path::String; host::String = "127.0.0.1")
    server = Sockets.listen(0) # OS picks a free port
    _, port = getsockname(server)

    CORS_HEADERS = [
        "Access-Control-Allow-Origin" => "*",
        "Access-Control-Allow-Methods" => "GET, OPTIONS",
        "Access-Control-Allow-Headers" => "Content-Type",
    ]

    function handler(req::HTTP.Request)
        req.method == "OPTIONS" && return HTTP.Response(200, CORS_HEADERS)

        rel = lstrip(req.target, '/')
        fpath = joinpath(path, rel)

        isfile(fpath) || return HTTP.Response(404, CORS_HEADERS, "Not found")

        filesize = stat(fpath).size
        mime = endswith(fpath, ".json") || occursin(".z", basename(fpath)) ?
            "application/json" : "application/octet-stream"
        headers = [
            CORS_HEADERS..., "Content-Type" => mime,
            "Accept-Ranges" => "bytes", "Content-Length" => string(filesize),
        ]

        range_hdr = HTTP.header(req, "Range", "")
        if !isempty(range_hdr)
            m = match(r"bytes=(\d+)-(\d*)", range_hdr)
            if !isnothing(m)
                start = parse(Int, m[1])
                stop = isempty(m[2]) ? filesize - 1 : parse(Int, m[2])
                len = stop - start + 1
                body = open(fpath, "r") do io
                    seek(io, start)
                    read(io, len)
                end
                return HTTP.Response(
                    206, [
                        headers...,
                        "Content-Range" => "bytes $start-$stop/$filesize",
                        "Content-Length" => string(len),
                    ]; body
                )
            end
        end

        return HTTP.Response(200, headers, read(fpath))
    end

    @async HTTP.serve(handler, host, port, server = server)
    lock(SERVERS_LOCK) do
        ZARR_SERVERS[port] = server
    end
    atexit(() -> stop_zarr!(port))
    @info "Zarr HTTP server started" path url = "http://$host:$port"
    return "http://$host:$port"
end

"""
    stop_zarr!(port)

Stop the Zarr HTTP server running on `port`.
"""
function stop_zarr!(port::Int)
    return lock(SERVERS_LOCK) do
        srv = get(ZARR_SERVERS, port, nothing)
        srv === nothing && return
        close(srv)
        pop!(ZARR_SERVERS, port, nothing)
        @info "Zarr server stopped" port
    end
end
