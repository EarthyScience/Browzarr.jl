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

Browzarr.jl is not yet registered. Install the main branch via:

```julia
using Pkg; Pkg.add(url="https://github.com/EarthyScience/Browzarr.jl", rev="main")
```

### Usage

Launch with a local file, a remote store, or no arguments to get started:

```julia
using Browzarr

browzarr()                                                # default (port 8080)
browzarr(; port=3000)                                     # custom port
browzarr(; store="/path/to/file.nc")                      # local file
browzarr(; store="https://s3.bucket.de:67/misc/out.zarr") # remote Zarr store
```

To stop all running servers:

```julia
Browzarr.stop_all!()
```

To stop a server on a specific port:

```julia
Browzarr.stop!(3000)
```
