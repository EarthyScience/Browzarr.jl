module Browzarr
export browzarr

using LazyArtifacts
using HTTP
using Zarr, Sockets

struct BrowzarrServer
    server::HTTP.Servers.Server
    host::String
    port::Int
    store::Union{String, Nothing}
    format::Union{String, Nothing}
end

const SERVERS = Dict{Int, BrowzarrServer}()
const ZARR_SERVERS = Dict{Int, Sockets.TCPServer}()
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

end
