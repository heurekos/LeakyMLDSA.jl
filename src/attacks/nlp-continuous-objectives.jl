import SpecialFunctions: erf

"""
    psi_none()

Zero penalty.
"""
function psi_none()
    return function(_...)
        return (0.0, 0.0)
    end
end

"""
    psi_normal(; k)

Step-function approximation via reflected normal CDF.
"""
function psi_normal(; k = sqrt(pi / 2))
    k /= sqrt(2)
    return function(x)
        t = k * x
        psi0 = 0.5 + 0.5 * erf(-t)
        psi1 = -k / sqrt(pi) * exp(-t^2)
        return (psi0, psi1)
    end
end

"""
    psi_logistic(; k)

Step-function approximation via reflected logistic CDF.
"""
function psi_logistic(; k = 2.0)
    return function(x)
        t = exp(k * x)
        psi0 = 1.0 / (1.0 + t)
        psi1 = -k * t * psi0^2
        return (psi0, psi1)
    end
end

"""
    psi_cauchy(; k)

Step-function approximation via reflected Cauchy CDF.
"""
function psi_cauchy(; k = pi / 2)
    return function(x)
        t = k * x
        psi0 = 0.5 + atan(-t) / pi
        psi1 = -k / (pi * (1.0 + t^2))
        return (psi0, psi1)
    end
end

"""
    psi_sin(; w)

Sine wave penalty for integer constraints.
"""
function psi_sin(; w = 1.0)
    return function(x)
        (_sin, _cos) = sincospi(x)
        psi0 = w * _sin
        psi1 = w * pi * _cos
        return (psi0, psi1)
    end
end

"""
    psi_box(psi; w)

Box constraint wrapper.
"""
function psi_box(psi; w = 1.0)
    return function(x, l, u)
        (psi0_l, psi1_l) = psi(x - l)
        (psi0_u, psi1_u) = psi(u - x)
        psi0 = w * (psi0_l + psi0_u)
        psi1 = w * (psi1_l - psi1_u)
        return (psi0, psi1)
    end
end

"""
    psi_square(psi)

Square penalty wrapper.
"""
function psi_square(psi)
    return function(x)
        (psi0, psi1) = psi(x)
        return (psi0^2, 2 * psi0 * psi1)
    end
end
