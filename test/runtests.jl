using BlsData
using Base.Test

b0 = BLS()
b1 = BLS(key="test")

data = get_data(b0, "PRS85006092")
data = get_data(b0, "PRS85006092"; catalog=true)
data = get_data(b0, "PRS85006092"; startyear=1990, catalog=true)
data = get_data(b0, ["PRS85006092", "LNS11000000"])
data = get_data(b0, ["PRS85006092", "LNS11000000"]; endyear=2014)
