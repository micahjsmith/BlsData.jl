using BLS
using Base.Test

b0 = BlsConnection()
b1 = BlsConnection(key="test")

data = get_data(b0, "PRS85006092")
data = get_data(b0, "PRS85006092"; catalog=true)
data = get_data(b0, "PRS85006092"; startyear=1990, catalog=true)
