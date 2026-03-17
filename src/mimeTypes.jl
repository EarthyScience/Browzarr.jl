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

function static_handler(dir::String)
    return function (req)
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
