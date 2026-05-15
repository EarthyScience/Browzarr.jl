const known_mimetypes = Dict(
    "html" => "text/html",
    "css" => "text/css",
    "js" => "application/javascript",
    "json" => "application/json",
    "png" => "image/png",
    "jpg" => "image/jpeg",
    "svg" => "image/svg+xml",
    "ico" => "image/x-icon",
    "woff2" => "font/woff2",
    "wasm" => "application/wasm",
    "nc" => "application/x-netcdf",
    "nc3" => "application/x-netcdf",
    "nc4" => "application/x-netcdf",
    "ncdf" => "application/x-netcdf",
)

function extension(f)
    return last(splitext(f))[2:end]
end

function file_mimetype(f)
    return ext_to_mimetype(extension(f))
end

function ext_to_mimetype(ext)
    return get(known_mimetypes, ext, "application/octet-stream")
end

"""
   file_handler(store::Union{String, Nothing}, req)

Serve a NetCDF file from `store` in response to an HTTP request `req`, supporting range requests for efficient streaming.
"""
function file_handler(store::Union{String, Nothing}, req)
    isnothing(store) && return HTTP.Response(400, "No store configured")
    uri = HTTP.URIs.URI(req.target)
    path = get(HTTP.URIs.queryparams(uri), "path", nothing)

    isnothing(path) && return HTTP.Response(400, "Missing path")
    path != store && return HTTP.Response(403, "Forbidden")
    !isfile(path) && return HTTP.Response(404, "File not found: $path")

    filesize = stat(path).size
    headers = [
        "Content-Type" => file_mimetype(path),
        "Content-Length" => string(filesize),
        "Accept-Ranges" => "bytes",
        "Access-Control-Allow-Origin" => "*",
    ]

    req.method == "HEAD" && return HTTP.Response(200, headers)

    range_header = HTTP.header(req, "Range", "")
    if !isempty(range_header)
        m = match(r"bytes=(\d+)-(\d*)", range_header)
        if !isnothing(m)
            start = parse(Int, m[1])
            stop = isempty(m[2]) ? filesize - 1 : parse(Int, m[2])
            len = stop - start + 1
            body = open(path, "r") do io
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

    return HTTP.Response(200, headers; body = open(path, "r"))
end

"""
    static_handler(dir::String, store::Union{String, Nothing})

Create an HTTP handler that serves static files from `dir`, and uses `file_handler` to serve the NetCDF file specified by `store` when requests are made to the `/file` endpoint.
"""
function static_handler(dir::String, store::Union{String, Nothing})
    return function (req)
        startswith(req.target, "/file") && return file_handler(store, req)

        path = split(req.target, "?")[1]
        path = lstrip(path, '/')
        isempty(path) && (path = "index.html")

        filepath = joinpath(dir, path)
        !isfile(filepath) && (filepath = filepath * ".html")

        real = normpath(filepath)
        startswith(real, dir) || return HTTP.Response(403, "Forbidden")

        if isfile(real)
            return HTTP.Response(
                200,
                ["Content-Type" => file_mimetype(real)],
                read(real)
            )
        else
            return HTTP.Response(404, "Not found: $(path)")
        end
    end
end
