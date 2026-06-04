module Browzarr
export browzarr

using LazyArtifacts
using HTTP
using Zarr, Sockets
using Zarr: DirectoryStore

# compat abstractions between HTTP 1.x and 2.x
const HTTP_V2 = pkgversion(HTTP) >= v"2.0"
const server_ = HTTP_V2 ? HTTP.Server : Sockets.TCPServer

function _serve!(handler, host, port; kwargs...)
    if HTTP_V2
        return HTTP.serve!(handler, host, port; kwargs...)
    else
        server = Sockets.listen(Sockets.getaddrinfo(host), port)
        return server, errormonitor(@async HTTP.serve(handler, host, port, server = server))
    end
end

_get_server(s) = HTTP_V2 ? s : first(s)

function _port(s)
    if HTTP_V2
        return HTTP.port(s)
    else
        _, port = getsockname(first(s))
        return port
    end
end

_forceclose(s) = HTTP_V2 ? HTTP.forceclose(s) : close(s)
_escapeuri(p) = HTTP_V2 ? HTTP.escapeuri(p) : HTTP.URIs.escapeuri(p)
_unescapeuri(p) = HTTP_V2 ? HTTP.unescapeuri(p) : HTTP.URIs.unescapeuri(p)
_uri(s) = HTTP_V2 ? HTTP.URI(s) : HTTP.URIs.URI(s)
_queryparams(uri) = HTTP_V2 ? HTTP.queryparams(uri) : HTTP.URIs.queryparams(uri)

struct BrowzarrServer
    server::server_
    host::String
    port::Int
    store::Union{String, Nothing}
    format::Union{String, Nothing}
end

struct ZarrServer
    server::server_
    host::String
    port::Int
    path::String
end

const SERVERS = Dict{Int, BrowzarrServer}()
const ZARR_SERVERS = Dict{Int, ZarrServer}()
const SERVERS_LOCK = ReentrantLock()

include("mimeTypes.jl")
include("serve_zarr.jl")
include("servers.jl")

function browzarr(; port::Union{Integer, Nothing} = nothing, open::Union{Bool, Nothing} = nothing, store::Union{String, ZarrServer, Nothing} = nothing)

    if store isa ZarrServer
        store = "http://$(store.host):$(store.port)"
    elseif store isa String && isdir(store)
        zarr_srv = serve_zarr(store)
        store = "http://$(zarr_srv.host):$(zarr_srv.port)"
        wait_for_server(store) || error("Zarr server failed to start at $store")
    end

    notebook = in_notebook()
    vscode = in_vscode()
    open_browser_flag = isnothing(open) ? !(notebook || vscode) : open

    srv = start_browzarr(; port, store)

    if notebook && !open_browser_flag
        display("text/html", browzarr_iframe(srv))
    elseif vscode && !open_browser_flag
        wait_for_server(srv.host, srv.port) || error("Browzarr server failed to start at $(srv.host):$(srv.port)")
        _display_vscode(srv)
    elseif open_browser_flag
        wait_for_server(srv.host, srv.port) || error("Browzarr server failed to start at $(srv.host):$(srv.port)")
        open_browser(srv)
        @info "Browzarr opened in browser" url = server_url(srv)
    end

    return srv
end

function Base.show(io::IO, srv::BrowzarrServer)
    color = get(io, :color, false)

    styled(c, s) = color ? "\e[$(c)m$(s)\e[0m" : string(s)
    key(s)   = styled("1;36", s)   # bold cyan
    str(s)   = styled("32", s)     # green
    num(s)   = styled("33", s)     # yellow
    sym(s)   = styled("38;5;208", s) # orange
    bold(s)  = styled("1",  s)
    
    print(io, bold("BrowzarrServer"), "(")
    print(io, key("host"), "=", str(srv.host), ", ")
    print(io, key("port"), "=", num(srv.port), ", ")
    print(io, key("store"), "=", sym(srv.store), ", ")
    print(io, key("format"), "=", sym(srv.format), ")")
end

function Base.show(io::IO, srv::ZarrServer)
    color = get(io, :color, false)
    styled(c, s) = color ? "\e[$(c)m$(s)\e[0m" : string(s)
    key(s)  = styled("1;36", s)      # bold cyan
    str(s)  = styled("32", s)        # green
    num(s)  = styled("33", s)        # yellow
    sym(s)  = styled("38;5;208", s)  # orange
    bold(s) = styled("1", s)
    print(io, bold("ZarrServer"), "(")
    print(io, key("host"), "=", str(srv.host), ", ")
    print(io, key("port"), "=", num(srv.port), ", ")
    print(io, key("path"), "=", sym(srv.path), ")")
end

end
