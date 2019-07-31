function spconv!(y_values::Vector{Int}, y_probs::Vector{Float64},
                 h_value::Int, h_prob::Float64,
                 x_values::Vector{Int}, x_probs::Vector{Float64}, nx::Int)

    h_q = 1 - h_prob

    ix = ixsh = 1
    iy = 0
    lastval = -1

    @inbounds while ix <= nx

        x = x_values[ix]
        xsh = x_values[ixsh] + h_value

        if lastval == x
            @fastmath y_probs[iy] += h_q * x_probs[ix]
            ix += 1

        elseif lastval == xsh
            @fastmath y_probs[iy] += h_prob * x_probs[ixsh]
            ixsh += 1

        elseif x == xsh
            iy += 1
            y_values[iy] = x
            @fastmath y_probs[iy] = h_q * x_probs[ix] + h_prob * x_probs[ixsh]
            lastval = x
            ix += 1
            ixsh += 1

        elseif x < xsh
            iy += 1
            y_values[iy] = x
            @fastmath y_probs[iy] = h_q * x_probs[ix]
            lastval = x
            ix += 1

        elseif xsh < x
            iy += 1
            y_values[iy] = xsh
            @fastmath y_probs[iy] = h_prob * x_probs[ixsh]
            lastval = xsh
            ixsh += 1

        end

    end

    @inbounds while ixsh <= nx
        iy += 1
        y_values[iy] = x_values[ixsh] + h_value
        @fastmath y_probs[iy] = h_prob * x_probs[ixsh]
        ixsh += 1
    end

    return y_values, y_probs, iy, x_values, x_probs

end


function spconv(hvsraw::AbstractVector{Int}, hpsraw::AbstractVector{Float64})

    zeroidxs = hvsraw .!= 0
    hvs = hvsraw[zeroidxs]
    hps = hpsraw[zeroidxs]

    length(hvs) == 0 && return DiscreteNonParametric([0], [1.], NoArgCheck())

    max_n = sum(hvs) + 1
    current_probs  = Vector{Float64}(undef, max_n)
    prev_probs     = Vector{Float64}(undef, max_n)
    current_values = Vector{Int}(undef, max_n)
    prev_values    = Vector{Int}(undef, max_n)

    current_n = 2
    current_values[1:current_n] = [0, hvs[1]]
    current_probs[1:current_n]  = [1 - hps[1], hps[1]]

    for (hv, hp) in zip(hvs[2:end], hps[2:end])
        current_values, current_probs, current_n, prev_values, prev_probs =
            spconv!(prev_values, prev_probs, hv, hp,
                    current_values, current_probs, current_n)
    end

    resize!(current_values, current_n)
    resize!(current_probs, current_n)
    nonzeroprob_idxs = findall(x -> x>0, current_probs)

    return DiscreteNonParametric(
        current_values[nonzeroprob_idxs],
        current_probs[nonzeroprob_idxs],
        NoArgCheck())

end

function add_dists(a::DiscreteNonParametric, b::DiscreteNonParametric)

    xs = vec(support(a) .+ support(b)')
    ps = vec(probs(a) .* probs(b)')

    # These are monstrous
    ordering = sortperm(xs)
    xs = xs[ordering]
    ps = ps[ordering]

    # TODO: Replace these resizing arrays with worst-case-length
    # vectors and an out_idx index tracker. Small potatoes
    # compared to the sort operation above though.
    out_values = [xs[1]]
    out_probs  = [ps[1]]
    prev_value = xs[1]

    for i in 2:length(xs)

        value = xs[i]

        if value == prev_value
            out_probs[end] += ps[i]
        else
            push!(out_values, value)
            push!(out_probs, ps[i])
            prev_value = value
        end

    end

    return DiscreteNonParametric(out_values, out_probs, NoArgCheck())

end

subtract_dists(a::DiscreteNonParametric, b::DiscreteNonParametric) =
    add_dists(a, DiscreteNonParametric(-b.support, b.p))

function assess(supply::DiscreteNonParametric{T,Float64,Vector{T}},
                demand::DiscreteNonParametric{T,Float64,Vector{T}}) where T

    s = support(supply)
    ps = probs(supply)

    d = support(demand)
    pd = probs(demand)
    j = j_max = length(d)
    j_min = 1

    p = 0.
    eul = 0.

    for i in 1:length(s)
        while j >= j_min
            if s[i] < d[j]
                psd = ps[i] * pd[j]
                p += psd
                eul += psd * (d[j] - s[i])
                j -= 1
            else
                j_min = j+1
                break
            end
        end
        j = j_max
    end

    return p, eul

end
