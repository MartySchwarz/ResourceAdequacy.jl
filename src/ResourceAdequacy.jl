module ResourceAdequacy

using Base.Dates
using StatsBase
using Distributions
using LightGraphs

#Make the following items available when ResourceAdequacy is called
export

    assess,

    # Units
    Year, Month, Week, Day, Hour, Minute,
    MW, GW,
    MWh, GWh, TWh,

    # Metrics
    LOLP, LOLE, EUE,
    val, stderr,

    # System distribution extraction methods
    Backcast, REPRA,

    # System assessment methods
    Copperplate, NetworkFlow, NetworkFlowStorage,

    # CV Methods
    EFC

include("units.jl")
include("SystemDistribution.jl")
include("SystemDistributionSet.jl")
include("conv.jl")

include("metrics.jl")
include("reliability.jl")
include("capacityvalue.jl")

end # module
