module adaptive_funding::credential {
    use sui::event;

    // key only (no store) = soulbound: cannot be transferred by the owner
    public struct FundingCredential has key {
        id: UID,
        recipient: address,
        program_id: address,
        milestones_paid: u64,
        on_time_rate_bps: u64,
        total_received: u64,
        bonus_earned: u64,
    }

    public struct CredentialMinted has copy, drop {
        credential_id: address,
        recipient: address,
        program_id: address,
        milestones_paid: u64,
        on_time_rate_bps: u64,
        total_received: u64,
        bonus_earned: u64,
    }

    public(package) fun mint(
        recipient: address,
        program_id: address,
        milestones_paid: u64,
        on_time_rate_bps: u64,
        total_received: u64,
        bonus_earned: u64,
        ctx: &mut TxContext,
    ) {
        let cred = FundingCredential {
            id: object::new(ctx),
            recipient,
            program_id,
            milestones_paid,
            on_time_rate_bps,
            total_received,
            bonus_earned,
        };
        let credential_id = object::id_address(&cred);
        event::emit(CredentialMinted {
            credential_id,
            recipient,
            program_id,
            milestones_paid,
            on_time_rate_bps,
            total_received,
            bonus_earned,
        });
        transfer::transfer(cred, recipient);
    }

    // === Getters ===

    public fun milestones_paid(c: &FundingCredential): u64 { c.milestones_paid }
    public fun total_received(c: &FundingCredential): u64 { c.total_received }
    public fun on_time_rate_bps(c: &FundingCredential): u64 { c.on_time_rate_bps }
}
