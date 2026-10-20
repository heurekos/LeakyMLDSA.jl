# Values based on the upper bound n_{inf,upper} derived in Section 4.3 of
# https://heurekos.github.io/LeakyMLDSA.jl/tches2027_1-paper208.pdf,
# adjusted where necessary to match the experimental results.
const N_INF_UPPER = Dict(
    (256, 2, 39) => Dict(
        3 =>     1_500_000, # adjusted
        4 =>         1_230,
        5 =>         2_555,
        6 =>         5_209,
        7 =>        10_518,
        8 =>        12_841,
    ),
    (256, 4, 49) => Dict(
        4 =>     3_500_000, # adjusted
        5 =>         2_357,
        6 =>         4_820,
        7 =>         9_748,
        8 =>        19_604,
        9 =>        30_076,
    ),
    (256, 2, 60) => Dict(
        3 => 3_000_000_000, # adjusted
        4 =>         2_500, # adjusted
        5 =>         2_008,
        6 =>         4_119,
        7 =>         8_343,
        8 =>        15_734,
    ),
)

"""
    n_inf_hint(mldsa)

Generously estimate the number of informative signatures sufficient for key recovery.
"""
function n_inf_hint(mldsa::MLDSA)
    (; n, eta, tau, lambda, p_err) = mldsa

    n_inf_upper = get(N_INF_UPPER, (n, eta, tau), nothing)
    isnothing(n_inf_upper) && return

    (lambda_min, lambda_max) = extrema(keys(n_inf_upper))
    lambda < lambda_min && return

    scale_err = inv(1 - 2 * sqrt((1 - p_err) * p_err))
    return ceil(Int, scale_err * n_inf_upper[min(lambda, lambda_max)])
end
