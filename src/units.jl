#Defines units to be used in the simulation

abstract type PowerUnit end
type MW <: PowerUnit end
type GW <: PowerUnit end

abstract type EnergyUnit end
type MWh <: EnergyUnit end
type GWh <: EnergyUnit end
type TWh <: EnergyUnit end

#Define unitsymbol function with multiple methods
unitsymbol(T::Type{<:PowerUnit}) = string(T)
unitsymbol(::Type{MW}) = "MW"
unitsymbol(::Type{GW}) = "GW"

unitsymbol(T::Type{<:EnergyUnit}) = string(T)
unitsymbol(::Type{MWh}) = "MWh"
unitsymbol(::Type{GWh}) = "GWh"
unitsymbol(::Type{TWh}) = "TWh"

unitsymbol(T::Type{<:Period}) = string(T)
unitsymbol(::Type{Minute}) = "min"
unitsymbol(::Type{Hour}) = "h"
unitsymbol(::Type{Day}) = "d"
unitsymbol(::Type{Year}) = "y"

#TODO: Generalize these for any type of units, not just MW,Hours, or minutes
#Define to_energy function with multiple methods
to_energy(p::Real, ::Type{MW}, n::Real, ::Type{Hour})  = (n*p, MWh)
to_energy(p::Real, ::Type{MW}, n::Real, ::Type{Minute}) = (n*p/60, MWh)
