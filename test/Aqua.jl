import Aqua

@testset "Aqua.jl" begin
    Aqua.test_all(LeakyMLDSA; unbound_args = false)
end
