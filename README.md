# BLS
[![Build Status](https://travis-ci.org/micahjsmith/BlsData.jl.svg?branch=master)](https://travis-ci.org/micahjsmith/BlsData.jl)

A basic Julia interface to pull data from the Bureau of Labor Statistics using
their Public API [here](http://www.bls.gov/developers/home.htm).

Register a Public Data API account on the BLS website
[here](http://data.bls.gov/registrationEngine/) to receive an API key. Then, take advantage
of the increased daily query limit and other features.

## Usage

Basic usage:
```
using BlsData
b = BLS()
one_series = get_data(b, "LNS11000000")
one_series_catalog = get_data(b, "
multiple_series = get_data(b, ["LNS11000000", "PRS85006092"])
```

```
using BlsData
b = BLS(key="MY API KEY")
data = get_data(b, "PRS85006092"; catalog=true)
```

## Setup

Simply run
```julia
julia> Pkg.clone("https://github.com/micahjsmith/BlsData.jl.git")
```

## Functionality

### The `Bls` type
The `Bls` type represents a connection to the BLS API.

Look for a registration key in the file `~/.blsdatarc`, or will omit the
registration key otherwise.
```
b = Bls()
```

Specify a registration key directly.
```
b = Bls(key="abc123")
```

Get and set fields.
```
api_url(b::Bls)                          # Get the base URL used to connect to the server
set_api_url(b::Bls, url::AbstractString) # Set the base URL used to connect to the server
api_key(b::Bls)                          # Get the API key
api_version(b::Bls)                      # Get the API version (v1 or v2) used
requests_made(b::Bls)                    # Get the number of requests made today
requests_remaining(b::Bls)               # Get the number of requests remaining today
```

Note that the requests made/remaining are calculated based on the lifetime of this object
only and would not include those made in a distinct Julia session.

### The `BlsSeries` type
The `BlsSeries` type contains the data in a query response.

Get fields.
```
id(s::BlsSeries)                         # Returns AbstractString
series(s::BlsSeries)                     # Returns DataFrame
catalog(s::BlsSeries)                    # Returns one or array of AbstractString
```

### Query data
Request one or multiple series from the BLS API.
```
get_data{T<:AbstractString}(b::Bls, series::Union{T,Array{T,1}};
               startyear::Int = Dates.year(now()) - QUERY_LIMIT + 1,
               endyear::Int   = Dates.year(now()),
               catalog::Bool  = false)
```

Argument detail.
* `b`: A Bls connection
* `series`: A string, or array of strings, identifying the time series
* `startyear`: A four-digit year identifying the start of the data request
* `endyear`: A four-digit year identifying the end of the data request
* `catalog`: Whether to return any available metadata about the series

Returns an object, or array of objects, of type `BlsSeries`.

## Finding data series
The BLS mnemonics are somewhat obscure. You can attempt to build them programmatically by
consulting [this page](http://www.bls.gov/help/hlpforma.htm).

## Notes
