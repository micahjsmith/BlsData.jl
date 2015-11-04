module BLS

using Requests
import Requests: post
import JSON

export BlsConnection, get_data

const DEFAULT_API_URL = "http://api.bls.gov/publicAPI/v2/timeseries/data/"
const BLS_RESPONSE_SUCCESS = "REQUEST_SUCCEEDED"
const BLS_RESPONSE_CATALOG_FAIL1 = "unable to get catalog data"
const BLS_RESPONSE_CATALOG_FAIL2 = "catalog has been disabled"

type BlsConnection
    url::AbstractString
    key::AbstractString
end

function BlsConnection(url=DEFAULT_API_URL; key="")
    BlsConnection(url, key)
end

api_url(b::BlsConnection) = b.url
api_key(b::BlsConnection) = b.key

"""
"""
function get_data(b::BlsConnection, series::AbstractString;
               startyear::Int=Dates.year(now())-9,
               endyear::Int=Dates.year(now()),
               catalog::Bool=false)
    return get_data(b, [series]; startyear=startyear, endyear=endyear, catalog=catalog)
end

"""
"""
function get_data{T<:AbstractString}(b::BlsConnection, series::Array{T, 1};
               startyear::Int=Dates.year(now())-9,
               endyear::Int=Dates.year(now()),
               catalog::Bool=false)

    # Setup payload.
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
    response_json = Requests.json(response)

    # Response okay?
    if response_json["status"] ≠ BLS_RESPONSE_SUCCESS
        warning("Request failed with message '", response_json[status], "'")
        return nothing
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
    n_series = length(response_json["Results"]["series"])
    for i = 1:n_series
    end

    return response_json
end

end # module
