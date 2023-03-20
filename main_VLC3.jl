# using libraries
using Base
using LinearAlgebra
using Distributions: Uniform

# local libraries
include("src/ProjectVLC.jl")

import .ProjectVLC.Channels: phi_rad, vlc_channel, theta_deg, shadow_check
import .ProjectVLC.Parameters: ψ_c, ψ_05, I_DC, Nb, u_r, A_PD, β, η, height, device_height, N0, height_user_body, shoulder_width, x_eve, y_eve, led, user_coop
import .ProjectVLC.FileOutput: Output_3d
import .ProjectVLC.FileInput: file_read
import .ProjectVLC.Algorithm: LED_selection
import .ProjectVLC.Functions: dbm2watt, parse_commandline


function main()
    parse_args = parse_commandline()
    Ps = parse(Float64, parse_args["power"]) # transmission power
    u_type = parse(Int64, parse_args["usertype"])
    simulation_loop = parse(Int64, parse_args["period"])

    led_num = size(led,1)
    user = user_coop(u_type)
    user_num = size(user,1)
    ps = Ps
    n0 = dbm2watt(N0)

    capacity_user_sum_simu = zeros(length(x_eve), length(y_eve))
    capacity_eve_simu = zeros(length(x_eve), length(y_eve))
    secrecy_simu = zeros(length(x_eve), length(y_eve))

    user_d_matrix = zeros(user_num,led_num)
    eve_d_matrix = zeros(led_num)
    user_psi_matrix = zeros(user_num,led_num)
    user_body = zeros(user_num,3)
    user_theta_rad = zeros(user_num,led_num)
    eve_theta_rad = zeros(led_num)
    eve_body = zeros(3)
    eve_psi_matrix = zeros(led_num)
    
    
    s_group, user_group = LED_selection(user,user_num,led,led_num,height,device_height,ψ_c,"deg")



    for x_index in eachindex(x_eve)
        for y_index in eachindex(y_eve)

            eve = [x_eve[x_index], y_eve[y_index], device_height]
            # simulation
            sum_user = 0
            sum_eve = 0
            sec = 0
            for loop_index in 1:simulation_loop
                
                user_led_block = ones(user_num,led_num)
                eve_led_block = ones(led_num)
                # calculate distance,phi between users,eve and led
                user_omega_deg = rand(Uniform(-180,180),user_num)

                eve_omega_deg = rand(Uniform(-180,180))

                eve_body = [
                    eve[1] + cos(eve_omega_deg),
                    eve[2] + sin(eve_omega_deg),
                    height_user_body
                ]
                
                for n in 1:user_num
                    user_body[n,:] = [
                        user[n,1] + cos(user_omega_deg[n]), 
                        user[n,2] + sin(user_omega_deg[n]),
                        height_user_body] 

                    for i in 1:led_num
                        user_psi_matrix[n,i] = phi_rad(led[i,:],user[n,:],theta_deg("walk","opt"),user_omega_deg[n])
                        user_d_matrix[n,i] = norm(led[i,:] - user[n,:])
                        user_theta_rad[n,i] = acos((height-device_height) / user_d_matrix[n,i])

                        # check block -- user
                        for n_body in 1:user_num
                            # check if any user's body block
                            if shadow_check(led[i,:],user[n,:],user_body[n_body,:],shoulder_width) == 0.0
                                user_led_block[n,i] = 0.0
                                break
                            end
                        end
                        # check if eve's body block
                        if shadow_check(led[i,:],user[n,:],eve_body,shoulder_width) == 0.0
                            user_led_block[n,i] = 0.0
                        end
                    end
                end

                # calculate distance, phi between eve and led
                
                h_eve = zeros(led_num)
                for i in 1:led_num
                    eve_d_matrix[i] = norm(led[i,:]-eve)
                    eve_psi_matrix[i] = phi_rad(led[i,:],eve,theta_deg("walk","opt"),eve_omega_deg)
                    eve_theta_rad[i] = acos((height - device_height) / eve_d_matrix[i])


                    # check block -- eve
                    for n in 1:user_num
                        # check if any user's body block
                        if shadow_check(led[i,:],eve,user_body[n,:],shoulder_width) == 0.0
                            eve_led_block[i] = 0.0
                            break
                        end
                    end
                    # check if eve's body block
                    if shadow_check(led[i,:],eve,eve_body,shoulder_width) == 0.0
                        eve_led_block[i] = 0.0
                    end

                    h_eve[i] = (vlc_channel(
                        eve_psi_matrix[i],
                        deg2rad(ψ_c),
                        eve_theta_rad[i],
                        deg2rad(ψ_05),
                        eve_d_matrix[i],
                        A_PD,
                        Nb,
                        η)
                        * eve_led_block[i]
                    )
                end   
                
                
                h_user = zeros(user_num,led_num) 
                # initial the channel gain matrix
                capacity_user = 0
                capacity_eve = 0
                for n in 1:user_num
                    # set index of the user number

                    # initial the SINR calculation
                    # user_SINR = 0
                    # eve_SINR = 0
                    

                    for i in 1:led_num
                        # set index of the LED number 
                        # get the value of the channel gain
                        h_user[n,i] = (vlc_channel(
                            user_psi_matrix[n,i],
                            deg2rad(ψ_c),
                            user_theta_rad[n,i],
                            deg2rad(ψ_05),
                            user_d_matrix[n,i],
                            A_PD,
                            Nb,
                            η)
                            * user_led_block[n,i]
                            )
                    end
                end
                # Each floor set the NOMA rules based on user number in its coverage area

                # user
                sum_h_eve = 0
                for s in eachindex(user_group)
                    sum_h_eve += sum(h_eve[s_group[s]])
                end
                
                
                for s in eachindex(user_group)
                    β_sum = zeros(length(user_group[s]))
                    
                    # println(user_group[s])
                    for b in 1:length(user_group[s])
                        # println(b)
                        if b < length(user_group[s])
                            β_sum[b] = β * (1 - β)^(b-1)
                        else
                            β_sum[b] = (1 - β)^(b-1)
                        end
                    
                        user_SINR = (sum(h_user[user_group[s][b],s_group[s]])^2 * ps * β_sum[b] 
                        / (sum(h_user[user_group[s][b],s_group[s]])^2 * ps * ((1-β)^(b-1) - β_sum[b]) + n0))
                        # println(β_sum[b])
                        capacity_user += 0.5 * log2(1 + user_SINR)
                    
                        # eve
                        eve_SINR = (sum(h_eve[s_group[s]])^2 * ps * β_sum[b]
                        / (sum(h_eve[s_group[s]])^2 * ps * ((1-β)^(b-1) - β_sum[b])
                        + (sum_h_eve - sum(h_eve[s_group[s]])) * ps
                        + n0))
                        capacity_eve += 0.5 * log2(1 + eve_SINR)
                    end
                end
                
                sum_user += capacity_user        
                sum_eve += capacity_eve
                sec += max((capacity_user - capacity_eve), 0)
                print("\r",
                "XoYCoordinate = ",[x_eve[x_index], y_eve[y_index]], 
                ", Secrecy_capacity = ", sec / loop_index,
                ", Simulation Period = ", loop_index)
            end

            capacity_user_sum_simu[x_index,y_index] = sum_user / simulation_loop
            capacity_eve_simu[x_index,y_index] = sum_eve / simulation_loop
            secrecy_simu[x_index,y_index] = sec / simulation_loop
            print("\n")
        end
    end

    # output file
    path = string("results/case3/Loop_num=", Int(simulation_loop), 
        "/Ps=", Float64(Ps), 
        "/user_type", u_type, "/")
    file_user = string("VLC_user.txt")
    file_eve = string("VLC_eve.txt")
    file_sec = string("VLC_sec.txt")
    
    if ispath(path) == false
        mkpath(path)
    end
    cd(path)

    Output_3d(file_eve, x_eve, length(x_eve), y_eve, length(y_eve), capacity_eve_simu)
    Output_3d(file_user, x_eve, length(x_eve), y_eve, length(y_eve), capacity_user_sum_simu)
    Output_3d(file_sec, x_eve, length(x_eve), y_eve, length(y_eve), secrecy_simu)




end

# main()

if contains(@__FILE__, PROGRAM_FILE)
    main()
end