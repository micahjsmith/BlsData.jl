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

include("fetch.jl")

end # module
