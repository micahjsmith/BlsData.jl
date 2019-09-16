using BlsData
using Test

let
    b = Bls()
    data = get_data(b, "PRS85006092")
    data = get_data(b, ["PRS85006092", "LNS11000000"])
    data = get_data(b, "PRS85006092"; startyear=1990)
    data = get_data(b, ["PRS85006092", "LNS11000000"]; endyear=2014)
    data = get_data(b, ["PRS85006092", "LNS11000000"]; startyear=1980, endyear=2014)
    data = get_data(b, "PRS85006092"; catalog=true)

    nothing
end

let
    b = Bls("test")

    nothing
end

let
    # Test empty BlsSeries
    empty_response = BlsData.EMPTY_RESPONSE()
    @test isempty(empty_response)

    nothing
end
