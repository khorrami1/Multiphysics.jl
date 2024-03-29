
using Tensors
using Ferrite
using Rotations

# F and F_e are given, then we gonna solve F_p:
# gamma_dot_0

E = 200e9
ν = 0.3
dim = 3
λ = E*ν / ((1 + ν) * (1 - 2ν))
μ = E / (2(1 + ν))
δ(i,j) = i == j ? 1.0 : 0.0

function get_func_elasticity(λ, μ)
    (i,j,k,l) -> λ*δ(i,j)*δ(k,l) + μ*(δ(i,k)*δ(j,l) + δ(i,l)*δ(j,k))
end

func_elas = get_func_elasticity(λ, μ)

C_11 = 10 # C_22 = C_33
C_12 = 5
C_44 = 2
get_C_qubic(C_11::Number, C_12::Number, C_44::Number) = [C_11 C_12 C_12 0 0 0; C_12 C_11 C_12 0 0 0 ; C_12 C_12 C_11 0 0 0; 0 0 0 C_44 0 0;  0 0 0 0 C_44 0;  0 0 0 0 0 C_44]

get_C_qubic(C_11, C_12, C_44)

function get_C_qubic_from_ijkl(C_11::Number, C_12::Number, C_44::Number)
    return function (i,j,k,l)
        if i==j
            if k==l
                if k==i
                    C_11
                else
                    C_12
                end
            else
                0.0
            end
        else
            if i==k && j==l
                C_44
            else
                0.0
            end
        end
    end
end

func_elas = get_C_qubic_from_ijkl(C_11, C_12, C_44)

C = SymmetricTensor{4, dim}(func_elas)

q = rand(QuatRotation)
aa = AngleAxis(q)

aa_vec3d = Vec((aa.axis_x, aa.axis_y, aa.axis_z ))

C_rotated = Tensors.rotate(C, aa_vec3d, aa.theta )


gamma_dot_0 = 1e-3
n = 20
gamma_dot_p = 0.0
dt = 1
gamma_p = 1e-3
h0 = 50
xi_0 = 10.0

using Tensors

struct MaterialState_isoJ2{T, S<:SecondOrderTensor{3, T}}
    F_p :: S
    F_e :: S
    S_e :: S
    L_p :: S
    gamma_p :: T
    xi :: T
end

function MaterialState_isoJ2()
    return MaterialState_isoJ2(
        one(Tensor{2, 3}),
        one(Tensor{2, 3}),
        zero(Tensor{2, 3}),
        one(Tensor{2, 3}), 0.0, 10.0
    )
end

num_q = 4
num_cell = 2

matstates_old = [MaterialState_isoJ2() for _ in 1:num_q, _ in 1:num_cell]
matstates_new = [MaterialState_isoJ2() for _ in 1:num_q, _ in 1:num_cell]

matstate = @view matstates_new[:,2]

matstate[1] = MaterialState_isoJ2()

matstates_old = matstates_new

# F = Matrix{Float64}(I, 3, 3)
# F_p = Matrix{Float64}(I, 3, 3)
# F_p[1,2] = 0.5
# I_3_3 = Matrix{Float64}(I, 3, 3)

# res_F_p_vec = zeros(9)
# F_p_vec = F_p[:]

function Res_Fp!(res_F_p_vec,F_p_vec, gamma_dot_p, gamma_p, F, h0, xi_0, F_p)
    F_p_next = reshape(F_p_vec, 3,3)
    gamma_p_next = gamma_dot_p*dt + gamma_p
    xi_next = xi_0 + h0*gamma_p_next
    F_e = F ⋅ inv(F_p_next)
    E_e = 0.5*(tdot(matstates[1,1].F_e) - one(Tensor{2,3}))
    S_e = 25*E_e
    S_e_dev = dev(S_e)
    norm_S_e_dev = norm(S_e_dev)
    gamma_dot_p = gamma_dot_0 * (norm_S_e_dev/xi_next)^n
    L_p = gamma_dot_p * S_e_dev/norm_S_e_dev
    F_dot_p = L_p * F_p_next
    res_F_p = F_p_next .- F_dot_p * dt .- F_p
    res_F_p_vec .= res_F_p[:]
    return  res_F_p_vec
end

#Res_Fp!(res_F_p_vec,F_p_vec, gamma_dot_p, gamma_p, F, I_3_3, h0, xi_0, F_p)

Res_Fp_nsoli!(res_F_p_vec, F_p_vec) = Res_Fp!(res_F_p_vec,F_p_vec, gamma_dot_p, gamma_p, F, h0, xi_0, F_p)

#Res_Fp_nsoli!(F_p_vec, res_F_p_vec)

krylov_dims = 4
sol = nsoli(Res_Fp_nsoli!, F_p_vec, F_p_vec, zeros(length(F_p_vec), krylov_dims))
println()
@show sol.history

