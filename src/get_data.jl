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
function get_data(b::Bls, series::Array{T, 1};
                  startyear::Int = typemin(Int),
                  endyear::Int   = typemin(Int),
                  catalog::Bool  = false) where {T<:AbstractString}
    # Resolve default and user-specified date ranges
    if startyear == endyear == typemin(Int)
        # If neither startyear nor endyear is specified
        endyear = Int(Dates.year(Dates.now()))
        startyear = endyear - (LIMIT_YEARS_PER_QUERY[get_api_version(b)]-1)
    elseif startyear == typemin(Int) && endyear ≠ typemin(Int)
        # If only endyear is specified
        startyear = endyear - (LIMIT_YEARS_PER_QUERY[get_api_version(b)]-1)
    elseif startyear ≠ typemin(Int) && endyear == typemin(Int)
        # If only startyear is specified
        endyear = startyear + (LIMIT_YEARS_PER_QUERY[get_api_version(b)]-1)
    end
    @assert endyear > startyear
    @assert startyear ≤ Int(Dates.year(Dates.now()))

    # Make multiple requests for year range greater than limit
    limit = LIMIT_YEARS_PER_QUERY[get_api_version(b)]
    nrequests = div(endyear-startyear, limit) + 1
    if nrequests > requests_remaining(b)
        println("Insufficient number of requests remaining ", "(", nrequests, " needed ",
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

        # Check that we got a non-empty result
        # TODO this check fails if series metadata has been added to the result
        if isempty(result)
            continue
        end

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
            println("Empty response from server ignored.")
            continue
        end

        @assert result[i].id==data[i].id

        # It's possible that the first df, from 'data', has no rows but differently typed
        # columns from the second df. In this case, we ditch the first df entirely.
        if nrow(data[i].data) > 0
            append!(data[i].data, result[i].data)
        else
            data[i].data = result[i].data
        end

        # Add non-empty catalog strings
        if !isempty(result[i].catalog)
            data[i].catalog = join(data[i].catalog, ". ")
        end
    end
end

function is_catalog_okay(catalog, message)
    # Catalog okay?
    catalog &&
        !isempty(message) &&
        !any(s->occursin(BLS_RESPONSE_CATALOG_FAIL1, s), message) &&
        !any(s->occursin(BLS_RESPONSE_CATALOG_FAIL2, s), message)
end


# Worker method for a single request
function _get_data(b::Bls, series::Array{T,1},
                   startyear::Int, endyear::Int, catalog::Bool) where {T<:AbstractString}
    n_series = length(series)

    # Setup payload
    url     = get_api_url(b);
    headers = Dict("Content-Type" => "application/json")
    payload = Dict("seriesid"     => series,
                   "startyear"    => startyear,
                   "endyear"      => endyear,
                   "catalog"      => catalog)
    key     = get_api_key(b);
    if !isempty(key)
        payload["registrationKey"] = key
    end

    # Submit POST request to BLS
    body = JSON.json(payload)
    response = HTTP.request("POST", url, headers, body)

    # Check if request succeeded
    status = response.status
    if response.status == 200
        response_json = JSON.parse(String(copy(response.body)))
        increment_requests!(b)
    elseif response.status == 202
        # A 202 status code can be returned to note that "Your request is processing.". It's
        # unclear how BLS treats this, so we just try to process anyway. Exceptions are
        # expected.
        response_json = JSON.parse(String(copy(response.body)))
        increment_requests!(b)
    elseif haskey(BLS_STATUS_CODE_REASONS, response.status)
        reason = BLS_STATUS_CODE_REASONS[status]
        reason_http = HttpCommon.STATUS_CODES[status]
        error("API request failed with status $(status) ($(reason_http)): $(reason)")
    else
        if DEBUG log_error(url, payload, headers, response) end
        error("API request failed unexpectedly with status $(status)")
    end

    # Response okay?
    if response_json["status"] ≠ BLS_RESPONSE_SUCCESS
        if DEBUG log_error(url, payload, headers, response) end
        status = response_json["status"]
        message = if haskey(response_json, "message")
            join(hcat(response_json["message"]), ";")
        else
            "<no message returned>"
        end
        println("API request failed with status $(status): $(message)")

        # Return empty response for each series
        return [EMPTY_RESPONSE() for i in 1:n_series]
    end

    catalog_okay = is_catalog_okay(catalog, response_json["message"])

    # Parse response into DataFrames, one for each series
    @assert n_series == length(response_json["Results"]["series"])
    out = Array{BlsSeries,1}(undef, n_series)
    for (i, series) in enumerate(response_json["Results"]["series"])
        seriesID = series["seriesID"]
        catalog_out = if catalog_okay
            series["catalog"]
        else
            ""
        end
        catalog_out = vcat(catalog_out)
        catalog_out = join(catalog_out, ". ")

        data   = map(parse_period_dict, series["data"])
        dates  = reverse([x[1] for x in data],1)
        values = reverse([x[2] for x in data],1)
        df = DataFrame(date=dates, value=values)

        # Data may not be returned in order, for some reason.
        sort!(df)

        out[i] = BlsSeries(seriesID, df, catalog_out)
    end

    return out
end

function parse_period_dict(dict::Dict{T,Any}) where {T<:AbstractString}
    value = parse(Float64, dict["value"])
    year  = parse(Int, dict["year"])

    period = dict["period"]
    # Monthly data
    if occursin(r"M\d\d", period) && period ≠ "M13"
        month = parse(Int, period[2:3])
        date = Dates.Date(year, month, 1)

    # Quarterly data
    elseif occursin(r"Q\d\d", period)
        quarter = parse(Int, period[3])
        date = Dates.Date(year, 3*quarter-2, 1)

    # Annual data
    elseif occursin(r"A\d\d", period)
        date = Dates.Date(year, 1, 1)

    # Not implemented
    else
        error("Data of frequency ", period, " not implemented")
    end

    return (date, value)
end
