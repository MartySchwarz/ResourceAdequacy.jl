struct NetworkFlowStorage <: ReliabilityAssessmentMethod
    timesteps::Int #Number of iterations
    persist::Bool   #True: Save detailed results to HDF5 file
                    #False: Save just LOLE

#Constructor function
    function NetworkFlowStorage(timesteps::Int, persist::Bool=false)
        @assert timesteps > 0
        new(timesteps, persist)
    end
end

function all_load_served(params::NetworkFlowStorage, A::Matrix{T}, B::Matrix{T}, sink::Int, n::Int) where T
    served = true
    unserved_load_data = zeros(0,2)
    i = 1
    while i <= n
        served = A[i, sink] == B[i, sink]
        if !served
            unserved_load_data = [unserved_load_data; [i A[i, sink] - B[i, sink]]] #Appends a new row each time with the node at which unserved load occurred, and the amount unserved.
        end
        i += 1
    end
    return unserved_load_data
end

function all_generation_used(params::NetworkFlowStorage, A::Matrix{T}, B::Matrix{T}, source::Int, n::Int) where T
    all_used = A[source, :] == B[source,:]
    return all_used
end

function assess(params::NetworkFlowStorage, system::SystemDistribution{N,T,P,Float64}) where {N,T,P}

    systemsampler = SystemSampler(system)
    sink_idx = nv(systemsampler.graph) #Number of total nodes in the graph, sink is the last node
    source_idx = sink_idx-1 #Source is the second-to-last last node
    n = sink_idx-2 #Number of network nodes
    n_gens = size(system.gen_dists,1) #Number of system dispatchable generators, not necessarily equal to the number of nodes/areas
    n_storage = size(system.storage_params,1) #Number of energy storage devices

    #Create a state matrix and initialize counters
    #state_matrix contains line flows, including flows between source to load to sink
    state_matrix = zeros(sink_idx, sink_idx)
    lol_count = 0
    lol_sum = 0.
    failure_states = FailureResult{Float64}[]

    flow_matrix = Array{Float64}(sink_idx, sink_idx)
    height = Array{Int}(sink_idx)
    count = Array{Int}(2*sink_idx+1)
    excess = Array{Float64}(sink_idx)
    active = Array{Bool}(sink_idx)


    ###########################################################################
    #In this section, use the generator parameters to determine the transition probabilities for each.
    #Create a state transition matrix from the MTTR and FOR
    # [OFF to ON, ON to OFF], the other transition probs are the complement of these values
    #MTBF = MTTR/FOR - MTTR
    generator_state_trans_matrix = Matrix{Float64}(n_gens,2)
    generator_state_trans_matrix = [1./system.gen_dists[:,3] 1./(system.gen_dists[:,3]./system.gen_dists[:,4] - system.gen_dists[:,3])]

    initial_generator_ON_fraction = 0.9 #Percentage of generators that begin online
    generator_state_vector = Int.(rand(n_gens,1) .< initial_generator_ON_fraction*ones(n_gens) #Initialize a vector of ones (Generator ON) and zeros (Generator OFF)
    ###########################################################################

    ###########################################################################
    #Initialize energy storage
    #Add a final column to determine the max this storage can provide in the next timestep
    #MaxPowerAvail X timestep = MaxEnergy X SOC
    #Since timestep = 1 unit, MaxPowerAvail = MaxEnergy X SOC, so long as it is less than MaxPowerCap. Thus, take the min
    storage_energy_tracker = [system.storage_params min.(system.storage_params[:,2].*system.storage_params[:,3],system.storage_params[:,1])] #Last column is min(energy X SOC, MaxPowerCap)
    #TODO: Make storage_energy_tracker into a structure? Probably easier than a matrix
    ###########################################################################


    #Main Loop
    for i in 1:params.timesteps

        #Iterate over all timesteps
        #This is where load flow is performed, using the push_relabel! function

#=
        A) Generation--Markov Chain with state transition matrixF
            Start with initial generator distribution for first time step. Then update using Markov Chain
        B) Load--Design for multiple possibilities:
            1) Preallocate load data (backcast?)
            2) Extraction "windowing" method
        C) Variable Gen--Same as Load
        D) Storage--If used, reduce SOC by amount used in an hour. If charged, increase SOC.
                If neither, model some trickle losses.
=#

        #Create state_matrix from systemsampler
        rand!(state_matrix, systemsampler)

        #Sum all of the generation in each node, changes each time iteration
        generation_row_vector = zeros(1,sink_idx)
        for j in 1:n
            temp_index_vector = find(system.gen_dists[:,2].==j) #temporary vector of the indices of the generators at node j
            generation_row_vector[j] = sum(system.gen_dists[temp_index_vector].*generator_state_vector[temp_index_vector]) #Multiply the generator capacities by the state vector, which will either multiply by zero or one, then sum. Even though system.gen_dists is a matrix, the indices will extract the values in the first column, as Julia is column-major
        end

        #Sum all of the storage in each node, changes each time iteration
        storage_row_vector = zeros(1,sink_idx)
        for j in 1:n
            temp_index_vector = find(storage_energy_tracker[:,4].==j) #temporary vector of the indices of the storage devices at node j
            temp_var = storage_energy_tracker[:,5] #Temporarily extract just the final column containing the storage_energy_tracker matrix, which contains just the max available power for this timestep for each storage device, as the max avail power may change each iteration
            storage_row_vector[j] = sum(temp_var[temp_index_vector]) #temp_index_vector indexes into the "fifth column" of storage_energy_tracker which contains the power capacity available at this timestep, calculated from SOC and MaxEnergy
        end

        #TODO: Currently overwriting the values in the state_matrix, but should probably just directly save these in SystemSampler
        state_matrix[source_idx,:] = generation_row_vector


        systemload, flow_matrix =
            LightGraphs.push_relabel!(flow_matrix, height, count, excess, active,
                          systemsampler.graph, source_idx, sink_idx, state_matrix)

        #Create a state_matrix with another node for storage
        # state_matrix_storage = state_matrix
        # state_matrix_storage = [state_matrix_storage zeros(sink_idx,1)]
        # state_matrix_storage = [state_matrix_storage; ]

        #Functions
        if !all_generation_used
            #Charge some batteries, if possible

        end

        unserved_load_data = all_load_served(params, state_matrix, flow_matrix, sink_idx, n)
        #TODO: Update this to take storage as an ON/OFF input
        if size(unserved_load_data,1) > 0 #If one instance of unserved load exists

            #First, we check if storage can fix the problem
            #Create a matrix of "leftovers"
            #This leaves a matrix with the available line capacity in the upper left block, available gen in the second-to-last row, and unserved load in the final column
            unserved_state_matrix = state_matrix - abs.(flow_matrix)

            #Remove the available generation, and save it for a later step
            available_generation = unserved_state_matrix[end-1,:]

            #Replace the row of available generation with the available storage (in "generation" mode)
            unserved_state_matrix[end-1,:] = [storage_row_vector 0 0] #Zero-padding for the final two columns

            #Run push_relabel again with the new values
            #TODO: Is it OK to reuse the "flow_matrix" variable?
            systemload, flow_matrix = LightGraphs.push_relabel!(flow_matrix, height, count, excess, active, systemsampler.graph, source_idx, sink_idx, unserved_state_matrix)


            unserved_load_data_storage = all_load_served(params, unserved_state_matrix, flow_matrix, sink_idx, n)

            #Decide which storage devices provided the energy
            update_storage_vector = zeros(n_storage,1) #Creates a vector of the amount of power used by each storage device. It will be used to update their SOCs at the end of the outermost loop. Needs to be re-"zeroed" at the start of each loop
            for j in 1:n #loop through all the nodes (not the sink or source)
                Reqd_power_node_j = flow_matrix[source_idx,j]

                sortrows(storage_energy_tracker, by=x->(x[4],x[5])) #Sort it by node, then by MaxPowerAvail
                temp_indices = find(storage_energy_tracker[:,4].==j) #Find indices of node j

                #Go through the storage devices at node j, using the lowest-power one first (hopefully, we have a proof for this)
                for k in 1:length(temp_indices)

                    #Note that it should be impossible for Reqd_power_node_j > sum(storage_energy_tracker[temp_indices[k],5]), this loop should pose no problems
                    if Reqd_power_node_j > storage_energy_tracker[temp_indices[k],5]

                        #Store this value and reduce Reqd_power_node_j by this amount
                        update_storage_vector[temp_indices[k]] = Reqd_power_node_j
                        Reqd_power_node_j = Reqd_power_node_j - storage_energy_tracker[temp_indices[k],5]
                    else
                        update_storage_vector[temp_indices[k]] = Reqd_power_node_j
                        break #exit this FOR loop as we have already determined which storae devices will provide the requirement

                    end
                end
            end

            #Now, use update_storage_vector to change the SOC of the storage devices
            #RIGHT HERE, DO IT!!!!!!!!!!!!!!!!!!!!!!!!!!


            if size(unserved_load_data_storage) > 0
                #DO STUFF

            else #All load was served when storage was included

            end



            # TODO: Save whether generator or transmission constraints are to blame?
            lol_count += 1
            #lol_sum += 0

            params.persist && push!(failure_states, FailureResult(state_matrix, flow_matrix, system.interface_labels, n))

        else #size(unserved_load_data,1) = 0
            #No need to record anything
        end

        #########################################################
        #Update generators based on their state transition matrix
        #TODO: Consider if there is a more efficient way to do this and perhaps put in its own function
        for j in 1:n_gens
            temp_bitarray = rand(1) .< generator_state_trans_matrix[j,generator_state_vector[j]+1] #This expression creates a BitArray that can't be used in IF logic
            if temp_bitarray[1] #Extract the first value which is a boolean
                generator_state_vector[j] = Int.(~Bool(generator_state_vector[j]))
            else
                #Do nothing, keep state the same
            end
        end
        #########################################################

        #########################################################
        #Update storage SOC (put this in a function??? Is there a more efficient way to do this??)
        #TODO: Should we account for losses? Right now it's 100% round-trip efficiency
        for j in 1:n_storage
            if update_storage_vector[j] > 0
                storage_energy_tracker[j,3] = storage_energy_tracker[j,3] + update_storage_vector[j]*1./storage_energy_tracker[j,2] #Update the SOC --> SOCnew = SOCold + (PowerUsed X Timestep)/MaxEnergy
            else # <= 0
                #Update SOC because of losses
                #TODO: Should we do losses here, or wait until after "charging"?

            end
        end
        #########################################################

        #########################################################
        #Do charging here?


        #########################################################

    end

    μ = lol_count/params.timesteps
    σ² = μ * (1-μ)
    # eue_val, E = to_energy(lol_sum/params.timesteps, P, N, T)
    eue_val, E = to_energy(Inf, P, N, T)

    detailed_results = FailureResultSet(failure_states, system.interface_labels)

    return SinglePeriodReliabilityAssessmentResult(
        LOLP{N,T}(μ, sqrt(σ²/params.timesteps)),
        EUE{E,N,T}(eue_val, 0.),
        params.persist ? detailed_results : nothing
    )

end