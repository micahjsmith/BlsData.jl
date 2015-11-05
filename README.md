# BLS

A basic Julia interface to pull data from the Bureau of Labor Statistics using
their Public API [here](http://www.bls.gov/developers/home.htm).

## Usage

Basic usage:
```
using BlsData
b = BLS()
data = get_data(b, "LNS11000000")
```

Or, register on the BLS website for a Public Data API account
[here](http://data.bls.gov/registrationEngine/). Then, take advantage of the
increased daily query limit and other features:
```
using BlsData
b = BLS(key="MY API KEY")
data = get_data(b, "PRS85006092"; catalog=true)
```

## Setup

Simply run
```julia
julia> Pkg.clone("https://github.com/micahjsmith/BlsData.jl.git")
```
