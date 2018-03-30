struct EFC <: CapacityValuationMethod
    nameplatecapacity::Float64
    p::Float64
    tol_mw::Float64
    nodes::Generic{Int,Float64,Vector{Int}}
end

#TODO: Generalize this (metaprogramming?) for the SystemDistribution case as well
function assess(params::EFC,
                metric::Type{<:ReliabilityMetric},
                extractionmethod::SinglePeriodExtractionMethod,
                assessmentmethod::ReliabilityAssessmentMethod,
                sys_before::S, sys_after::S) where {S <: SystemDistributionSet}

    metric_target = metric(assess(extractionmethod, assessmentmethod, sys_after))

    metric_a = metric(assess(extractionmethod, assessmentmethod, sys_before))
    fc_a = 0.

    metric_b = metric(assess(extractionmethod, assessmentmethod,
        addfirmcapacity(sys_before, node, nameplatecapacity)))
    fc_b = nameplatecapacity

    while true

        println("(", fc_b, ", ", metric_b, ")",
                " < ", metric_target, " < ",
                "(", fc_a, ", ", metric_a, ")")

        # Stopping conditions

        ## Return midpoint if bounds are within solution tolerance of each other
        if fc_b - fc_a < tol_mw
            println("Capacity difference within tolerance, stopping.")
            return (fc_a + fc_b)/2
        end

        ## If either bound exceeds the null hypothesis
        ## probability threshold, return the most probable bound
        p_a = pequal(metric_target, metric_a)
        p_b = pequal(metric_target, metric_b)
        if (p_a >= p) || (p_b >= p)
            println("Equality probability within tolerance, stopping.")
            return p_a > p_b ? metric_a : metric_b
        end

        # Evaluate metric at midpoint
        fc_x = (fc_a + fc_b) / 2
        metric_x = metric(assess(
            extractionmethod,
            assessmentmethod,
            addfirmcapacity(sys_before, node, fc_x)))

        # Tighten FC bounds
        if val(metric_x) > val(metric_target)
            fc_a = fc_x
            metric_a = metric_x
        else # metric_x <= metric_target
            fc_b = fc_x
            metric_b = metric_x
        end

    end

end