#System representation at one time step

LimitDistributions{T} = Vector{Generic{T,Float64,Vector{T}}}
LimitSamplers{T} = Vector{Distributions.GenericSampler{T, Vector{T}}}

struct SystemDistribution{N,T<:Period,P<:PowerUnit,V<:Real}
    gen_distributions::LimitDistributions{V} #List of dist of max available capacities
    vgsamples::Matrix{V} #possible states of VG
    interface_labels::Vector{Tuple{Int,Int}} #Maps one region to another in electrical network (edge list)
    interface_distributions::LimitDistributions{V} #Probability distribution of carrying cap of transmission lines
    loadsamples::Matrix{V} #Collection of load states (buses x #states at each bus)
    gen_state_trans_probs::Matrix{V} #Generator Markov chain probabilities

    function SystemDistribution{N,T,P}(
        gen_dists::LimitDistributions{V},
        vgsamples::Matrix{V},
        interface_labels::Vector{Tuple{Int,Int}},
        interface_dists::LimitDistributions{V},
        loadsamples::Matrix{V},
        gen_state_trans_probs::Matrix{V}) where {N,T,P,V}

        n_regions = length(gen_dists)
        @assert size(vgsamples, 1) == n_regions
        @assert size(loadsamples, 1) == n_regions
        @assert length(interface_dists) == length(interface_labels)
        @assert size(gen_state_trans_probs,1) == n_regions

        new{N,T,P,V}(gen_dists, vgsamples,
                     interface_labels, interface_dists,
                     loadsamples, gen_state_trans_probs)

    end

    function SystemDistribution{N,T,P}(gd::Generic{V,Float64,Vector{V}},
                                vg::Vector{V}, ld::Vector{V}) where {N,T,P,V}

        #gen_state_trans_probs = [zeros(length(gd),1) ones(length(gd),1) zeros(length(gd),1) ones(length(gd),1)] #guarentees that gen stays online

        new{N,T,P,V}([gd], reshape(vg, 1, length(vg)),
               Vector{Tuple{Int,Int}}[], Generic{V,Float64,Vector{V}}[],
               reshape(ld, 1, length(ld)),[zeros(length(gd),1) ones(length(gd),1) zeros(length(gd),1) ones(length(gd),1)])
    end

end

struct SystemSampler{T <: Real}
    gen_samplers::LimitSamplers{T}
    vgsamples::Matrix{T}
    interface_labels::Vector{Tuple{Int,Int}}
    interface_samplers::LimitSamplers{T}
    loadsamples::Matrix{T}
    node_idxs::UnitRange{Int}
    interface_idxs::UnitRange{Int}
    loadsample_idxs::UnitRange{Int}
    vgsample_idxs::UnitRange{Int}
    graph::DiGraph{Int}

    function SystemSampler(sys::SystemDistribution{N,T,P,V}) where {N,T,P,V}

        n_nodes = length(sys.gen_distributions)
        n_interfaces = length(sys.interface_distributions)
        n_vgsamples = size(sys.vgsamples, 2)
        n_loadsamples = size(sys.loadsamples, 2)

        node_idxs = Base.OneTo(n_nodes)
        interface_idxs = Base.OneTo(n_interfaces)
        loadsample_idxs = Base.OneTo(n_loadsamples)
        vgsample_idxs = Base.OneTo(n_vgsamples)

        source_node = n_nodes + 1
        sink_node   = n_nodes + 2
        graph = DiGraph(sink_node)

        # Populate graph with interface edges
        for (from, to) in sys.interface_labels
            add_edge!(graph, from, to)
            add_edge!(graph, to, from)
        end

        # Populate graph with source and sink edges
        for i in node_idxs

            add_edge!(graph, source_node, i)
            add_edge!(graph, i, sink_node)

            # Graph requires reverse edges as well,
            # even if max flow is zero
            # (why does LightGraphs use a DiGraph for this then?)
            add_edge!(graph, i, source_node)
            add_edge!(graph, sink_node, i)

        end

        new{V}(sampler.(sys.gen_distributions), sys.vgsamples,
               sys.interface_labels,
               sampler.(sys.interface_distributions),
               sys.loadsamples,
               node_idxs, interface_idxs,
               loadsample_idxs, vgsample_idxs,
               graph)

    end
end

function Base.rand!(A::Matrix{T}, system::SystemSampler{T}) where T

    node_idxs = system.node_idxs
    source_idx = last(node_idxs) + 1
    sink_idx = last(node_idxs) + 2

    vgsample_idx = rand(system.vgsample_idxs)
    loadsample_idx = rand(system.loadsample_idxs)

    # Assign random generation capacities and loads
    for i in node_idxs
        A[source_idx, i] =
            rand(system.gen_samplers[i]) +
            system.vgsamples[i, vgsample_idx]
        A[i, sink_idx] = system.loadsamples[i, loadsample_idx]
    end

    # Assign random line limits
    for ij in system.interface_idxs
        i, j = system.interface_labels[ij]
        flowlimit = rand(system.interface_samplers[ij])
        A[i,j] = flowlimit
        A[j,i] = flowlimit
    end

    return A

end

function Base.rand(system::SystemSampler{T}) where T
    n = nv(system.graph)
    A = zeros(T, n, n)
    return rand!(A, system)
end
