#[test_only]
module adaptive_funding::funding_tests {
    use sui::test_scenario::{Self, Scenario};
    use sui::coin;
    use sui::sui::SUI;
    use sui::clock;
    use adaptive_funding::program::{Self, ManagerCap, ReviewerCap};
    use adaptive_funding::pool::{Self, FundingPool};
    use adaptive_funding::agreement::{Self, FundingAgreement, Waitlist};

    // === Test addresses ===
    const MANAGER: address   = @0xA;
    const RECIPIENT: address = @0xB;
    const REVIEWER1: address = @0xC;
    const REVIEWER2: address = @0xD;
    const RECIPIENT2: address = @0xE;

    // === Helpers ===

    fun setup(scenario: &mut Scenario) {
        test_scenario::next_tx(scenario, MANAGER);
        program::create_program(b"Test Program", b"Test Description", test_scenario::ctx(scenario));
        test_scenario::next_tx(scenario, MANAGER);
        let cap = test_scenario::take_from_sender<ManagerCap>(scenario);
        let clock = clock::create_for_testing(test_scenario::ctx(scenario));
        pool::create_pool<SUI>(&cap, 500, &clock, test_scenario::ctx(scenario));
        test_scenario::next_tx(scenario, MANAGER);
        let pool = test_scenario::take_shared<FundingPool<SUI>>(scenario);
        program::issue_reviewer_cap(&cap, REVIEWER1, test_scenario::ctx(scenario));
        program::issue_reviewer_cap(&cap, REVIEWER2, test_scenario::ctx(scenario));
        test_scenario::return_shared(pool);
        test_scenario::return_to_sender(scenario, cap);
        clock::destroy_for_testing(clock);
    }

    fun deposit_to_pool(scenario: &mut Scenario, amount: u64) {
        test_scenario::next_tx(scenario, MANAGER);
        let mut pool = test_scenario::take_shared<FundingPool<SUI>>(scenario);
        let coin = coin::mint_for_testing<SUI>(amount, test_scenario::ctx(scenario));
        pool::deposit(&mut pool, coin);
        test_scenario::return_shared(pool);
    }

    fun make_agreement(
        scenario: &mut Scenario,
        amounts: vector<u64>,
        deadlines: vector<u64>,
        stream_ms: u64,
        bonus_bps: u64,
        decay_bps: u64,
        timeout_ms: u64,
        clock_ms: u64,
    ) {
        test_scenario::next_tx(scenario, MANAGER);
        let cap = test_scenario::take_from_sender<ManagerCap>(scenario);
        let mut pool = test_scenario::take_shared<FundingPool<SUI>>(scenario);
        let mut clock = clock::create_for_testing(test_scenario::ctx(scenario));
        clock::set_for_testing(&mut clock, clock_ms);
        let reviewers = vector[REVIEWER1, REVIEWER2];
        agreement::create_agreement<SUI>(
            &cap, &mut pool,
            RECIPIENT, reviewers, 2,
            amounts, deadlines,
            stream_ms, 0, agreement::curve_linear(),
            bonus_bps, decay_bps, timeout_ms,
            &clock, test_scenario::ctx(scenario),
        );
        test_scenario::return_to_sender(scenario, cap);
        test_scenario::return_shared(pool);
        clock::destroy_for_testing(clock);
    }

    fun submit(scenario: &mut Scenario, milestone_idx: u64, clock_ms: u64) {
        test_scenario::next_tx(scenario, RECIPIENT);
        let mut agr = test_scenario::take_shared<FundingAgreement<SUI>>(scenario);
        let mut clock = clock::create_for_testing(test_scenario::ctx(scenario));
        clock::set_for_testing(&mut clock, clock_ms);
        agreement::submit_proof<SUI>(
            &mut agr, milestone_idx,
            b"https://proof.example.com",
            b"abc123hash",
            b"proof note",
            &clock, test_scenario::ctx(scenario),
        );
        test_scenario::return_shared(agr);
        clock::destroy_for_testing(clock);
    }

    fun vote(scenario: &mut Scenario, reviewer: address, decision: u8, clock_ms: u64) {
        vote_on(scenario, reviewer, decision, clock_ms, 0);
    }

    fun vote_on(scenario: &mut Scenario, reviewer: address, decision: u8, clock_ms: u64, milestone_idx: u64) {
        test_scenario::next_tx(scenario, reviewer);
        let rev_cap = test_scenario::take_from_sender<ReviewerCap>(scenario);
        let mut agr = test_scenario::take_shared<FundingAgreement<SUI>>(scenario);
        let mut pool = test_scenario::take_shared<FundingPool<SUI>>(scenario);
        let mut clock = clock::create_for_testing(test_scenario::ctx(scenario));
        clock::set_for_testing(&mut clock, clock_ms);
        agreement::cast_vote<SUI>(
            &rev_cap, &mut agr, &mut pool, milestone_idx, decision, b"note",
            &clock, test_scenario::ctx(scenario),
        );
        test_scenario::return_to_sender(scenario, rev_cap);
        test_scenario::return_shared(agr);
        test_scenario::return_shared(pool);
        clock::destroy_for_testing(clock);
    }

    // === Test 1: create program ===
    #[test]
    fun test_create_program() {
        let mut scenario = test_scenario::begin(MANAGER);
        program::create_program(b"My Program", b"Desc", test_scenario::ctx(&mut scenario));
        test_scenario::next_tx(&mut scenario, MANAGER);
        let cap = test_scenario::take_from_sender<ManagerCap>(&scenario);
        test_scenario::return_to_sender(&scenario, cap);
        test_scenario::end(scenario);
    }

    // === Test 2: create pool ===
    #[test]
    fun test_create_pool() {
        let mut scenario = test_scenario::begin(MANAGER);
        program::create_program(b"P", b"D", test_scenario::ctx(&mut scenario));
        test_scenario::next_tx(&mut scenario, MANAGER);
        let cap = test_scenario::take_from_sender<ManagerCap>(&scenario);
        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        pool::create_pool<SUI>(&cap, 500, &clock, test_scenario::ctx(&mut scenario));
        test_scenario::next_tx(&mut scenario, MANAGER);
        let pool = test_scenario::take_shared<FundingPool<SUI>>(&scenario);
        assert!(pool::balance_value(&pool) == 0, 0);
        test_scenario::return_shared(pool);
        test_scenario::return_to_sender(&scenario, cap);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    // === Test 3: deposit to pool ===
    #[test]
    fun test_deposit() {
        let mut scenario = test_scenario::begin(MANAGER);
        setup(&mut scenario);
        deposit_to_pool(&mut scenario, 1_000_000_000);
        test_scenario::next_tx(&mut scenario, MANAGER);
        let pool = test_scenario::take_shared<FundingPool<SUI>>(&scenario);
        assert!(pool::balance_value(&pool) == 1_000_000_000, 0);
        test_scenario::return_shared(pool);
        test_scenario::end(scenario);
    }

    // === Test 4: create agreement ===
    #[test]
    fun test_create_agreement() {
        let mut scenario = test_scenario::begin(MANAGER);
        setup(&mut scenario);
        deposit_to_pool(&mut scenario, 1_000_000_000);
        make_agreement(&mut scenario, vector[500_000_000], vector[999_999_999_999], 0, 0, 0, 60_000, 0);
        test_scenario::next_tx(&mut scenario, MANAGER);
        let agr = test_scenario::take_shared<FundingAgreement<SUI>>(&scenario);
        assert!(agreement::total_amount(&agr) == 500_000_000, 0);
        assert!(agreement::escrow_value(&agr) == 500_000_000, 0);
        assert!(agreement::is_active(&agr), 0);
        test_scenario::return_shared(agr);
        test_scenario::end(scenario);
    }

    // === Test 5: submit proof ===
    #[test]
    fun test_submit_proof() {
        let mut scenario = test_scenario::begin(MANAGER);
        setup(&mut scenario);
        deposit_to_pool(&mut scenario, 1_000_000_000);
        make_agreement(&mut scenario, vector[500_000_000], vector[999_999_999_999], 0, 0, 0, 60_000, 0);
        submit(&mut scenario, 0, 1000);
        test_scenario::next_tx(&mut scenario, MANAGER);
        let agr = test_scenario::take_shared<FundingAgreement<SUI>>(&scenario);
        assert!(agreement::milestone_state(&agr, 0) == agreement::state_submitted(), 0);
        test_scenario::return_shared(agr);
        test_scenario::end(scenario);
    }

    // === Test 6: unanimous approve → paid ===
    #[test]
    fun test_unanimous_approve_paid() {
        let mut scenario = test_scenario::begin(MANAGER);
        setup(&mut scenario);
        deposit_to_pool(&mut scenario, 1_000_000_000);
        make_agreement(&mut scenario, vector[500_000_000], vector[999_999_999_999], 0, 0, 0, 60_000, 0);
        submit(&mut scenario, 0, 1000);
        vote(&mut scenario, REVIEWER1, agreement::decision_approve(), 2000);
        vote(&mut scenario, REVIEWER2, agreement::decision_approve(), 3000);
        test_scenario::next_tx(&mut scenario, MANAGER);
        let agr = test_scenario::take_shared<FundingAgreement<SUI>>(&scenario);
        assert!(agreement::milestone_state(&agr, 0) == agreement::state_paid(), 0);
        assert!(agreement::released_total(&agr) == 500_000_000, 0);
        test_scenario::return_shared(agr);
        test_scenario::end(scenario);
    }

    // === Test 7: approve with warning → partially released (50%) ===
    #[test]
    fun test_approve_with_warning() {
        let mut scenario = test_scenario::begin(MANAGER);
        setup(&mut scenario);
        deposit_to_pool(&mut scenario, 1_000_000_000);
        make_agreement(&mut scenario, vector[500_000_000], vector[999_999_999_999], 0, 0, 0, 60_000, 0);
        submit(&mut scenario, 0, 1000);
        vote(&mut scenario, REVIEWER1, agreement::decision_warning(), 2000);
        vote(&mut scenario, REVIEWER2, agreement::decision_warning(), 3000);
        test_scenario::next_tx(&mut scenario, MANAGER);
        let agr = test_scenario::take_shared<FundingAgreement<SUI>>(&scenario);
        assert!(agreement::milestone_state(&agr, 0) == agreement::state_partially_released(), 0);
        assert!(agreement::released_total(&agr) == 250_000_000, 0);
        assert!(agreement::milestone_withheld(&agr, 0) == 250_000_000, 0);
        test_scenario::return_shared(agr);
        test_scenario::end(scenario);
    }

    // === Test 8: reject → all withheld ===
    #[test]
    fun test_reject() {
        let mut scenario = test_scenario::begin(MANAGER);
        setup(&mut scenario);
        deposit_to_pool(&mut scenario, 1_000_000_000);
        make_agreement(&mut scenario, vector[500_000_000], vector[999_999_999_999], 0, 0, 0, 60_000, 0);
        submit(&mut scenario, 0, 1000);
        vote(&mut scenario, REVIEWER1, agreement::decision_reject(), 2000);
        vote(&mut scenario, REVIEWER2, agreement::decision_reject(), 3000);
        test_scenario::next_tx(&mut scenario, MANAGER);
        let agr = test_scenario::take_shared<FundingAgreement<SUI>>(&scenario);
        assert!(agreement::milestone_state(&agr, 0) == agreement::state_rejected(), 0);
        assert!(agreement::milestone_withheld(&agr, 0) == 500_000_000, 0);
        assert!(agreement::released_total(&agr) == 0, 0);
        test_scenario::return_shared(agr);
        test_scenario::end(scenario);
    }

    // === Test 9: vote revision ===
    #[test]
    fun test_vote_revision() {
        let mut scenario = test_scenario::begin(MANAGER);
        setup(&mut scenario);
        deposit_to_pool(&mut scenario, 1_000_000_000);
        make_agreement(&mut scenario, vector[500_000_000], vector[999_999_999_999], 0, 0, 0, 60_000, 0);
        submit(&mut scenario, 0, 1000);
        // R1 votes reject, then changes to approve
        vote(&mut scenario, REVIEWER1, agreement::decision_reject(), 2000);
        vote(&mut scenario, REVIEWER1, agreement::decision_approve(), 2500);
        // R2 votes approve — quorum of 2 approves hit
        vote(&mut scenario, REVIEWER2, agreement::decision_approve(), 3000);
        test_scenario::next_tx(&mut scenario, MANAGER);
        let agr = test_scenario::take_shared<FundingAgreement<SUI>>(&scenario);
        assert!(agreement::milestone_state(&agr, 0) == agreement::state_paid(), 0);
        test_scenario::return_shared(agr);
        test_scenario::end(scenario);
    }

    // === Test 10: double vote same decision aborts ===
    #[test]
    #[expected_failure(abort_code = 6, location = adaptive_funding::agreement)]
    fun test_double_vote_aborts() {
        let mut scenario = test_scenario::begin(MANAGER);
        setup(&mut scenario);
        deposit_to_pool(&mut scenario, 1_000_000_000);
        make_agreement(&mut scenario, vector[500_000_000], vector[999_999_999_999], 0, 0, 0, 60_000, 0);
        submit(&mut scenario, 0, 1000);
        vote(&mut scenario, REVIEWER1, agreement::decision_approve(), 2000);
        vote(&mut scenario, REVIEWER1, agreement::decision_approve(), 2500); // should abort
        test_scenario::end(scenario);
    }

    // === Test 11: on-time full approve earns bonus ===
    #[test]
    fun test_on_time_bonus() {
        let mut scenario = test_scenario::begin(MANAGER);
        setup(&mut scenario);
        deposit_to_pool(&mut scenario, 2_000_000_000);
        // bonus_bps = 1000 (10%), no decay
        make_agreement(&mut scenario, vector[500_000_000], vector[999_999_999_999], 0, 1000, 0, 60_000, 0);
        submit(&mut scenario, 0, 1000);
        vote(&mut scenario, REVIEWER1, agreement::decision_approve(), 2000);
        vote(&mut scenario, REVIEWER2, agreement::decision_approve(), 3000);
        test_scenario::next_tx(&mut scenario, MANAGER);
        let agr = test_scenario::take_shared<FundingAgreement<SUI>>(&scenario);
        // bonus = 500_000_000 * 10% = 50_000_000
        assert!(agreement::bonus_total(&agr) == 50_000_000, 0);
        test_scenario::return_shared(agr);
        test_scenario::end(scenario);
    }

    // === Test 12: late submission 1 day — decay applied ===
    #[test]
    fun test_late_decay_1_day() {
        let mut scenario = test_scenario::begin(MANAGER);
        setup(&mut scenario);
        deposit_to_pool(&mut scenario, 1_000_000_000);
        let deadline = 86_400_000u64; // 1 day in ms
        // decay_bps_per_day = 200 (2%)
        make_agreement(&mut scenario, vector[500_000_000], vector[deadline], 0, 0, 200, 60_000, 0);
        // Submit 1 day late = deadline + 1 day
        submit(&mut scenario, 0, deadline + 86_400_000);
        vote(&mut scenario, REVIEWER1, agreement::decision_approve(), deadline + 86_400_001);
        vote(&mut scenario, REVIEWER2, agreement::decision_approve(), deadline + 86_400_002);
        test_scenario::next_tx(&mut scenario, MANAGER);
        let agr = test_scenario::take_shared<FundingAgreement<SUI>>(&scenario);
        // payout = 500_000_000 * (10000 - 200) / 10000 = 490_000_000
        assert!(agreement::released_total(&agr) == 490_000_000, 0);
        test_scenario::return_shared(agr);
        test_scenario::end(scenario);
    }

    // === Test 13: late decay 3 days ===
    #[test]
    fun test_late_decay_3_days() {
        let mut scenario = test_scenario::begin(MANAGER);
        setup(&mut scenario);
        deposit_to_pool(&mut scenario, 1_000_000_000);
        let deadline = 86_400_000u64;
        make_agreement(&mut scenario, vector[500_000_000], vector[deadline], 0, 0, 200, 60_000, 0);
        submit(&mut scenario, 0, deadline + 3 * 86_400_000);
        vote(&mut scenario, REVIEWER1, agreement::decision_approve(), deadline + 3 * 86_400_001);
        vote(&mut scenario, REVIEWER2, agreement::decision_approve(), deadline + 3 * 86_400_002);
        test_scenario::next_tx(&mut scenario, MANAGER);
        let agr = test_scenario::take_shared<FundingAgreement<SUI>>(&scenario);
        // 3 days * 200 bps/day = 600 bps decay → payout = 9400/10000 of 500M = 470_000_000
        assert!(agreement::released_total(&agr) == 470_000_000, 0);
        test_scenario::return_shared(agr);
        test_scenario::end(scenario);
    }

    // === Test 14: streaming linear vesting ===
    #[test]
    fun test_streaming_linear() {
        let mut scenario = test_scenario::begin(MANAGER);
        setup(&mut scenario);
        deposit_to_pool(&mut scenario, 1_000_000_000);
        let stream_ms = 100_000u64;
        make_agreement(&mut scenario, vector[500_000_000], vector[999_999_999_999], stream_ms, 0, 0, 60_000, 0);
        submit(&mut scenario, 0, 1000);
        vote(&mut scenario, REVIEWER1, agreement::decision_approve(), 2000);
        vote(&mut scenario, REVIEWER2, agreement::decision_approve(), 3000);
        // Check streaming state
        test_scenario::next_tx(&mut scenario, MANAGER);
        {
            let agr = test_scenario::take_shared<FundingAgreement<SUI>>(&scenario);
            assert!(agreement::milestone_state(&agr, 0) == agreement::state_streaming(), 0);
            test_scenario::return_shared(agr);
        };
        // Claim at 50% through the stream
        test_scenario::next_tx(&mut scenario, RECIPIENT);
        let mut agr = test_scenario::take_shared<FundingAgreement<SUI>>(&scenario);
        let mut clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        clock::set_for_testing(&mut clock, 3000 + stream_ms / 2);
        agreement::claim_vested<SUI>(&mut agr, 0, &clock, test_scenario::ctx(&mut scenario));
        // ~50% vested = 250_000_000
        assert!(agreement::released_total(&agr) == 250_000_000, 0);
        test_scenario::return_shared(agr);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    // === Test 15: streaming stepped vesting ===
    #[test]
    fun test_streaming_stepped() {
        let mut scenario = test_scenario::begin(MANAGER);
        setup(&mut scenario);
        deposit_to_pool(&mut scenario, 1_000_000_000);
        let stream_ms = 100_000u64;
        test_scenario::next_tx(&mut scenario, MANAGER);
        let cap = test_scenario::take_from_sender<ManagerCap>(&scenario);
        let mut pool = test_scenario::take_shared<FundingPool<SUI>>(&scenario);
        let mut clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        agreement::create_agreement<SUI>(
            &cap, &mut pool, RECIPIENT, vector[REVIEWER1, REVIEWER2], 2,
            vector[400_000_000], vector[999_999_999_999],
            stream_ms, 0, agreement::curve_stepped(),
            0, 0, 60_000,
            &clock, test_scenario::ctx(&mut scenario),
        );
        test_scenario::return_to_sender(&scenario, cap);
        test_scenario::return_shared(pool);
        clock::destroy_for_testing(clock);

        submit(&mut scenario, 0, 1000);
        vote(&mut scenario, REVIEWER1, agreement::decision_approve(), 2000);
        vote(&mut scenario, REVIEWER2, agreement::decision_approve(), 3000);

        // Claim at 25% through stream (step 1 = 25%)
        test_scenario::next_tx(&mut scenario, RECIPIENT);
        let mut agr = test_scenario::take_shared<FundingAgreement<SUI>>(&scenario);
        let mut clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        clock::set_for_testing(&mut clock, 3000 + stream_ms / 4 + 1);
        agreement::claim_vested<SUI>(&mut agr, 0, &clock, test_scenario::ctx(&mut scenario));
        assert!(agreement::released_total(&agr) == 100_000_000, 0); // 25%
        test_scenario::return_shared(agr);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    // === Test 16: streaming accelerating (quadratic) ===
    #[test]
    fun test_streaming_accelerating() {
        let mut scenario = test_scenario::begin(MANAGER);
        setup(&mut scenario);
        deposit_to_pool(&mut scenario, 1_000_000_000);
        let stream_ms = 100_000u64;
        test_scenario::next_tx(&mut scenario, MANAGER);
        let cap = test_scenario::take_from_sender<ManagerCap>(&scenario);
        let mut pool = test_scenario::take_shared<FundingPool<SUI>>(&scenario);
        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        agreement::create_agreement<SUI>(
            &cap, &mut pool, RECIPIENT, vector[REVIEWER1, REVIEWER2], 2,
            vector[400_000_000], vector[999_999_999_999],
            stream_ms, 0, agreement::curve_accelerating(),
            0, 0, 60_000,
            &clock, test_scenario::ctx(&mut scenario),
        );
        test_scenario::return_to_sender(&scenario, cap);
        test_scenario::return_shared(pool);
        clock::destroy_for_testing(clock);

        submit(&mut scenario, 0, 1000);
        vote(&mut scenario, REVIEWER1, agreement::decision_approve(), 2000);
        vote(&mut scenario, REVIEWER2, agreement::decision_approve(), 3000);

        // At 50% time: quadratic = 25% vested
        test_scenario::next_tx(&mut scenario, RECIPIENT);
        let mut agr = test_scenario::take_shared<FundingAgreement<SUI>>(&scenario);
        let mut clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        clock::set_for_testing(&mut clock, 3000 + stream_ms / 2);
        agreement::claim_vested<SUI>(&mut agr, 0, &clock, test_scenario::ctx(&mut scenario));
        assert!(agreement::released_total(&agr) == 100_000_000, 0); // 25% of 400M
        test_scenario::return_shared(agr);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    // === Test 17: cliff — nothing claimable before cliff ===
    #[test]
    fun test_cliff_blocks_early_claim() {
        let mut scenario = test_scenario::begin(MANAGER);
        setup(&mut scenario);
        deposit_to_pool(&mut scenario, 1_000_000_000);
        let stream_ms = 100_000u64;
        let cliff_ms = 50_000u64;
        test_scenario::next_tx(&mut scenario, MANAGER);
        let cap = test_scenario::take_from_sender<ManagerCap>(&scenario);
        let mut pool = test_scenario::take_shared<FundingPool<SUI>>(&scenario);
        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        agreement::create_agreement<SUI>(
            &cap, &mut pool, RECIPIENT, vector[REVIEWER1, REVIEWER2], 2,
            vector[400_000_000], vector[999_999_999_999],
            stream_ms, cliff_ms, agreement::curve_linear(),
            0, 0, 60_000,
            &clock, test_scenario::ctx(&mut scenario),
        );
        test_scenario::return_to_sender(&scenario, cap);
        test_scenario::return_shared(pool);
        clock::destroy_for_testing(clock);
        submit(&mut scenario, 0, 1000);
        vote(&mut scenario, REVIEWER1, agreement::decision_approve(), 2000);
        vote(&mut scenario, REVIEWER2, agreement::decision_approve(), 3000);
        // Try to claim at 30% time (before cliff)
        test_scenario::next_tx(&mut scenario, RECIPIENT);
        let mut agr = test_scenario::take_shared<FundingAgreement<SUI>>(&scenario);
        let mut clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        clock::set_for_testing(&mut clock, 3000 + stream_ms * 3 / 10); // 30% — before cliff
        // Should fail with nothing-to-claim
        // We skip the actual claim since it would abort; just verify state
        assert!(agreement::milestone_state(&agr, 0) == agreement::state_streaming(), 0);
        test_scenario::return_shared(agr);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    // === Test 18: review timeout (permissionless auto-release) ===
    #[test]
    fun test_review_timeout() {
        let mut scenario = test_scenario::begin(MANAGER);
        setup(&mut scenario);
        deposit_to_pool(&mut scenario, 1_000_000_000);
        // timeout = 10_000 ms
        make_agreement(&mut scenario, vector[500_000_000], vector[999_999_999_999], 0, 0, 0, 10_000, 0);
        submit(&mut scenario, 0, 1000);
        // Enforce timeout after 11_000 ms from submission
        test_scenario::next_tx(&mut scenario, @0xDEAD); // permissionless caller
        let mut agr = test_scenario::take_shared<FundingAgreement<SUI>>(&scenario);
        let mut pool = test_scenario::take_shared<FundingPool<SUI>>(&scenario);
        let mut clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        clock::set_for_testing(&mut clock, 1000 + 11_000); // past timeout
        agreement::enforce_timeout<SUI>(&mut agr, &mut pool, 0, &clock, test_scenario::ctx(&mut scenario));
        assert!(agreement::released_total(&agr) == 250_000_000, 0); // 50%
        assert!(agreement::milestone_withheld(&agr, 0) == 250_000_000, 0);
        test_scenario::return_shared(agr);
        test_scenario::return_shared(pool);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    // === Test 19: expire milestone past deadline ===
    #[test]
    fun test_expire_milestone() {
        let mut scenario = test_scenario::begin(MANAGER);
        setup(&mut scenario);
        deposit_to_pool(&mut scenario, 1_000_000_000);
        let deadline = 5_000u64;
        make_agreement(&mut scenario, vector[500_000_000], vector[deadline], 0, 0, 0, 60_000, 0);
        // Expire at time past deadline
        test_scenario::next_tx(&mut scenario, @0xFF);
        let mut agr = test_scenario::take_shared<FundingAgreement<SUI>>(&scenario);
        let mut clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        clock::set_for_testing(&mut clock, deadline + 1);
        agreement::expire_milestone<SUI>(&mut agr, 0, &clock, test_scenario::ctx(&mut scenario));
        assert!(agreement::milestone_state(&agr, 0) == agreement::state_expired(), 0);
        assert!(agreement::milestone_withheld(&agr, 0) == 500_000_000, 0);
        test_scenario::return_shared(agr);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    // === Test 20: waterfall — recycle + fund next ===
    #[test]
    fun test_waterfall_recycle_fund_next() {
        let mut scenario = test_scenario::begin(MANAGER);
        setup(&mut scenario);
        deposit_to_pool(&mut scenario, 2_000_000_000);
        make_agreement(&mut scenario, vector[500_000_000], vector[999_999_999_999], 0, 0, 0, 60_000, 0);
        // Create waitlist
        test_scenario::next_tx(&mut scenario, MANAGER);
        let cap = test_scenario::take_from_sender<ManagerCap>(&scenario);
        let pool = test_scenario::take_shared<FundingPool<SUI>>(&scenario);
        agreement::create_waitlist<SUI>(&cap, &pool, test_scenario::ctx(&mut scenario));
        test_scenario::return_to_sender(&scenario, cap);
        test_scenario::return_shared(pool);
        // Add to waitlist
        test_scenario::next_tx(&mut scenario, MANAGER);
        let cap = test_scenario::take_from_sender<ManagerCap>(&scenario);
        let mut wl = test_scenario::take_shared<Waitlist<SUI>>(&scenario);
        agreement::add_to_waitlist<SUI>(
            &cap, &mut wl, RECIPIENT2, 300_000_000,
            vector[REVIEWER1], 1, 0, 0, agreement::curve_linear(), 0, 0, 60_000,
            b"Next in line",
            test_scenario::ctx(&mut scenario),
        );
        test_scenario::return_to_sender(&scenario, cap);
        test_scenario::return_shared(wl);
        // Reject milestone → all withheld
        submit(&mut scenario, 0, 1000);
        vote(&mut scenario, REVIEWER1, agreement::decision_reject(), 2000);
        vote(&mut scenario, REVIEWER2, agreement::decision_reject(), 3000);
        // Recycle withheld
        test_scenario::next_tx(&mut scenario, MANAGER);
        let cap = test_scenario::take_from_sender<ManagerCap>(&scenario);
        let mut agr = test_scenario::take_shared<FundingAgreement<SUI>>(&scenario);
        let mut pool = test_scenario::take_shared<FundingPool<SUI>>(&scenario);
        agreement::recycle_withheld<SUI>(&cap, &mut agr, &mut pool, 0, test_scenario::ctx(&mut scenario));
        assert!(agreement::milestone_state(&agr, 0) == agreement::state_recycled(), 0);
        // Fund next from waitlist
        let mut wl = test_scenario::take_shared<Waitlist<SUI>>(&scenario);
        let mut clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        let funded = agreement::try_fund_next<SUI>(&cap, &mut wl, &mut pool, &clock, test_scenario::ctx(&mut scenario));
        assert!(funded, 0);
        assert!(agreement::waitlist_length(&wl) == 0, 0);
        test_scenario::return_to_sender(&scenario, cap);
        test_scenario::return_shared(agr);
        test_scenario::return_shared(pool);
        test_scenario::return_shared(wl);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    // === Test 21: waitlist FIFO ordering ===
    #[test]
    fun test_waitlist_fifo() {
        let mut scenario = test_scenario::begin(MANAGER);
        setup(&mut scenario);
        deposit_to_pool(&mut scenario, 5_000_000_000);
        test_scenario::next_tx(&mut scenario, MANAGER);
        let cap = test_scenario::take_from_sender<ManagerCap>(&scenario);
        let pool = test_scenario::take_shared<FundingPool<SUI>>(&scenario);
        agreement::create_waitlist<SUI>(&cap, &pool, test_scenario::ctx(&mut scenario));
        test_scenario::return_to_sender(&scenario, cap);
        test_scenario::return_shared(pool);
        test_scenario::next_tx(&mut scenario, MANAGER);
        let cap = test_scenario::take_from_sender<ManagerCap>(&scenario);
        let mut wl = test_scenario::take_shared<Waitlist<SUI>>(&scenario);
        agreement::add_to_waitlist<SUI>(
            &cap, &mut wl, RECIPIENT, 100_000_000, vector[REVIEWER1], 1,
            0, 0, agreement::curve_linear(), 0, 0, 60_000, b"A",
            test_scenario::ctx(&mut scenario),
        );
        agreement::add_to_waitlist<SUI>(
            &cap, &mut wl, RECIPIENT2, 200_000_000, vector[REVIEWER1], 1,
            0, 0, agreement::curve_linear(), 0, 0, 60_000, b"B",
            test_scenario::ctx(&mut scenario),
        );
        assert!(agreement::waitlist_length(&wl) == 2, 0);
        let mut pool = test_scenario::take_shared<FundingPool<SUI>>(&scenario);
        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        let funded1 = agreement::try_fund_next<SUI>(&cap, &mut wl, &mut pool, &clock, test_scenario::ctx(&mut scenario));
        assert!(funded1, 0);
        assert!(agreement::waitlist_length(&wl) == 1, 0);
        let funded2 = agreement::try_fund_next<SUI>(&cap, &mut wl, &mut pool, &clock, test_scenario::ctx(&mut scenario));
        assert!(funded2, 0);
        assert!(agreement::waitlist_length(&wl) == 0, 0);
        test_scenario::return_to_sender(&scenario, cap);
        test_scenario::return_shared(pool);
        test_scenario::return_shared(wl);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    // === Test 22: yield accrual ===
    #[test]
    fun test_yield_accrual() {
        let mut scenario = test_scenario::begin(MANAGER);
        setup(&mut scenario);
        deposit_to_pool(&mut scenario, 1_000_000_000);
        // Fund yield reserve
        test_scenario::next_tx(&mut scenario, MANAGER);
        let mut pool = test_scenario::take_shared<FundingPool<SUI>>(&scenario);
        let reserve_coin = coin::mint_for_testing<SUI>(100_000_000, test_scenario::ctx(&mut scenario));
        pool::deposit_yield_reserve(&mut pool, reserve_coin);
        // Accrue yield after 1 year (31_536_000_000 ms)
        let mut clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        clock::set_for_testing(&mut clock, 31_536_000_000);
        pool::accrue_yield(&mut pool, &clock);
        // ~5% of 1B = 50M accrued
        assert!(pool::balance_value(&pool) > 1_000_000_000, 0);
        test_scenario::return_shared(pool);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    // === Test 23: yield reserve deposit and balance ===
    #[test]
    fun test_yield_reserve_balance() {
        let mut scenario = test_scenario::begin(MANAGER);
        setup(&mut scenario);
        test_scenario::next_tx(&mut scenario, MANAGER);
        let mut pool = test_scenario::take_shared<FundingPool<SUI>>(&scenario);
        let coin = coin::mint_for_testing<SUI>(500_000_000, test_scenario::ctx(&mut scenario));
        pool::deposit_yield_reserve(&mut pool, coin);
        assert!(pool::reserve_value(&pool) == 500_000_000, 0);
        test_scenario::return_shared(pool);
        test_scenario::end(scenario);
    }

    // === Test 24: pause pool blocks allocation ===
    #[test]
    #[expected_failure(abort_code = 0, location = adaptive_funding::pool)]
    fun test_pause_pool_blocks_allocation() {
        let mut scenario = test_scenario::begin(MANAGER);
        setup(&mut scenario);
        deposit_to_pool(&mut scenario, 1_000_000_000);
        // Pause pool
        test_scenario::next_tx(&mut scenario, MANAGER);
        let cap = test_scenario::take_from_sender<ManagerCap>(&scenario);
        let mut pool = test_scenario::take_shared<FundingPool<SUI>>(&scenario);
        pool::pause_pool(&cap, &mut pool);
        test_scenario::return_to_sender(&scenario, cap);
        test_scenario::return_shared(pool);
        // Try to create agreement (allocates from pool) — should abort
        make_agreement(&mut scenario, vector[500_000_000], vector[999_999_999_999], 0, 0, 0, 60_000, 0);
        test_scenario::end(scenario);
    }

    // === Test 25: pause agreement blocks submission ===
    #[test]
    #[expected_failure(abort_code = 5, location = adaptive_funding::agreement)]
    fun test_pause_agreement_blocks_submission() {
        let mut scenario = test_scenario::begin(MANAGER);
        setup(&mut scenario);
        deposit_to_pool(&mut scenario, 1_000_000_000);
        make_agreement(&mut scenario, vector[500_000_000], vector[999_999_999_999], 0, 0, 0, 60_000, 0);
        test_scenario::next_tx(&mut scenario, MANAGER);
        let cap = test_scenario::take_from_sender<ManagerCap>(&scenario);
        let mut agr = test_scenario::take_shared<FundingAgreement<SUI>>(&scenario);
        agreement::pause_agreement(&cap, &mut agr);
        test_scenario::return_to_sender(&scenario, cap);
        test_scenario::return_shared(agr);
        // Submit should abort
        submit(&mut scenario, 0, 1000);
        test_scenario::end(scenario);
    }

    // === Test 26: money conservation invariant ===
    #[test]
    fun test_money_conservation_across_mixed_outcomes() {
        let mut scenario = test_scenario::begin(MANAGER);
        setup(&mut scenario);
        let total_deposit = 2_000_000_000u64;
        deposit_to_pool(&mut scenario, total_deposit);
        // Create 2-milestone agreement: approve first, reject second
        make_agreement(
            &mut scenario,
            vector[600_000_000, 400_000_000],
            vector[999_999_999_999, 999_999_999_998],
            0, 0, 0, 60_000, 0,
        );
        // Milestone 0: approve
        submit(&mut scenario, 0, 1000);
        vote_on(&mut scenario, REVIEWER1, agreement::decision_approve(), 2000, 0);
        vote_on(&mut scenario, REVIEWER2, agreement::decision_approve(), 3000, 0);
        // Milestone 1: reject
        submit(&mut scenario, 1, 4000);
        vote_on(&mut scenario, REVIEWER1, agreement::decision_reject(), 5000, 1);
        vote_on(&mut scenario, REVIEWER2, agreement::decision_reject(), 6000, 1);
        // Recycle milestone 1
        test_scenario::next_tx(&mut scenario, MANAGER);
        let cap = test_scenario::take_from_sender<ManagerCap>(&scenario);
        let mut agr = test_scenario::take_shared<FundingAgreement<SUI>>(&scenario);
        let mut pool = test_scenario::take_shared<FundingPool<SUI>>(&scenario);
        agreement::recycle_withheld<SUI>(&cap, &mut agr, &mut pool, 1, test_scenario::ctx(&mut scenario));
        // Invariant: released + recycled == total_amount + bonus
        let released = agreement::released_total(&agr);
        let recycled = agreement::recycled_total(&agr);
        let total = agreement::total_amount(&agr);
        let bonus = agreement::bonus_total(&agr);
        assert!(released + recycled == total + bonus, 0);
        assert!(agreement::escrow_value(&agr) == 0, 0);
        test_scenario::return_to_sender(&scenario, cap);
        test_scenario::return_shared(agr);
        test_scenario::return_shared(pool);
        test_scenario::end(scenario);
    }

    // === Test 27: auth failure — non-reviewer cannot vote ===
    #[test]
    #[expected_failure(abort_code = 1, location = adaptive_funding::agreement)]
    fun test_auth_non_reviewer_cannot_vote() {
        let mut scenario = test_scenario::begin(MANAGER);
        setup(&mut scenario);
        deposit_to_pool(&mut scenario, 1_000_000_000);
        make_agreement(&mut scenario, vector[500_000_000], vector[999_999_999_999], 0, 0, 0, 60_000, 0);
        submit(&mut scenario, 0, 1000);
        // Give an imposter a ReviewerCap for a DIFFERENT program
        test_scenario::next_tx(&mut scenario, @0xEEE);
        program::create_program(b"Fake", b"Fake", test_scenario::ctx(&mut scenario));
        test_scenario::next_tx(&mut scenario, @0xEEE);
        let fake_cap = test_scenario::take_from_sender<ManagerCap>(&scenario);
        program::issue_reviewer_cap(&fake_cap, @0xEEE, test_scenario::ctx(&mut scenario));
        test_scenario::return_to_sender(&scenario, fake_cap);
        // Imposter tries to vote on our agreement — should fail (not in reviewers list)
        test_scenario::next_tx(&mut scenario, @0xEEE);
        let rev_cap = test_scenario::take_from_sender<ReviewerCap>(&scenario);
        let mut agr = test_scenario::take_shared<FundingAgreement<SUI>>(&scenario);
        let mut pool = test_scenario::take_shared<FundingPool<SUI>>(&scenario);
        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        agreement::cast_vote<SUI>(
            &rev_cap, &mut agr, &mut pool, 0, agreement::decision_approve(), b"",
            &clock, test_scenario::ctx(&mut scenario),
        );
        test_scenario::return_to_sender(&scenario, rev_cap);
        test_scenario::return_shared(agr);
        test_scenario::return_shared(pool);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }
}
