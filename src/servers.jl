function start_browzarr(; port::Int = 3000, host::String = "127.0.0.1")
    return lock(SERVERS_LOCK) do
        haskey(SERVERS, port) && error("Server already running on port $port")
        dir = joinpath(artifact"Browzarr", "app")
        handler = static_handler(dir)
        task = @async HTTP.serve(handler, host, port)

        srv = BrowzarrServer(task, host, port)
        SERVERS[port] = srv

        atexit(
            () -> lock(SERVERS_LOCK) do
                port in keys(SERVERS) && stop!(SERVERS[port])
            end
        )

        return srv
    end
end

function stop!(srv::BrowzarrServer)
    if !istaskdone(srv.task)
        try
            Base.throwto(srv.task, InterruptException())
            wait(srv.task)
        catch e
            e isa InterruptException && return
            e isa TaskFailedException &&
                e.task.exception isa InterruptException && return
            rethrow(e)
        end
    end
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

function open_browser(srv::BrowzarrServer)
    url = "http://$(srv.host):$(srv.port)"
    launch_browzarr(url)
    return url
end

struct BrowzarrIframe
    html::String
end

function Base.show(io::IO, ::MIME"text/html", iframe::BrowzarrIframe)
    return print(io, iframe.html)
end

function browzarr_iframe(srv::BrowzarrServer; width = "100%", height = "600px")
    url = "http://$(srv.host):$(srv.port)"
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
    # VS Code and Cursor (Cursor embeds VS Code's Julia extension)
    if isdefined(Main, :VSCodeServer)
        return true
    end
    return false
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
