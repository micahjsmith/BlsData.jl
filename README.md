# BlsData
[![Build Status](https://travis-ci.org/micahjsmith/BlsData.jl.svg?branch=master)](https://travis-ci.org/micahjsmith/BlsData.jl)

A basic Julia interface to pull data from the Bureau of Labor Statistics using
their Public API [here](https://www.bls.gov/developers/home.htm).

Register a Public Data API account on the BLS website
[here](https://data.bls.gov/registrationEngine/) to receive an API key. Then, take advantage
of the increased daily query limit and other features.

## Usage

```
using BlsData
b = Bls()
one_series = get_data(b, "LNS11000000")
```

## Setup

```julia
julia> Pkg.add("BlsData")
```

## Functionality

### The `Bls` type
The `Bls` type represents a connection to the BLS API.

Looks for a registration key in the file `~/.blsdatarc`, or omits the registration key otherwise.
```
b = Bls()
```

Specify a registration key directly.
```
b = Bls(key="0123456789abcdef0123456789abcdef")
```

Get and set fields.
```
api_url(b::Bls)                          # Get the base URL used to connect to the server
set_api_url!(b::Bls, url::AbstractString) # Set the base URL used to connect to the server
api_key(b::Bls)                          # Get the API key
api_version(b::Bls)                      # Get the API version (v1 or v2) used
requests_made(b::Bls)                    # Get the number of requests made today
requests_remaining(b::Bls)               # Get the number of requests remaining today
```

Note that the requests made/remaining are calculated based on the lifetime of this object
only and would not include those made in a distinct Julia session.

### The `BlsSeries` type
The `BlsSeries` type contains the data in a query response.

```
id(s::BlsSeries)                         # Get series ID
series(s::BlsSeries)                     # Get data as DataFrame
catalog(s::BlsSeries)                    # Get joined catalog strings
```

### Query data
Request one or multiple series from the BLS API.
```
get_data(b, series [; startyear, endyear, catalog])
```

* `b`: A `Bls` connection
* `series`: A string, or array of strings, identifying the time series
* `startyear`: A four-digit year identifying the start of the data request. Defaults to
    9 or 19 years before `endyear`, depending on the API version used.
* `endyear`: A four-digit year identifying the end of the data request. Defaults to
    9 or 19 years after `endyear`, depending on the API version used; or, this year, if
    neither `startyear` nor `endyear` is provided.
* `catalog`: Whether to return any available metadata about the series. Defaults to `false`.

A `BlsSeries`, or an array of `BlsSeries`.

## Finding data series
The BLS mnemonics are somewhat obscure. You can attempt to build them programmatically by
consulting [this page](https://www.bls.gov/help/hlpforma.htm).

## Notes
The BLS API provides the following limits on requests:

|                        | v2 (registered) | v1 (unregistered) |
| ---                    | ---             | ---               |
| Daily query limit      | 500             | 25                |
| Years per query limit  | 20              | 10                |
| Series per query limit | 50              | 25                |

`BlsData.jl` addresses these limits as follows:
- track daily query limit for reference
- make multiple requests under the hood, and concatenate results, for date ranges longer
  than limit
- [NOT IMPLEMENTED] make multiple requests under the hood, and concatenate results, for lists of series longer
  than limit
