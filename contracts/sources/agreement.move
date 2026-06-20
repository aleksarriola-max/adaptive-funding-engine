module adaptive_funding::agreement {
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::clock::Clock;
    use sui::event;
    use std::string::{Self, String};
    use adaptive_funding::program::{ManagerCap, ReviewerCap};
    use adaptive_funding::pool::{Self, FundingPool};
    use adaptive_funding::credential;

    // === Milestone state constants ===
    const STATE_LOCKED: u8          = 0;
    const STATE_OPEN: u8            = 1;
    const STATE_SUBMITTED: u8       = 2;
    const STATE_STREAMING: u8       = 3;
    const STATE_PAID: u8            = 4;
    const STATE_PARTIALLY_RELEASED: u8 = 5;
    const STATE_REJECTED: u8        = 6;
    const STATE_EXPIRED: u8         = 7;
    const STATE_RECYCLED: u8        = 8;

    // === Decision constants ===
    const DECISION_APPROVE: u8   = 0;
    const DECISION_WARNING: u8   = 1;
    const DECISION_REJECT: u8    = 2;
    const DECISION_SYSTEM: u8    = 3; // enforced timeout / auto-release

    // === Stream curve constants ===
    const CURVE_LINEAR: u8       = 0;
    const CURVE_STEPPED: u8      = 1;
    const CURVE_ACCELERATING: u8 = 2;

    // === Error codes ===
    const ENotRecipient: u64        = 0;
    const ENotReviewer: u64         = 1;
    const EMilestoneNotOpen: u64    = 2;
    const EMilestoneNotSubmitted: u64 = 3;
    const EAgreementPaused: u64     = 5;
    const EAlreadyVotedSame: u64    = 6;
    const EQuorumAlreadyReached: u64 = 7;
    const ENotExpired: u64          = 8;
    const ENotTimedOut: u64         = 9;
    const EEscrowNotEmpty: u64      = 10;
    const ENoWithheld: u64          = 11;
    const ENothingToClaim: u64      = 12;
    const EMilestoneNotRecyclable: u64 = 13;
    const EAgreementAlreadyDone: u64 = 14;
    const ENotStreaming: u64        = 15;
    const EPoolMismatch: u64        = 16;

    // === Time ===
    const MS_PER_DAY: u64  = 86_400_000;
    const BASIS_POINTS: u64 = 10_000;

    // === Embedded types ===

    public struct Submission has store, drop {
        url: String,
        sha256_hash: vector<u8>,
        note: String,
        submitted_at_ms: u64,
    }

    public struct ReviewVote has store, drop {
        reviewer: address,
        decision: u8,
        note: String,
        voted_at_ms: u64,
    }

    public struct ApprovalRecord has store, drop {
        decision: u8,
        note: String,
        decided_at_ms: u64,
        reviewer: address, // 0x0 = system/timeout
    }

    public struct StreamConfig has store, drop {
        total_vesting: u64,
        claimed: u64,
        start_ms: u64,
        duration_ms: u64,
        cliff_ms: u64,
        curve: u8,
        decision: u8,
    }

    public struct AdaptivePolicy has store, copy, drop {
        stream_duration_ms: u64,
        cliff_ms: u64,
        curve: u8,
        bonus_bps: u64,
        late_decay_bps_per_day: u64,
        review_timeout_ms: u64,
    }

    public struct Milestone has store {
        amount: u64,
        deadline_ms: u64,
        state: u8,
        submission: Option<Submission>,
        votes: vector<ReviewVote>,
        approval: Option<ApprovalRecord>,
        stream: Option<StreamConfig>,
        withheld: u64,
    }

    // === Main objects ===

    public struct FundingAgreement<phantom T> has key {
        id: UID,
        program_id: address,
        pool_id: address,
        recipient: address,
        reviewers: vector<address>,
        quorum_threshold: u64,
        milestones: vector<Milestone>,
        policy: AdaptivePolicy,
        escrow: Balance<T>,
        paused: bool,
        active: bool,
        total_amount: u64,
        released_total: u64,
        recycled_total: u64,
        bonus_total: u64,
        on_time_count: u64,
        settled_count: u64,
    }

    public struct DisbursementReceipt has key {
        id: UID,
        agreement_id: address,
        milestone_index: u64,
        amount_paid: u64,
        bonus_paid: u64,
        decision: u8,
        decided_at_ms: u64,
    }

    public struct QueuedRequest has store, drop {
        recipient: address,
        amount: u64,
        reviewers: vector<address>,
        quorum_threshold: u64,
        policy: AdaptivePolicy,
        description: String,
    }

    public struct Waitlist<phantom T> has key {
        id: UID,
        program_id: address,
        pool_id: address,
        queue: vector<QueuedRequest>,
        total_funded: u64,
    }

    // === Events ===

    public struct AgreementCreated has copy, drop {
        agreement_id: address,
        program_id: address,
        recipient: address,
        total_amount: u64,
    }

    public struct ProofSubmitted has copy, drop {
        agreement_id: address,
        milestone_index: u64,
        sha256_hash: vector<u8>,
        submitted_at_ms: u64,
    }

    public struct VoteCast has copy, drop {
        agreement_id: address,
        milestone_index: u64,
        reviewer: address,
        decision: u8,
    }

    public struct MilestoneSettled has copy, drop {
        agreement_id: address,
        milestone_index: u64,
        decision: u8,
        amount_paid: u64,
        withheld: u64,
        bonus: u64,
    }

    public struct FundsVested has copy, drop {
        agreement_id: address,
        milestone_index: u64,
        amount: u64,
        recipient: address,
    }

    public struct MilestoneRecycled has copy, drop {
        agreement_id: address,
        milestone_index: u64,
        amount: u64,
    }

    public struct MilestoneExpired has copy, drop {
        agreement_id: address,
        milestone_index: u64,
    }

    public struct TimeoutEnforced has copy, drop {
        agreement_id: address,
        milestone_index: u64,
        amount_released: u64,
    }

    public struct AgreementCompleted has copy, drop {
        agreement_id: address,
        recipient: address,
        total_released: u64,
    }

    public struct WaitlistFunded has copy, drop {
        agreement_id: address,
        recipient: address,
        amount: u64,
    }

    // === Create agreement ===

    public fun create_agreement<T>(
        cap: &ManagerCap,
        pool: &mut FundingPool<T>,
        recipient: address,
        reviewers: vector<address>,
        quorum_threshold: u64,
        milestone_amounts: vector<u64>,
        milestone_deadlines: vector<u64>,
        stream_duration_ms: u64,
        cliff_ms: u64,
        curve: u8,
        bonus_bps: u64,
        late_decay_bps_per_day: u64,
        review_timeout_ms: u64,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let _ = clock;
        let n = milestone_amounts.length();
        assert!(n > 0 && n == milestone_deadlines.length(), 0);

        let mut total = 0u64;
        let mut i = 0;
        while (i < n) {
            total = total + *milestone_amounts.borrow(i);
            i = i + 1;
        };

        let escrow_bal = pool::allocate(pool, total);

        let policy = AdaptivePolicy {
            stream_duration_ms,
            cliff_ms,
            curve,
            bonus_bps,
            late_decay_bps_per_day,
            review_timeout_ms,
        };

        let mut milestones = vector::empty<Milestone>();
        i = 0;
        while (i < n) {
            let state = if (i == 0) { STATE_OPEN } else { STATE_LOCKED };
            milestones.push_back(Milestone {
                amount: *milestone_amounts.borrow(i),
                deadline_ms: *milestone_deadlines.borrow(i),
                state,
                submission: option::none(),
                votes: vector::empty(),
                approval: option::none(),
                stream: option::none(),
                withheld: 0,
            });
            i = i + 1;
        };

        let agreement = FundingAgreement<T> {
            id: object::new(ctx),
            program_id: adaptive_funding::program::program_id(cap),
            pool_id: object::id_address(pool),
            recipient,
            reviewers,
            quorum_threshold,
            milestones,
            policy,
            escrow: escrow_bal,
            paused: false,
            active: true,
            total_amount: total,
            released_total: 0,
            recycled_total: 0,
            bonus_total: 0,
            on_time_count: 0,
            settled_count: 0,
        };
        let agreement_id = object::id_address(&agreement);
        event::emit(AgreementCreated { agreement_id, program_id: adaptive_funding::program::program_id(cap), recipient, total_amount: total });
        transfer::share_object(agreement);
    }

    // === Submit proof ===

    public fun submit_proof<T>(
        agreement: &mut FundingAgreement<T>,
        milestone_idx: u64,
        proof_url: vector<u8>,
        proof_hash: vector<u8>,
        note: vector<u8>,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        assert!(!agreement.paused, EAgreementPaused);
        assert!(agreement.active, EAgreementAlreadyDone);
        assert!(ctx.sender() == agreement.recipient, ENotRecipient);
        let milestone = agreement.milestones.borrow_mut(milestone_idx);
        assert!(milestone.state == STATE_OPEN, EMilestoneNotOpen);
        let now = clock.timestamp_ms();
        milestone.submission = option::some(Submission {
            url: string::utf8(proof_url),
            sha256_hash: proof_hash,
            note: string::utf8(note),
            submitted_at_ms: now,
        });
        milestone.state = STATE_SUBMITTED;
        let sha256_hash = milestone.submission.borrow().sha256_hash;
        event::emit(ProofSubmitted {
            agreement_id: object::id_address(agreement),
            milestone_index: milestone_idx,
            sha256_hash,
            submitted_at_ms: now,
        });
    }

    // === Cast vote (with quorum detection) ===

    public fun cast_vote<T>(
        cap: &ReviewerCap,
        agreement: &mut FundingAgreement<T>,
        pool: &mut FundingPool<T>,
        milestone_idx: u64,
        decision: u8,
        note: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(!agreement.paused, EAgreementPaused);
        assert!(agreement.active, EAgreementAlreadyDone);
        assert!(object::id_address(pool) == agreement.pool_id, EPoolMismatch);
        let reviewer = adaptive_funding::program::reviewer_address(cap);
        assert!(is_reviewer(agreement, reviewer), ENotReviewer);
        {
            let milestone = agreement.milestones.borrow(milestone_idx);
            assert!(milestone.state == STATE_SUBMITTED, EMilestoneNotSubmitted);
            assert!(milestone.approval.is_none(), EQuorumAlreadyReached);
        };
        let now = clock.timestamp_ms();
        {
            let milestone = agreement.milestones.borrow_mut(milestone_idx);
            // check for existing vote from this reviewer
            let mut existing_idx: Option<u64> = option::none();
            let mut vi = 0;
            while (vi < milestone.votes.length()) {
                let v = milestone.votes.borrow(vi);
                if (v.reviewer == reviewer) {
                    assert!(v.decision != decision, EAlreadyVotedSame);
                    existing_idx = option::some(vi);
                };
                vi = vi + 1;
            };
            if (existing_idx.is_some()) {
                milestone.votes.swap_remove(*existing_idx.borrow());
            };
            milestone.votes.push_back(ReviewVote {
                reviewer,
                decision,
                note: string::utf8(note),
                voted_at_ms: now,
            });
        };
        event::emit(VoteCast {
            agreement_id: object::id_address(agreement),
            milestone_index: milestone_idx,
            reviewer,
            decision,
        });
        // Check quorum
        let quorum_decision = check_quorum(agreement, milestone_idx);
        if (quorum_decision.is_some()) {
            let d = *quorum_decision.borrow();
            settle(agreement, pool, milestone_idx, d, reviewer, clock, ctx);
        };
    }

    // === Enforce review timeout (permissionless) ===

    public fun enforce_timeout<T>(
        agreement: &mut FundingAgreement<T>,
        pool: &mut FundingPool<T>,
        milestone_idx: u64,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(!agreement.paused, EAgreementPaused);
        assert!(agreement.active, EAgreementAlreadyDone);
        assert!(object::id_address(pool) == agreement.pool_id, EPoolMismatch);
        let now = clock.timestamp_ms();
        {
            let milestone = agreement.milestones.borrow(milestone_idx);
            assert!(milestone.state == STATE_SUBMITTED, EMilestoneNotSubmitted);
            assert!(milestone.approval.is_none(), EQuorumAlreadyReached);
            let sub = milestone.submission.borrow();
            assert!(now >= sub.submitted_at_ms + agreement.policy.review_timeout_ms, ENotTimedOut);
        };
        let amount_released = {
            let milestone = agreement.milestones.borrow(milestone_idx);
            milestone.amount / 2
        };
        event::emit(TimeoutEnforced {
            agreement_id: object::id_address(agreement),
            milestone_index: milestone_idx,
            amount_released,
        });
        // System settles at 50% (WARNING decision, reviewer = @0x0)
        settle(agreement, pool, milestone_idx, DECISION_WARNING, @0x0, clock, ctx);
    }

    // === Expire milestone (permissionless) ===

    public fun expire_milestone<T>(
        agreement: &mut FundingAgreement<T>,
        milestone_idx: u64,
        clock: &Clock,
        _ctx: &TxContext,
    ) {
        assert!(agreement.active, EAgreementAlreadyDone);
        let now = clock.timestamp_ms();
        let milestone = agreement.milestones.borrow_mut(milestone_idx);
        assert!(milestone.state == STATE_OPEN || milestone.state == STATE_SUBMITTED, EMilestoneNotOpen);
        assert!(now > milestone.deadline_ms, ENotExpired);
        milestone.state = STATE_EXPIRED;
        milestone.withheld = milestone.amount;
        event::emit(MilestoneExpired {
            agreement_id: object::id_address(agreement),
            milestone_index: milestone_idx,
        });
        // Open next milestone if any
        open_next(agreement, milestone_idx);
    }

    // === Claim vested funds (streaming) ===

    public fun claim_vested<T>(
        agreement: &mut FundingAgreement<T>,
        milestone_idx: u64,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(!agreement.paused, EAgreementPaused);
        let now = clock.timestamp_ms();
        {
            let milestone = agreement.milestones.borrow(milestone_idx);
            assert!(milestone.state == STATE_STREAMING, ENotStreaming);
        };
        let recipient = agreement.recipient;
        let (delta, fully_vested, stream_decision) = {
            let milestone = agreement.milestones.borrow_mut(milestone_idx);
            let stream = milestone.stream.borrow_mut();
            let vested = compute_vested(stream, now);
            let delta = if (vested > stream.claimed) { vested - stream.claimed } else { 0 };
            assert!(delta > 0, ENothingToClaim);
            stream.claimed = stream.claimed + delta;
            let fully_vested = stream.claimed >= stream.total_vesting;
            (delta, fully_vested, stream.decision)
        };
        // Transfer from escrow
        let payment = agreement.escrow.split(delta);
        agreement.released_total = agreement.released_total + delta;
        transfer::public_transfer(coin::from_balance(payment, ctx), recipient);
        event::emit(FundsVested {
            agreement_id: object::id_address(agreement),
            milestone_index: milestone_idx,
            amount: delta,
            recipient,
        });
        if (fully_vested) {
            let milestone = agreement.milestones.borrow_mut(milestone_idx);
            milestone.state = if (stream_decision == DECISION_APPROVE) {
                STATE_PAID
            } else {
                STATE_PARTIALLY_RELEASED
            };
            open_next(agreement, milestone_idx);
        };
    }

    // === Recycle withheld funds ===

    public fun recycle_withheld<T>(
        _cap: &ManagerCap,
        agreement: &mut FundingAgreement<T>,
        pool: &mut FundingPool<T>,
        milestone_idx: u64,
        _ctx: &TxContext,
    ) {
        assert!(object::id_address(pool) == agreement.pool_id, EPoolMismatch);
        let milestone = agreement.milestones.borrow_mut(milestone_idx);
        assert!(
            milestone.state == STATE_PARTIALLY_RELEASED ||
            milestone.state == STATE_REJECTED ||
            milestone.state == STATE_EXPIRED,
            EMilestoneNotRecyclable
        );
        let w = milestone.withheld;
        assert!(w > 0, ENoWithheld);
        milestone.withheld = 0;
        milestone.state = STATE_RECYCLED;
        let withheld_bal = agreement.escrow.split(w);
        agreement.recycled_total = agreement.recycled_total + w;
        pool::return_funds(pool, withheld_bal);
        event::emit(MilestoneRecycled {
            agreement_id: object::id_address(agreement),
            milestone_index: milestone_idx,
            amount: w,
        });
    }

    // === Complete agreement (mints soulbound credential) ===

    public fun complete_agreement<T>(
        agreement: &mut FundingAgreement<T>,
        ctx: &mut TxContext,
    ) {
        assert!(agreement.active, EAgreementAlreadyDone);
        // All milestones must be terminal (Paid or Recycled)
        let n = agreement.milestones.length();
        let mut i = 0;
        while (i < n) {
            let s = agreement.milestones.borrow(i).state;
            assert!(s == STATE_PAID || s == STATE_RECYCLED, EMilestoneNotRecyclable);
            i = i + 1;
        };
        assert!(agreement.escrow.value() == 0, EEscrowNotEmpty);
        agreement.active = false;
        let on_time_rate = if (agreement.settled_count > 0) {
            agreement.on_time_count * BASIS_POINTS / agreement.settled_count
        } else { 0 };
        event::emit(AgreementCompleted {
            agreement_id: object::id_address(agreement),
            recipient: agreement.recipient,
            total_released: agreement.released_total,
        });
        credential::mint(
            agreement.recipient,
            agreement.program_id,
            agreement.settled_count,
            on_time_rate,
            agreement.released_total,
            agreement.bonus_total,
            ctx,
        );
    }

    // === Cancel agreement ===

    public fun cancel_agreement<T>(
        _cap: &ManagerCap,
        agreement: &mut FundingAgreement<T>,
        pool: &mut FundingPool<T>,
        _ctx: &TxContext,
    ) {
        assert!(agreement.active, EAgreementAlreadyDone);
        assert!(object::id_address(pool) == agreement.pool_id, EPoolMismatch);
        agreement.active = false;
        let remaining = agreement.escrow.value();
        if (remaining > 0) {
            let bal = agreement.escrow.split(remaining);
            pool::return_funds(pool, bal);
        };
    }

    // === Pause / unpause ===

    public fun pause_agreement<T>(_cap: &ManagerCap, agreement: &mut FundingAgreement<T>) {
        agreement.paused = true;
    }

    public fun unpause_agreement<T>(_cap: &ManagerCap, agreement: &mut FundingAgreement<T>) {
        agreement.paused = false;
    }

    // === Waitlist ===

    public fun create_waitlist<T>(
        cap: &ManagerCap,
        pool: &FundingPool<T>,
        ctx: &mut TxContext,
    ) {
        transfer::share_object(Waitlist<T> {
            id: object::new(ctx),
            program_id: adaptive_funding::program::program_id(cap),
            pool_id: object::id_address(pool),
            queue: vector::empty(),
            total_funded: 0,
        });
    }

    public fun add_to_waitlist<T>(
        _cap: &ManagerCap,
        waitlist: &mut Waitlist<T>,
        recipient: address,
        amount: u64,
        reviewers: vector<address>,
        quorum_threshold: u64,
        stream_duration_ms: u64,
        cliff_ms: u64,
        curve: u8,
        bonus_bps: u64,
        late_decay_bps_per_day: u64,
        review_timeout_ms: u64,
        description: vector<u8>,
        _ctx: &TxContext,
    ) {
        waitlist.queue.push_back(QueuedRequest {
            recipient,
            amount,
            reviewers,
            quorum_threshold,
            policy: AdaptivePolicy {
                stream_duration_ms,
                cliff_ms,
                curve,
                bonus_bps,
                late_decay_bps_per_day,
                review_timeout_ms,
            },
            description: string::utf8(description),
        });
    }

    public fun try_fund_next<T>(
        cap: &ManagerCap,
        waitlist: &mut Waitlist<T>,
        pool: &mut FundingPool<T>,
        clock: &Clock,
        ctx: &mut TxContext,
    ): bool {
        if (waitlist.queue.is_empty()) return false;
        let amount = waitlist.queue.borrow(0).amount;
        if (pool::balance_value(pool) < amount) return false;

        let req = waitlist.queue.remove(0);
        let policy = req.policy;
        let deadline_ms = clock.timestamp_ms() + 30 * MS_PER_DAY;
        let escrow_bal = pool::allocate(pool, req.amount);

        let mut milestones = vector::empty<Milestone>();
        milestones.push_back(Milestone {
            amount: req.amount,
            deadline_ms,
            state: STATE_OPEN,
            submission: option::none(),
            votes: vector::empty(),
            approval: option::none(),
            stream: option::none(),
            withheld: 0,
        });

        let agreement = FundingAgreement<T> {
            id: object::new(ctx),
            program_id: waitlist.program_id,
            pool_id: waitlist.pool_id,
            recipient: req.recipient,
            reviewers: req.reviewers,
            quorum_threshold: req.quorum_threshold,
            milestones,
            policy,
            escrow: escrow_bal,
            paused: false,
            active: true,
            total_amount: req.amount,
            released_total: 0,
            recycled_total: 0,
            bonus_total: 0,
            on_time_count: 0,
            settled_count: 0,
        };
        waitlist.total_funded = waitlist.total_funded + req.amount;
        let agreement_id = object::id_address(&agreement);
        event::emit(WaitlistFunded {
            agreement_id,
            recipient: req.recipient,
            amount: req.amount,
        });
        event::emit(AgreementCreated {
            agreement_id,
            program_id: waitlist.program_id,
            recipient: req.recipient,
            total_amount: req.amount,
        });
        let _ = cap;
        transfer::share_object(agreement);
        true
    }

    // === Internal helpers ===

    fun is_reviewer<T>(agreement: &FundingAgreement<T>, addr: address): bool {
        let mut i = 0;
        while (i < agreement.reviewers.length()) {
            if (*agreement.reviewers.borrow(i) == addr) return true;
            i = i + 1;
        };
        false
    }

    fun count_votes_for<T>(agreement: &FundingAgreement<T>, milestone_idx: u64, decision: u8): u64 {
        let milestone = agreement.milestones.borrow(milestone_idx);
        let mut count = 0u64;
        let mut i = 0;
        while (i < milestone.votes.length()) {
            if (milestone.votes.borrow(i).decision == decision) count = count + 1;
            i = i + 1;
        };
        count
    }

    fun check_quorum<T>(agreement: &FundingAgreement<T>, milestone_idx: u64): Option<u8> {
        let threshold = agreement.quorum_threshold;
        if (count_votes_for(agreement, milestone_idx, DECISION_APPROVE) >= threshold) {
            return option::some(DECISION_APPROVE)
        };
        if (count_votes_for(agreement, milestone_idx, DECISION_WARNING) >= threshold) {
            return option::some(DECISION_WARNING)
        };
        if (count_votes_for(agreement, milestone_idx, DECISION_REJECT) >= threshold) {
            return option::some(DECISION_REJECT)
        };
        option::none()
    }

    fun settle<T>(
        agreement: &mut FundingAgreement<T>,
        pool: &mut FundingPool<T>,
        milestone_idx: u64,
        decision: u8,
        reviewer: address,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let now = clock.timestamp_ms();
        let policy = agreement.policy;
        let recipient = agreement.recipient;

        // Compute payout based on timing + decision
        let (amount, submitted_at_ms, deadline_ms) = {
            let m = agreement.milestones.borrow(milestone_idx);
            let sub = m.submission.borrow();
            (m.amount, sub.submitted_at_ms, m.deadline_ms)
        };

        // Late decay: days = floor((submitted - deadline) / MS_PER_DAY), 0 if on time
        let on_time = submitted_at_ms <= deadline_ms;
        let days_late = if (on_time) { 0u64 }
            else { (submitted_at_ms - deadline_ms) / MS_PER_DAY };

        let decay_bps = days_late * policy.late_decay_bps_per_day;
        let timing_bps = if (decay_bps >= BASIS_POINTS) { 0u64 }
            else { BASIS_POINTS - decay_bps };

        // Decision multiplier
        let decision_bps: u64 = if (decision == DECISION_APPROVE) { BASIS_POINTS }
            else if (decision == DECISION_WARNING) { BASIS_POINTS / 2 }
            else { 0 }; // REJECT or SYSTEM with 0

        // For system timeout (DECISION_WARNING from @0x0), use 50%
        let actual_decision_bps = if (reviewer == @0x0 && decision == DECISION_WARNING) {
            BASIS_POINTS / 2
        } else { decision_bps };

        let payout = ((amount as u128) * (timing_bps as u128) * (actual_decision_bps as u128)
            / ((BASIS_POINTS as u128) * (BASIS_POINTS as u128))) as u64;
        let withheld = amount - payout;

        // Bonus: on-time + full approve only
        let bonus = if (on_time && decision == DECISION_APPROVE && reviewer != @0x0) {
            (((amount as u128) * (policy.bonus_bps as u128) / (BASIS_POINTS as u128)) as u64)
        } else { 0 };

        // Record approval
        {
            let m = agreement.milestones.borrow_mut(milestone_idx);
            m.withheld = withheld;
            m.approval = option::some(ApprovalRecord {
                decision,
                note: string::utf8(b""),
                decided_at_ms: now,
                reviewer,
            });
        };

        // Pay bonus from pool
        if (bonus > 0) {
            pool::pay_bonus(pool, bonus, recipient, ctx);
            agreement.bonus_total = agreement.bonus_total + bonus;
        };

        // Update stats
        if (on_time) agreement.on_time_count = agreement.on_time_count + 1;
        agreement.settled_count = agreement.settled_count + 1;

        event::emit(MilestoneSettled {
            agreement_id: object::id_address(agreement),
            milestone_index: milestone_idx,
            decision,
            amount_paid: payout,
            withheld,
            bonus,
        });

        // Mint receipt
        let agreed_id = object::id_address(agreement);
        transfer::transfer(DisbursementReceipt {
            id: object::new(ctx),
            agreement_id: agreed_id,
            milestone_index: milestone_idx,
            amount_paid: payout,
            bonus_paid: bonus,
            decision,
            decided_at_ms: now,
        }, recipient);

        // Stream or instant payout
        if (payout > 0) {
            if (policy.stream_duration_ms > 0) {
                let m = agreement.milestones.borrow_mut(milestone_idx);
                m.stream = option::some(StreamConfig {
                    total_vesting: payout,
                    claimed: 0,
                    start_ms: now,
                    duration_ms: policy.stream_duration_ms,
                    cliff_ms: policy.cliff_ms,
                    curve: policy.curve,
                    decision,
                });
                m.state = STATE_STREAMING;
            } else {
                // Instant transfer
                let payment_bal = agreement.escrow.split(payout);
                agreement.released_total = agreement.released_total + payout;
                transfer::public_transfer(coin::from_balance(payment_bal, ctx), recipient);
                let m = agreement.milestones.borrow_mut(milestone_idx);
                m.state = if (decision == DECISION_APPROVE) { STATE_PAID }
                    else if (withheld > 0) { STATE_PARTIALLY_RELEASED }
                    else { STATE_PAID };
                open_next(agreement, milestone_idx);
            }
        } else {
            // No payout (reject or 0 after decay)
            let m = agreement.milestones.borrow_mut(milestone_idx);
            m.state = if (decision == DECISION_REJECT) { STATE_REJECTED } else { STATE_PARTIALLY_RELEASED };
            open_next(agreement, milestone_idx);
        };
    }

    fun open_next<T>(agreement: &mut FundingAgreement<T>, current_idx: u64) {
        let next = current_idx + 1;
        if (next < agreement.milestones.length()) {
            let m = agreement.milestones.borrow_mut(next);
            if (m.state == STATE_LOCKED) m.state = STATE_OPEN;
        };
    }

    fun compute_vested(stream: &StreamConfig, now_ms: u64): u64 {
        let elapsed = if (now_ms > stream.start_ms) { now_ms - stream.start_ms } else { 0 };
        if (elapsed < stream.cliff_ms) return 0;
        let effective = if (elapsed > stream.duration_ms) { stream.duration_ms } else { elapsed };
        let total = stream.total_vesting;
        if (stream.curve == CURVE_LINEAR) {
            ((total as u128) * (effective as u128) / (stream.duration_ms as u128)) as u64
        } else if (stream.curve == CURVE_STEPPED) {
            let steps = effective * 4 / stream.duration_ms;
            let steps = if (steps > 4) { 4 } else { steps };
            total * steps / 4
        } else {
            // Accelerating (quadratic)
            let num = (total as u128) * (effective as u128) * (effective as u128);
            let den = (stream.duration_ms as u128) * (stream.duration_ms as u128);
            (num / den) as u64
        }
    }

    // === Getters ===

    public fun recipient<T>(a: &FundingAgreement<T>): address { a.recipient }
    public fun is_active<T>(a: &FundingAgreement<T>): bool { a.active }
    public fun is_paused<T>(a: &FundingAgreement<T>): bool { a.paused }
    public fun escrow_value<T>(a: &FundingAgreement<T>): u64 { a.escrow.value() }
    public fun total_amount<T>(a: &FundingAgreement<T>): u64 { a.total_amount }
    public fun released_total<T>(a: &FundingAgreement<T>): u64 { a.released_total }
    public fun recycled_total<T>(a: &FundingAgreement<T>): u64 { a.recycled_total }
    public fun bonus_total<T>(a: &FundingAgreement<T>): u64 { a.bonus_total }
    public fun milestone_state<T>(a: &FundingAgreement<T>, idx: u64): u8 {
        a.milestones.borrow(idx).state
    }
    public fun milestone_withheld<T>(a: &FundingAgreement<T>, idx: u64): u64 {
        a.milestones.borrow(idx).withheld
    }
    public fun milestone_amount<T>(a: &FundingAgreement<T>, idx: u64): u64 {
        a.milestones.borrow(idx).amount
    }
    public fun waitlist_length<T>(w: &Waitlist<T>): u64 { w.queue.length() }

    // Expose constants for tests
    public fun state_open(): u8 { STATE_OPEN }
    public fun state_submitted(): u8 { STATE_SUBMITTED }
    public fun state_streaming(): u8 { STATE_STREAMING }
    public fun state_paid(): u8 { STATE_PAID }
    public fun state_partially_released(): u8 { STATE_PARTIALLY_RELEASED }
    public fun state_rejected(): u8 { STATE_REJECTED }
    public fun state_expired(): u8 { STATE_EXPIRED }
    public fun state_recycled(): u8 { STATE_RECYCLED }
    public fun decision_approve(): u8 { DECISION_APPROVE }
    public fun decision_warning(): u8 { DECISION_WARNING }
    public fun decision_reject(): u8 { DECISION_REJECT }
    public fun curve_linear(): u8 { CURVE_LINEAR }
    public fun curve_stepped(): u8 { CURVE_STEPPED }
    public fun curve_accelerating(): u8 { CURVE_ACCELERATING }
}
