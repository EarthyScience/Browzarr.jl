using Pkg.Artifacts

next_out_dir = "/Users/lalonso/Documents/Browzarr/out"
artifact_toml = joinpath(@__DIR__, "Artifacts.toml")

browzarr_hash = artifact_hash("Browzarr", artifact_toml)

if browzarr_hash === nothing || !artifact_exists(browzarr_hash)
    browzarr_hash = create_artifact() do artifact_dir
        cp(next_out_dir, joinpath(artifact_dir, "app"); force = true)
    end

    bind_artifact!(artifact_toml, "Browzarr", browzarr_hash; force = true)
    @info "Artifact created" path = artifact_path(browzarr_hash)
else
    @info "Artifact already exists" path = artifact_path(browzarr_hash)
end
