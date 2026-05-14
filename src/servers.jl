function start_browzarr(; port::Int = 3000, host::String = "127.0.0.1", store::Union{String, Nothing} = nothing)
    return lock(SERVERS_LOCK) do
        haskey(SERVERS, port) && error("Server already running on port $port")
        # The `browzarr` npm tarball unpacks under `package/` and the static build lives in `out/`.
        dir = joinpath(artifact"Browzarr", "package", "out")
        handler = static_handler(dir, store)
        server = HTTP.serve!(handler, host, port)

        srv = BrowzarrServer(server, host, port, store, detect_format(store))
        SERVERS[port] = srv

        atexit(
            () -> lock(SERVERS_LOCK) do
                port in keys(SERVERS) && stop!(SERVERS[port])
            end
        )

        return srv
    end
end

function detect_format(store::Union{String, Nothing})
    isnothing(store) && return nothing
    return endswith(store, ".nc") || endswith(store, ".nc4") ? "nc" : nothing
end

function stop!(srv::BrowzarrServer)
    close(srv.server)
    return @info "Browzarr server stopped" port = srv.port
end

function stop!(port::Int)
    srv = lock(SERVERS_LOCK) do
        get(SERVERS, port, nothing)
    end
    srv === nothing && error("No server running on port $port")
    stop!(srv)
    return lock(SERVERS_LOCK) do
        pop!(SERVERS, port, nothing)
    end
end

function stop_all!()
    servers = lock(SERVERS_LOCK) do
        s = collect(values(SERVERS))
        empty!(SERVERS)
        s
    end
    for srv in servers
        try
            stop!(srv)
        catch e
            @warn "Failed to stop server" port = srv.port exception = e
        end
    end
    return @info "All Browzarr servers stopped"
end

running_servers() = lock(SERVERS_LOCK) do
    collect(values(SERVERS))
end

get_server(port::Int) = lock(SERVERS_LOCK) do
    get(SERVERS, port, nothing)
end

function launch_browzarr(url::String)
    if Sys.isapple()
        tryrun(`open $url`) && return true
    elseif Sys.iswindows()
        tryrun(`powershell.exe start $url`) && return true
    elseif Sys.islinux()
        tryrun(`xdg-open $url`) && return true
        tryrun(`gnome-open $url`) && return true
    end
    tryrun(`python -mwebbrowser $url`) && return true
    tryrun(`python3 -mwebbrowser $url`) && return true
    @warn "Can't find a way to open a browser, open $url manually!"
    return false
end

tryrun(cmd::Cmd) = try
    success(cmd)
catch
    false
end

function server_url(srv::BrowzarrServer)
    base = "http://$(srv.host):$(srv.port)"
    isnothing(srv.store) && return base
    store = startswith(srv.store, "http") ? srv.store : HTTP.URIs.escapeuri(srv.store)
    url = "$base/?store=$store"
    !isnothing(srv.format) && (url *= "&format=$(srv.format)")
    return url
end

function open_browser(srv::BrowzarrServer)
    url = server_url(srv)
    launch_browzarr(url)
    return url
end

struct BrowzarrIframe
    html::String
end

function Base.show(io::IO, ::MIME"juliavscode/html", iframe::BrowzarrIframe)
    return print(io, iframe.html)
end
Base.showable(::MIME"juliavscode/html", ::BrowzarrIframe) = true

function browzarr_iframe(srv::BrowzarrServer; width = "100%", height = "600px")
    url = server_url(srv)
    html = """<iframe src="$url" width="$width" height="$height" frameborder="0"></iframe>"""
    return BrowzarrIframe(html)
end

function in_notebook()
    # Jupyter
    if isdefined(Main, :IJulia) && Main.IJulia.inited
        return true
    end
    # Pluto
    if isdefined(Main, :PlutoRunner)
        return true
    end
    return false
end

function in_vscode()
    return isdefined(Main, :VSCodeServer)
end

function _display_vscode(srv::BrowzarrServer)
    url = server_url(srv)
    iframe = browzarr_iframe(srv)
    display(MIME("juliavscode/html"), iframe)
    return @info "Browzarr displayed in VS Code plot pane" url = url
end

function wait_for_server(host, port; timeout = 10.0)
    deadline = time() + timeout
    while time() < deadline
        try
            close(HTTP.connect(host, port))
            return true
        catch
            sleep(0.05)
        end
    end
    @warn "Server on $host:$port did not become ready in time"
    return false
end

function wait_for_server(url::String; timeout = 10.0)
    uri = HTTP.URIs.URI(url)
    host = uri.host
    port = parse(Int, uri.port)
    deadline = time() + timeout
    while time() < deadline
        try
            HTTP.get("http://$host:$port"; readtimeout = 1, retry = false, status_exception = false)
            return true
        catch
            sleep(0.05)
        end
    end
    @warn "Server did not become ready in time" url
    return false
end
