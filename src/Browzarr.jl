module Browzarr
export browzarr

using Pkg.Artifacts
using HTTP

struct BrowzarrServer
    server::HTTP.Servers.Server
    host::String
    port::Int
    store::Union{String, Nothing}
    format::Union{String, Nothing}
end

const SERVERS = Dict{Int, BrowzarrServer}()
const SERVERS_LOCK = ReentrantLock()
const DEFAULT_PORT = 3000
const DEFAULT_AUTOPORT = true   # automatically pick next port if current in use

include("mimeTypes.jl")
include("servers.jl")

function browzarr(;
    port::Integer = DEFAULT_PORT,
    autoport::Bool = DEFAULT_AUTOPORT,
    open::Union{Bool, Nothing} = nothing,
    store::Union{String, Nothing} = nothing
)
    notebook = in_notebook()
    vscode = in_vscode()
    open_browser_flag = isnothing(open) ? !(notebook || vscode) : open

    srv = start_browzarr(; port, autoport, store)

    if notebook && !open_browser_flag
        display("text/html", browzarr_iframe(srv))
    elseif vscode && !open_browser_flag
        wait_for_server(srv.host, srv.port)
        _display_vscode(srv)
    elseif open_browser_flag
        wait_for_server(srv.host, srv.port)
        open_browser(srv)
        @info "Browzarr opened in browser" url = server_url(srv)
    end

    return srv
end

end
