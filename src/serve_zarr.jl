"""
    _synthetic_zmetadata(path) -> Union{Vector{UInt8}, Nothing}

Build the same consolidated metadata dict as `Zarr.consolidate_metadata(s::AbstractStore, d, prefix)`
with `prefix == ""`, then serialize it like `Zarr.consolidate_metadata(s::AbstractStore, p)`
(the `JSON.print` of `metadata` / `zarr_consolidated_format`) but **without** writing `s[p, .zmetadata]` to disk.
`Zarr.zarr_req_handler` instead calls `consolidate_metadata(s)` so the store gains a real `.zmetadata`
file before keys are served.

Returns `nothing` when `.zmetadata` already exists on disk, a root `zarr.json` exists (v2-only synthesis),
or the directory is not a Zarr v2 group/array.
"""
function _synthetic_zmetadata(path::String)
    meta_path = joinpath(path, ".zmetadata")
    isfile(meta_path) && return nothing
    isfile(joinpath(path, "zarr.json")) && return nothing
    is_v2 = isfile(joinpath(path, ".zgroup")) || isfile(joinpath(path, ".zarray"))
    is_v2 || return nothing
    store = DirectoryStore(path)
    d = Dict{String, Any}()
    Zarr.consolidate_metadata(store, d, "")
    buf = IOBuffer()
    Zarr.JSON.print(buf, Dict("metadata" => d, "zarr_consolidated_format" => 1), 4)
    return take!(buf)
end

"""
    serve_zarr(path; host="127.0.0.1")

Spin up a local HTTP server exposing a Zarr store at `path`.
Returns the URL string to pass to `browzarr(; store=...)`.

Unconsolidated Zarr v2 stores (`.zgroup` / `.zattrs` only) are served with a
synthesized `.zmetadata` so HTTP clients can discover the hierarchy without directory listing.
"""
function serve_zarr(path::String; host::String = "127.0.0.1")
    path = abspath(path)
    synthetic_zmetadata = _synthetic_zmetadata(path)
    !isnothing(synthetic_zmetadata) &&
        @info "Serving synthesized .zmetadata for unconsolidated Zarr v2 store" path

    CORS_HEADERS = [
        "Access-Control-Allow-Origin" => "*",
        "Access-Control-Allow-Methods" => "GET, OPTIONS",
        "Access-Control-Allow-Headers" => "Content-Type",
    ]

    function handler(req::HTTP.Request)
        req.method == "OPTIONS" && return HTTP.Response(200, CORS_HEADERS)

        target_path = HTTP.URIs.unescapeuri(HTTP.URIs.URI(req.target).path)
        rel = lstrip(target_path, '/')
        contains(rel, "..") && return HTTP.Response(403, CORS_HEADERS, "Forbidden")
        fpath = abspath(joinpath(path, rel))

        base = joinpath(path, "")
        if !startswith(fpath, base)
            return HTTP.Response(403, CORS_HEADERS, "Forbidden")
        end

        if rel == ".zmetadata" && !isnothing(synthetic_zmetadata)
            headers = [
                CORS_HEADERS...,
                "Content-Type" => "application/json",
                "Content-Length" => string(length(synthetic_zmetadata)),
            ]
            req.method == "HEAD" && return HTTP.Response(200, headers)
            return HTTP.Response(200, headers; body = synthetic_zmetadata)
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
                return HTTP.Response(
                    206, [
                        headers...,
                        "Content-Range" => "bytes $start-$stop/$filesize",
                        "Content-Length" => string(len),
                    ]; body
                )
            end
        end

        return HTTP.Response(200, headers, open(fpath, "r"))
    end
    
    # HTTP.jl 2.x: non-blocking server
    server = HTTP.serve!(handler, host, 0)
    # Extract the OS-assigned ephemeral port
    port = HTTP.port(server)

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
function stop_zarr!(port::Integer)
    return lock(SERVERS_LOCK) do
        srv = get(ZARR_SERVERS, port, nothing)
        srv === nothing && return
        close(srv)
        pop!(ZARR_SERVERS, port, nothing)
        @info "Zarr server stopped" port
    end
end
