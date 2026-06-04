## Browzarr.jl
> The Julia bridge for launching [Browzarr](https://github.com/EarthyScience/Browzarr) - a browser-based visualization framework for exploring and analyzing Zarr and NetCDF datasets.

**Try it now at [browzarr.io](https://browzarr.io)**

<div align="center">

[![][docs-dev-img]][docs-dev-url]
[![Zarr](https://img.shields.io/badge/Zarr-Compatible-e34b75)](https://zarr.dev/)
[![NetCDF4](https://img.shields.io/badge/NetCDF4-Compatible-008B8B)](https://www.unidata.ucar.edu/software/netcdf/)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://github.com/EarthyScience/Browzarr.jl/blob/4ab08317c9932a9422cda506d967bf76b1b06920/LICENSE)

</div>

[docs-dev-img]: https://img.shields.io/badge/docs-%20tutorial-orange?style=round-square
[docs-dev-url]: https://browzarr.io/docs/

---

> [!NOTE]
> This package is solely responsible for launching the Browzarr app from Julia. All visualization and data interaction happens in the browser.

### Installation

```julia
using Pkg; Pkg.add("Browzarr")
```

or install the `main` branch via:

```julia
using Pkg; Pkg.add(url="https://github.com/EarthyScience/Browzarr.jl", rev="main")
```

### Usage

Launch with a local file, a remote store, or no arguments to get started:

```julia
using Browzarr

browzarr()                                                # default (any available port)
browzarr(; port=3000)                                     # custom port
browzarr(; store="/absolute/path/to/file.nc")             # local file
browzarr(; store="/absolute/path/to/zarr_file.zarr")      # local zarr directory
browzarr(; store="https://s3.bucket.de:67/misc/out.zarr") # remote Zarr store
```

List all `BrowzarrServer`s

```julia
Browzarr.running_servers()
```

To stop all running servers:

```julia
Browzarr.stop_all!()
```

To stop a server on a specific port:

```julia
Browzarr.stop!(3000)
```

### Setup a Local Zarr Server

You can pass directly the path to your local `zarr` directory
```julia
using Browzarr
browzarr(; store="/absolute/path/to/zarr_file.zarr")      # local zarr directory
```

or setup the server in advance and then pass that

```julia
using Browzarr
store = Browzarr.serve_zarr("/absolute/path/to/zarr_file.zarr")
# now launch it!
browzarr(; store=store)
```

List all `ZarrServer`s

```julia
Browzarr.running_zarr_servers()
```

To stop all running `ZarrServer`s:

```julia
Browzarr.stop_all_zarr!()
```

To stop a `ZarrServer` on a specific port:

```julia
Browzarr.stop_zarr!(16180)
```

---
