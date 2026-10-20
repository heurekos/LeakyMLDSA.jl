using LeakyMLDSA: dot, leakage

for p_err in [0.0, 0.1]
    for MLDSAParameterSet in [MLDSA44, MLDSA65, MLDSA87], lambda in 4:9

        @testset "$MLDSAParameterSet: sanity checks (p_err=$p_err, λ=$lambda)" begin
            n_sig = 10

            mldsa = MLDSAParameterSet(; p_err, lambda)
            key = generate_key(mldsa)

            @test key_guess(mldsa, key) == key

            for _ in 1:n_sig
                (c, z, b) = generate_leaky_signature(mldsa, key)
                y = z - dot(c, key)

                @test is_informative(mldsa, z)
                @test leakage(mldsa, y) == !iszero(y & (1 << lambda))
                iszero(p_err) && @test b == leakage(mldsa, y)
            end

            sigs = Signatures(mldsa; count = n_sig)

            @test length(sigs) == n_sig
            @test key_violations(sigs, sigs.key) == 0
            iszero(p_err) && @test sig_violations(sigs, sigs.key) == 0

            for (c, z) in zip(sigs.cs, sigs.zs)
                y = z - dot(c, key)

                @test is_informative(mldsa, z)
                @test leakage(mldsa, y) == !iszero(y & (1 << lambda))
            end

            sigs_copy = Signatures(mldsa, sigs.cs, sigs.zs, falses(length(sigs)))

            @test sigs.cs == sigs_copy.cs
            @test sigs.zs == sigs_copy.zs
        end
    end
end
