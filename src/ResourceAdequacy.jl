module ResourceAdequacy

using Base.Dates
using StatsBase
using OnlineStats
using Distributions
using LightGraphs

export

    assess,

    # Units
    Year, Month, Week, Day, Hour, Minute,
    MW, GW,
    MWh, GWh, TWh,

    # Metrics
    LOLP, LOLE, EUE,
    val, stderr,

    # Distribution extraction specifications
    Backcast, REPRA,

    # Simulation specifications
    NonSequentialCopperplate, SequentialCopperplate,
    NonSequentialNetworkFlow,

    # Result specifications
    MinimalResult, NetworkResult,

    # Result methods
    timestamps

CapacityDistribution{T} = Distributions.Generic{T,Float64,Vector{T}}
CapacitySampler{T} = Distributions.GenericSampler{T, Vector{T}}

# Parametrize simulation specs by sequentiality
abstract type SimulationSequentiality end
struct NonSequential <: SimulationSequentiality end
struct Sequential <: SimulationSequentiality end

# Abstract component specifications
abstract type ExtractionSpec end
abstract type SimulationSpec{T<:SimulationSequentiality} end
abstract type ResultSpec end

include("utils.jl")
include("metrics.jl")
include("systemdata.jl")
include("results.jl")
include("extraction.jl")
include("simulation.jl")

end # module
