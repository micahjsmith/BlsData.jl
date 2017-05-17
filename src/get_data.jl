"""
`get_data(b, series [; startyear, endyear, catalog])`
Request one or multiple series using the BLS API.

Arguments
---------
* `b`: A `Bls` connection
* `series`: A string, or array of strings, identifying the time series
* `startyear`: A four-digit year identifying the start of the data request. Defaults to
    9 or 19 years before `endyear`, depending on the API version used.
* `endyear`: A four-digit year identifying the end of the data request. Defaults to
    9 or 19 years after `endyear`, depending on the API version used; or, this year, if
    neither `startyear` nor `endyear` is provided.
* `catalog`: Whether to return any available metadata about the series. Defaults to `false`.

Returns
-------
A `BlsSeries`, or an array of `BlsSeries`.
"""
function get_data(b::Bls, series::AbstractString; kwargs...)
   return get_data(b, [series]; kwargs...)
end
function get_data{T<:AbstractString}(b::Bls, series::Array{T, 1};
                                     startyear::Int = typemin(Int),
                                     endyear::Int   = typemin(Int),
                                     catalog::Bool  = false)

    # Resolve default and user-specified date ranges
    if startyear == endyear == typemin(Int)
        endyear = Dates.year(now())
        startyear = endyear - LIMIT_YEARS_PER_QUERY_ADJ[api_version(b)]
    elseif startyear == typemin(Int) && endyear ≠ typemin(Int)
        startyear = endyear - LIMIT_YEARS_PER_QUERY_ADJ[api_version(b)]
    elseif startyear ≠ typemin(Int) && endyear == typemin(Int)
        endyear = startyear + LIMIT_YEARS_PER_QUERY_ADJ[api_version(b)]
    end
    @assert endyear > startyear

    series = vcat(series)

    # Make multiple requests for year range greater than limit
    limit = LIMIT_YEARS_PER_QUERY[api_version(b)]
    nrequests = div(endyear-startyear, limit) + 1
    if nrequests > requests_remaining(b)
        warn("Insufficient number of requests remaining ", "(", nrequests, " needed ", 
            requests_remaining(b), " remaining).")
        return if length(series) > 1
            [EMPTY_RESPONSE() for i in 1:length(series)]
        else
            EMPTY_RESPONSE()
        end
    end

    # Actually make requests to server
    data = []
    for i=1:nrequests
        t0 = startyear + limit * i - limit
        t1 = startyear + limit * i - 1
        if t1 > endyear
            t1 = endyear
        end
        result = _get_data(b, series, t0, t1, catalog)

        # Append to existing results
        if isempty(data)
            data = result
        else
            append_result!(data, result)
        end

    end

    if length(data) == 1
        return data[1]
    else
        return data
    end
end

# Append data frame and catalog information for each series.
function append_result!(data, result)
    for i=1:length(result)
        # Simply don't attempt to append empty results
        if isempty(result[i])
            warn("Empty response from server ignored.")
            continue
        end

        @assert id(result[i])==id(data[i])
        append!(series(data[i]), series(result[i]))

        # Add non-empty catalog strings
        if !isempty(catalog(result[i]))
            data[i].catalog = join(catalog(data[i]), ". ")
        end
    end
end

# Worker method for a single request
function _get_data{T<:AbstractString}(b::Bls, series::Array{T,1}, 
                                      startyear::Int, endyear::Int, catalog::Bool)

    n_series = length(series)

    # Setup payload
    url     = api_url(b);
    headers = Dict("Content-Type" => "application/json")
    json    = Dict("seriesid"     => series,
                   "startyear"    => startyear,
                   "endyear"      => endyear,
                   "catalog"      => catalog)
    key     = api_key(b);
    if !isempty(key)
        json["registrationKey"] = key
    end

    # Submit POST request to BLS
    response = Requests.post(url; json=json, headers=headers)

    # Check if request succeeded
    status = response.status
    if response.status == 200
        response_json = Requests.json(response)
        increment_requests(b)
    elseif response.status == 202
        # A 202 status code can be returned to note that "Your request is processing.". It's
        # unclear how BLS treats this, so we just try to process anyway. Exceptions are
        # expected.
        response_json = Requests.json(response)
        increment_requests(b)
    elseif haskey(BLS_STATUS_CODE_REASONS, response.status)
        reason = BLS_STATUS_CODE_REASONS[status]
        reason_http = HttpCommon.STATUS_CODES[status]
        error("API request failed with status $(status) ($(reason_http)): $(reason)")
    else
        try
            if DEBUG
                open(joinpath(homedir(), ".blsdatajl.log"), "a") do f
                    println(f, Requests.text(response))
                end
            end
        finally
            error("API request failed unexpectedly with status $(status)")
        end
    end

    # Response okay?
    if response_json["status"] ≠ BLS_RESPONSE_SUCCESS
        status = response_json["status"]
        message = if haskey(response_json, "message")
            join(hcat(response_json["message"]), ";")
        else
            "<no message returned>"
        end
        warn("API request failed with status $(status): $(message)")

        # Return empty response for each series
        return [EMPTY_RESPONSE() for i in 1:n_series]
    end

    # Catalog okay?
    catalog_okay = catalog &&
        !isempty(response_json["message"]) &&
        !isempty(find(s->contains(s, BLS_RESPONSE_CATALOG_FAIL1), response_json["message"])) &&
        !isempty(find(s->contains(s, BLS_RESPONSE_CATALOG_FAIL2), response_json["message"]))

    # Parse response into DataFrames, one for each series
    @assert n_series == length(response_json["Results"]["series"])
    out = Array{BlsSeries,1}(n_series)
    for (i, series) in enumerate(response_json["Results"]["series"])
        seriesID = series["seriesID"]
        catalog_out = if catalog_okay
            series["catalog"]
        else
            ""
        end
        catalog_out = vcat(catalog_out)
        catalog_out = join(catalog_out, ". ")

        data = map(parse_period_dict, series["data"])
        dates = flipdim([x[1] for x in data],1)
        values = flipdim([x[2] for x in data],1)
        df = DataFrame(date=dates, value=values)

        # Data may not be returned in order, for some reason.
        sort!(df)

        out[i] = BlsSeries(seriesID, df, catalog_out)
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
