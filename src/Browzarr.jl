module Browzarr
export browzarr

using Pkg.Artifacts
using HTTP

struct BrowzarrServer
    task::Task
    host::String
    port::Int
    store::Union{String, Nothing}
    format::Union{String, Nothing}
end

const SERVERS = Dict{Int, BrowzarrServer}()
const SERVERS_LOCK = ReentrantLock()

include("mimeTypes.jl")
include("servers.jl")

function browzarr(; port::Int = 3000, open::Union{Bool, Nothing} = nothing, store::Union{String, Nothing} = nothing)
    notebook = in_notebook()
    open_browser_flag = isnothing(open) ? !notebook : open
    srv = start_browzarr(; port, store)

    if notebook && !open_browser_flag
        display("text/html", browzarr_iframe(srv))
    elseif open_browser_flag
        wait_for_server(srv.host, srv.port)
        open_browser(srv)
        @info "Browzarr opened in browser" url = server_url(srv)
    end

    return srv
end

end
