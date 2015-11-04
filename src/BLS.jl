module BLS

export BlsConnection, get_data

const DEFAULT_API_URL = "http://api.bls.gov/publicAPI/v2/timeseries/data/"

type BlsConnection
    url::AbstractString
    key::AbstractString
end

function BlsConnection(url=DEFAULT_API_URL; key="")
    BlsConnection(url, key)
end

api_url(b::BlsConnection) = b.url
api_key(b::BlsConnection) = b.key

using Requests
import Requests: post
import JSON

"""
"""
function get_data(b::BlsConnection, series::AbstractString;
               startyear::Int=Dates.year(now())-10,
               endyear::Int=Dates.year(now()),
               catalog::Bool=false)
    return get_data(b, [series]; startyear=startyear, endyear=endyear, catalog=catalog)
end

"""
"""
function get_data{T<:AbstractString}(b::BlsConnection, series::Array{T, 1};
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
