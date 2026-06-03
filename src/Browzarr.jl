module Browzarr
export browzarr

using LazyArtifacts
using HTTP
using HTTP: Server, forceclose
using Zarr
using Zarr: DirectoryStore

struct BrowzarrServer
    server::Server
    host::String
    port::Int
    store::Union{String, Nothing}
    format::Union{String, Nothing}
end

const SERVERS = Dict{Int, BrowzarrServer}()
const ZARR_SERVERS = Dict{Int, Server}()
const SERVERS_LOCK = ReentrantLock()

include("mimeTypes.jl")
include("serve_zarr.jl")
include("servers.jl")

function browzarr(; port::Union{Integer, Nothing} = nothing, open::Union{Bool, Nothing} = nothing, store::Union{String, Nothing} = nothing)

    if !isnothing(store) && isdir(store)
        store = serve_zarr(store)
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

end
