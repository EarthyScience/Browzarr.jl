_store_path(prefix::String, suffix::String) =
    isempty(prefix) ? suffix : rstrip(prefix, '/') * '/' * suffix

function _v3_consolidated_missing(root::Dict)
    cons = get(root, "consolidated_metadata", missing)
    (cons === missing || cons === nothing) && return true
    return false
end

function _walk_v3_metadata!(store::DirectoryStore, meta::Dict{String, Any}, prefix::String)
    for sub in Zarr.subdirs(store, prefix)
        subpath = _store_path(prefix, sub)
        zj = store[subpath, "zarr.json"]
        if zj !== nothing
            meta[subpath] = Zarr.JSON.parse(
                String(copy(zj)); dicttype = Dict{String, Any}
            )
        end
        _walk_v3_metadata!(store, meta, string(subpath, "/"))
    end
    return nothing
end

"""
    _synthetic_zmetadata(path) -> Union{Vector{UInt8}, Nothing}

Build consolidated metadata for a local Zarr v2 store that has no on-disk
`.zmetadata`. Returns `nothing` when the file already exists, the store is Zarr
v3 (root `zarr.json`), or the path is not a Zarr v2 group/array.
"""
function _synthetic_zmetadata(path::String)
    meta_path = joinpath(path, ".zmetadata")
    isfile(meta_path) && return nothing
    isfile(joinpath(path, "zarr.json")) && return nothing
    is_v2 = isfile(joinpath(path, ".zgroup")) || isfile(joinpath(path, ".zarray"))
    is_v2 || return nothing
    store = DirectoryStore(path)
    meta = Dict{String, Any}()
    Zarr.consolidate_metadata(store, meta, "")
    buf = IOBuffer()
    Zarr.JSON.print(buf, Dict("metadata" => meta, "zarr_consolidated_format" => 1), 4)
    return take!(buf)
end

"""
    _synthetic_root_zarr_json(path) -> Union{Vector{UInt8}, Nothing}

For Zarr v3 stores whose root `zarr.json` has `consolidated_metadata` null or
absent, build a response with inline consolidated metadata so HTTP clients can
discover the hierarchy. Returns `nothing` when not applicable.
"""
function _synthetic_root_zarr_json(path::String)
    root_file = joinpath(path, "zarr.json")
    isfile(root_file) || return nothing
    root = Zarr.JSON.parse(read(root_file, String); dicttype = Dict{String, Any})
    get(root, "zarr_format", 0) == 3 || return nothing
    _v3_consolidated_missing(root) || return nothing
    get(root, "node_type", "") == "group" || return nothing

    store = DirectoryStore(path)
    children = Dict{String, Any}()
    _walk_v3_metadata!(store, children, "")
    root["consolidated_metadata"] = Dict(
        "kind" => "inline",
        "must_understand" => false,
        "metadata" => children,
    )
    buf = IOBuffer()
    Zarr.JSON.print(buf, root, 4)
    return take!(buf)
end

"""
    serve_zarr(path; host="127.0.0.1")

Spin up a local HTTP server exposing a Zarr store at `path`.
Returns the URL string to pass to `browzarr(; store=...)`.

Unconsolidated Zarr v2 stores (`.zgroup` / `.zattrs` only) are served with a
synthesized `.zmetadata`. Unconsolidated Zarr v3 stores (`consolidated_metadata`
null in root `zarr.json`) are served with synthesized inline consolidation in
`zarr.json`.
"""
function serve_zarr(path::String; host::String = "127.0.0.1")
    path = abspath(path)
    synthetic_zmetadata = _synthetic_zmetadata(path)
    synthetic_zarr_json = _synthetic_root_zarr_json(path)
    !isnothing(synthetic_zmetadata) &&
        @info "Serving synthesized .zmetadata for unconsolidated Zarr v2 store" path
    !isnothing(synthetic_zarr_json) &&
        @info "Serving synthesized consolidated_metadata for unconsolidated Zarr v3 store" path

    server = Sockets.listen(Sockets.getaddrinfo(host), 0) # OS picks a free port
    _, port = getsockname(server)

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
            headers = [CORS_HEADERS..., "Content-Type" => "application/json"]
            req.method == "HEAD" && return HTTP.Response(200, headers)
            return HTTP.Response(200, headers, synthetic_zmetadata)
        end

        if rel == "zarr.json" && !isnothing(synthetic_zarr_json)
            headers = [CORS_HEADERS..., "Content-Type" => "application/json"]
            req.method == "HEAD" && return HTTP.Response(200, headers)
            return HTTP.Response(200, headers, synthetic_zarr_json)
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

    errormonitor(@async HTTP.serve(handler, host, port, server = server))
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
