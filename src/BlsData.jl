isdefined(Base, :__precompile__) && __precompile__()

module BlsData

using Compat
using DataFrames

import Dates
import JSON
import HttpCommon
import HTTP
import Printf: @printf

export
    # Bls type
    Bls, get_api_url, set_api_url!, get_api_key, get_api_version, requests_made,
        requests_remaining,
    # BlsSeries type
    BlsSeries,
    # get data
    get_data

const DEFAULT_API_URL            = "https://api.bls.gov/publicAPI/v2/timeseries/data/"
const API_KEY_LENGTH             = 32
const BLS_RESPONSE_SUCCESS       = "REQUEST_SUCCEEDED"
const BLS_RESPONSE_CATALOG_FAIL1 = "unable to get catalog data"
const BLS_RESPONSE_CATALOG_FAIL2 = "catalog has been disabled"

# See https://www.bls.gov/developers/api_faqs.htm for status code reasons.
const BLS_STATUS_CODE_REASONS    = Dict(400 => "Your request did not follow the correct syntax.",
                                        401 => "You are not authorized to make this request.",
                                        404 => "Your request was not found and/or does not exist.",
                                        429 => "You have made too many requests.",
                                        500 => "The server has encountered an unexpected condition, and the request cannot be completed.")

const LIMIT_DAILY_QUERY          = [25, 500]
const LIMIT_SERIES_PER_QUERY     = [25, 50]
const LIMIT_YEARS_PER_QUERY      = [10, 20]

# Debugging info
const DEBUG                      = true
function log_error(url, payload, headers, response)
    try
        open(joinpath(homedir(), ".blsdatajl.log"), "a") do f
            println(f, "--------")
            println(f, "Request")
            println(f, url)
            println(f, JSON.json(payload))
            println(f, headers)
            println(f, "Response")
            println(f, String(response))
        end
    catch e
        # pass
    end
end

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
* `set_api_url!(b::Bls, url::AbstractString)`: Set the base URL used to connect to the server
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
mutable struct Bls
    url::AbstractString
    key::AbstractString
    n_requests::Int16
    t_created::Dates.DateTime
end
function Bls(key="")
    if isempty(key)
        try
            key = open(joinpath(homedir(),".blsdatarc"), "r") do f
                read(f, String)
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
    t_created = Dates.now()
    Bls(url, key, n_requests, t_created)
end

get_api_url(b::Bls) = b.url
set_api_url!(b::Bls, url::AbstractString) = setfield!(b, :url, url)
get_api_key(b::Bls) = b.key
get_api_version(b::Bls) = 1 + !isempty(get_api_key(b))
requests_made(b::Bls) = b.n_requests
requests_remaining(b::Bls) = LIMIT_DAILY_QUERY[get_api_version(b)] - requests_made(b)

function increment_requests!(b::Bls)
    # Reset request if we are in a new day!
    if Dates.day(Dates.now()) ≠ Dates.day(b.t_created)
        b.t_created = Dates.now()
        b.n_requests = 0
    end

    b.n_requests += 1
end

function Base.show(io::IO, b::Bls)
    @printf io "BLS API v%d Connection\n"   get_api_version(b)
    @printf io "\turl: %s\n"                get_api_url(b)
    @printf io "\tkey: %s\n"                get_api_key(b)
    @printf io "\trequests made (this session): %d\n"       requests_made(b)
    @printf io "\trequests remaining (this session): ≤%d\n" requests_remaining(b)
end

"""
A time series with metadata returned from a `get_data` call.

For a series `s`, access fields with
```
s.id
s.data
s.catalog
```
"""
mutable struct BlsSeries
    id::AbstractString
    data::DataFrame
    catalog::AbstractString
end

function Base.show(io::IO, s::BlsSeries)
    @printf io "BlsSeries\n"
    @printf io "\tid: %s\n" s.id
    @printf io "\tdata: %dx%d DataFrame with columns %s\n" size(s.data)...  names(s.data)
    @printf io "\tcatalog: %s\n" s.catalog
end

EMPTY_RESPONSE() = BlsSeries("",DataFrame(),"")
function Base.isempty(s::BlsSeries)
    for name in propertynames(s)
        if !isempty(getproperty(s, name))
            return false
        end
    end
    return true
end

# deprecated
export
    api_url, api_key, api_version,
    id, series, catalog
@deprecate api_url(b::Bls) get_api_url(b)
@deprecate api_key(b::Bls) get_api_key(b)
@deprecate api_version(b::Bls) get_api_version(b)
@deprecate id(s::BlsSeries) getfield(s, :id)
@deprecate series(s::BlsSeries) getfield(s, :data)
@deprecate catalog(s::BlsSeries) getfield(s, :catalog)

include("get_data.jl")
end # module
