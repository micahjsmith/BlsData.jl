isdefined(Base, :__precompile__) && __precompile__()

module BlsData

using Requests
using DataFrames
import Requests: post
import JSON

export Bls, api_url, set_api_url!, api_key, api_version, requests_made, requests_remaining
export BlsSeries, id, series, catalog
export get_data

const DEFAULT_API_URL            = "http://api.bls.gov/publicAPI/v2/timeseries/data/"
const API_KEY_LENGTH             = 32
const BLS_RESPONSE_SUCCESS       = "REQUEST_SUCCEEDED"
const BLS_RESPONSE_CATALOG_FAIL1 = "unable to get catalog data"
const BLS_RESPONSE_CATALOG_FAIL2 = "catalog has been disabled"
const LIMIT_DAILY_QUERY          = [25, 500]
const LIMIT_SERIES_PER_QUERY     = [25, 50]
const LIMIT_YEARS_PER_QUERY      = [10, 20]
const LIMIT_YEARS_PER_QUERY_ADJ  = LIMIT_DAILY_QUERY .- 1

"""
A connection to the BLS API.

Constructors
------------
* `Bls()`
* `Bls(key::AbstractString)`

Arguments
---------
* `key`: Registration key provided by the BLS.

Methods
-------
* `api_url(b::Bls)`: Get the base URL used to connect to the server
* `set_api_url(b::Bls, url::AbstractString)`: Set the base URL used to connect to the server
* `api_key(b::Bls)`: Get the API key
* `api_version(b::Bls)`: Get the API version (v1 or v2) used
* `requests_made(b::Bls)`: Get the number of requests made today
* `requests_remaining(b::Bls)`: Get the number of requests remaining today

Notes
-----
* A default API key can be specified in a ~/.blsdatarc file.
* A valid registration key increases the allowable number of requests per day as well making
  catalog metadata available.

"""
type Bls
    url::AbstractString
    key::AbstractString
    n_requests::Int16
    t_created::DateTime
end
function Bls(key="")
    if isempty(key)
        try
            open(joinpath(homedir(),".blsdatarc"), "r") do f
                key = readall(f)
            end
            key = rstrip(key)
            @printf "API key loaded.\n"
            # Key validation
            if length(key) > API_KEY_LENGTH
                key = key[1:API_KEY_LENGTH]
                warn("Key too long. First ", API_KEY_LENGTH, " chars used.")
            end
            if !isxdigit(key)
                error("Invalid BLS API key: ", key)
            end
        catch err
        end

    end

    url = DEFAULT_API_URL
    n_requests = 0
    t_created = now()
    Bls(url, key, n_requests, t_created)
end
api_url(b::Bls) = b.url
set_api_url!(b::Bls, url::AbstractString) = setfield!(b, :url, url)
api_key(b::Bls) = b.key
api_version(b::Bls) = 1 + !isempty(api_key(b))
requests_made(b::Bls) = b.n_requests
requests_remaining(b::Bls) = LIMIT_DAILY_QUERY[api_version(b)] - requests_made(b)
function increment_requests(b::Bls)
    # Reset request if we are in a new day!
    if Dates.day(now()) ≠ Dates.day(b.t_created)
        b.t_created = now()
        b.n_requests = 0
    end

    b.n_requests += 1
end

function Base.show(io::IO, b::Bls)
    @printf io "BLS API v%d Connection\n"   api_version(b)
    @printf io "\turl: %s\n"                api_url(b)
    @printf io "\tkey: %s\n"                api_key(b)
    @printf io "\trequests made (this connection): %d\n"      requests_made(b)
    @printf io "\trequests remaining (this connection): %d\n" requests_remaining(b)
end

"""
A time series with metadata returned from a `get_data` call.

Prefer to access fields with
```
id(s::BlsSeries)
series(s::BlsSeries)
catalog(s::BlsSeries)
```
"""
type BlsSeries
    id::AbstractString
    df::DataFrame
    catalog::AbstractString
end
id(s::BlsSeries)      = s.id
series(s::BlsSeries)  = s.df
catalog(s::BlsSeries) = s.catalog

function Base.show(io::IO, s::BlsSeries)
    @printf io "BlsSeries\n"
    @printf io "\tid: %s\n" id(s)
    @printf io "\tseries: %dx%d DataFrame with columns %s\n" size(series(s))...  names(series(s)) 
    @printf io "\tcatalog: %s\n" catalog(s)
end

EMPTY_RESPONSE() = BlsSeries("",DataFrame(),"")
function Base.isempty(s::BlsSeries)
    return id(s) == "" &&
        series(s) == DataFrame() &&
        catalog(s) == ""
end

include("get_data.jl")
end # module
