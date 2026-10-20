for p_err in [0.0, 0.1]
    for MLDSAParameterSet in [MLDSA44, MLDSA65, MLDSA87], lambda in 4:9
        (MLDSAParameterSet, lambda) == (MLDSA65, 4) && continue

        @testset "$MLDSAParameterSet: NLP attack (p_err=$p_err, λ=$lambda)" begin
            mldsa = MLDSAParameterSet(; p_err, lambda)
            sigs = Signatures(mldsa; count = n_inf_hint(mldsa), seed = 0)
            result = run_attack(NLPAttack(sigs; timeout = 10))

            @test attack_succeeded(result)
            iszero(p_err) && @test sig_violations(result) == 0
        end
    end
end
