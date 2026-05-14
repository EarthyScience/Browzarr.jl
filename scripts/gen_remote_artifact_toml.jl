using Downloads
using Inflate
using SHA
using Tar

"""
    npm_tarball_url(pkg::AbstractString; version::AbstractString = "latest")

Resolve the npm `dist.tarball` URL for `pkg` and `version`.

`version` may be `"latest"` or an explicit version string like `"0.3.1"`.
"""
function npm_tarball_url(pkg::AbstractString; version::AbstractString = "latest")
    meta_url = version == "latest" ?
        "https://registry.npmjs.org/$(pkg)/latest" :
        "https://registry.npmjs.org/$(pkg)/$(version)"

    json_path = Downloads.download(meta_url)
    json = read(json_path, String)

    # Match `dist.tarball` specifically (npm metadata JSON).
    # We must allow nested `{}` inside `dist` (e.g. `signatures`), so we use a DOTALL non-greedy match.
    #
    # NOTE: this is a raw regex string, so backslashes are not double-escaped.
    m = match(r"(?s)\"dist\"\s*:\s*\{.*?\"tarball\"\s*:\s*\"([^\"]+)\"", json)
    m === nothing && error("Could not find dist.tarball in npm metadata: $meta_url")
    return String(m.captures[1])
end

"""
Compute `(sha256_hex, tree_hash_bytes)` for a .tar.gz/.tgz file at `url`.

- `sha256_hex` hashes the compressed bytes.
- `tree_hash_bytes` hashes the unpacked tarball tree (what Artifacts.toml stores as `git-tree-sha1`).
"""
function artifact_hashes_from_url(url::AbstractString)
    path = Downloads.download(url)
    sha256_hex = bytes2hex(open(sha256, path))
    tree_hash_bytes = Tar.tree_hash(IOBuffer(inflate_gzip(path)))
    return sha256_hex, tree_hash_bytes
end

function gen_remote_artifact_toml()
    pkg = get(ENV, "BROWZARR_NPM_PKG", "browzarr")
    version = get(ENV, "BROWZARR_NPM_VERSION", "latest")
    name = get(ENV, "BROWZARR_ARTIFACT_NAME", "Browzarr")

    # Optional: bypass npm metadata resolution entirely.
    tarball = get(ENV, "BROWZARR_NPM_TARBALL_URL", "")
    if isempty(tarball)
        tarball = npm_tarball_url(pkg; version)
    end
    sha256_hex, tree_hash_bytes = artifact_hashes_from_url(tarball)

    println("[", name, "]")
    println("git-tree-sha1 = \"", tree_hash_bytes, "\"")
    println("lazy = true")
    println()
    println("  [[", name, ".download]]")
    println("  url = \"", tarball, "\"")
    return println("  sha256 = \"", sha256_hex, "\"")
end

gen_remote_artifact_toml()
