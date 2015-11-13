isdefined(Base, :__precompile__) && __precompile__()

module BlsData

using Requests
using DataFrames
import Requests: post
import JSON

export Bls, api_url, set_api_url!, api_key, api_version, requests_made, requests_remaining
export get_data
export BlsSeries, id, series, catalog

const DEFAULT_API_URL            = "http://api.bls.gov/publicAPI/v2/timeseries/data/"
const API_KEY_LENGTH             = 32
const BLS_RESPONSE_SUCCESS       = "REQUEST_SUCCEEDED"
const BLS_RESPONSE_CATALOG_FAIL1 = "unable to get catalog data"
const BLS_RESPONSE_CATALOG_FAIL2 = "catalog has been disabled"
const LIMIT_DAILY_QUERY          = [25, 500]
const LIMIT_SERIES_PER_QUERY     = [25, 50]
const LIMIT_YEARS_PER_QUERY      = [10, 20]

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
data(s::BlsSeries)
catalog(s::BlsSeries)
```
"""
type BlsSeries
    id::AbstractString
    df::DataFrame
    catalog::Array{AbstractString,1}
end
EMPTY_RESPONSE() = BlsSeries("",DataFrame(),[""])
id(s::BlsSeries)      = s.id
data(s::BlsSeries)    = s.df
catalog(s::BlsSeries) = s.catalog

"""
```
get_data{T<:AbstractString}(b::Bls, series::T;
               startyear::Int=Dates.year(now())-9,
               endyear::Int=Dates.year(now()),
               catalog::Bool=false)
```
```
get_data{T<:AbstractString}(b::Bls, series::Array{T,1};
               startyear::Int=Dates.year(now())-9,
               endyear::Int=Dates.year(now()),
               catalog::Bool=false)
```
Request one or multiple series from the BLS API.

Arguments
---------
* `b`: A Bls connection
* `series`: A string, or array of strings, identifying the time series
* `startyear`: A four-digit year identifying the start of the data request
* `endyear`: A four-digit year identifying the end of the data request
* `catalog`: Whether to return any available metadata about the series

Returns
-------
An object, or array of objects, of type BlsSeries

Notes
-----
The BLS truncates any requests for data for a period longer than 20 years (or 10 years
without a registration key).
"""
function get_data{T<:AbstractString}(b::Bls, series::T;
               startyear::Int = Dates.year(now()) - LIMIT_YEARS_PER_QUERY[api_version(b)]-1,
               endyear::Int = Dates.year(now()),
               catalog::Bool = false)
    return get_data(b, [series]; startyear=startyear, endyear=endyear, catalog=catalog)[1]
end
function get_data{T<:AbstractString}(b::Bls, series::Array{T, 1};
               startyear::Int = Dates.year(now()) - LIMIT_YEARS_PER_QUERY[api_version(b)]-1,
               endyear::Int = Dates.year(now()),
               catalog::Bool = false)

    # Ensure requests remaining
    if requests_remaining(b) <= 0
        warn("No queries remaining today. Try again tomorrow.")
        return [EMPTY_RESPONSE() for i in 1:n_series]
    end

    n_series = length(series)

    # Setup payload
    headers = Dict("Content-Type" => "application/json")
    json    = Dict("seriesid"     => series,
                   "startyear"    => startyear,
                   "endyear"      => endyear,
                   "catalog"      => catalog)

    url     = api_url(b);
    key     = api_key(b);

    if !isempty(key)
        json["registrationKey"] = key
    end

    # Submit POST request to BLS
    response = post(url; json=json, headers=headers)
    increment_requests(b)
    response_json = Requests.json(response)

    # Response okay?
    if response_json["status"] ≠ BLS_RESPONSE_SUCCESS
        warn("Request failed with message '", response_json["status"], "'")

        # Return empty response for each series
        return [EMPTY_RESPONSE() for i in 1:n_series]
    end

    # Catalog okay?
    catalog_okay = false
    if catalog &&
        !isempty(response_json["message"]) &&
        !isempty(find(s->contains(s, BLS_RESPONSE_CATALOG_FAIL1), response_json["message"])) &&
        !isempty(find(s->contains(s, BLS_RESPONSE_CATALOG_FAIL2), response_json["message"]))
        catalog_okay = true
    end

    # Parse response into DataFrames, one for each series
    @assert n_series == length(response_json["Results"]["series"])
    out = Array{BlsSeries,1}(n_series)
    for (i, series) in enumerate(response_json["Results"]["series"])
        seriesID = series["seriesID"]
        if catalog_okay
            catalog = series["catalog"]
        else
            catalog = ""
        end
        catalog = vcat(catalog)

        data = map(parse_period_dict, series["data"])
        dates = flipdim([x[1] for x in data],1)
        values = flipdim([x[2] for x in data],1)
        df = DataFrame(date=dates, value=values)

        out[i] = BlsSeries(seriesID, df, catalog)
    end

    return out
end

function parse_period_dict{T<:AbstractString}(dict::Dict{T,Any})
    value = float(dict["value"])
    year  = parse(Int, dict["year"])

    period = dict["period"]
    # Monthly data
    if ismatch(r"M\d\d", period) && period ≠ "M13"
        month = parse(Int, period[2:3])
        date = Date(year, month, 1)

    # Quarterly data
    elseif ismatch(r"Q\d\d", period)
        quarter = parse(Int, period[3])
        date = Date(year, 3*quarter-2, 1)

    # Annual data
    elseif ismatch(r"A\d\d", period)
        date = Date(year, 1, 1)

    # Not implemented
    else
        error("Data of frequency ", period, " not implemented")
    end
    
    return (date, value)
end

end # module
