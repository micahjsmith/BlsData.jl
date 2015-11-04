module BLS

export BlsConnection, fetch

const DEFAULT_API_URL = "http://api.bls.gov/publicAPI/v2/timeseries/data/"

type BlsConnection
    url::AbstractString
    key::AbstractString
end

function BlsConnection(url=DEFAULT_API_URL; key="")
    BlsConnection(url, key)
end

using Requests
import Requests: post
import JSON

"""
"""
function fetch(b::BlsConnection, series::AbstractString;
               startyear::Int=Dates.year(now())-10,
               endyear::Int=Dates.year(now()),
               catalog::Bool=false)
    return fetch(b, [series]; startyear=startyear, endyear=endyear, catalog=catalog)
end

"""
"""
function fetch(b::BlsConnection, series::Vector{AbstractString};
               startyear::Int=Dates.year(now())-10,
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
        json["restristrationKey"] = key
    end

    # Submit POST request to BLS
    response = post(url; json=json, headers=headers)

    return response
end

end # module
