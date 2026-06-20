// Stub staking module — native SUI staking to be wired to sui_system on mainnet.
// Keeps deploy.sh compatible without requiring the SuiSystem framework dependency.
module adaptive_funding::staking {
    use adaptive_funding::program::ManagerCap;

    public struct StakeVault has key {
        id: UID,
        program_id: address,
        total_staked: u64,
    }

    public fun create_vault(
        cap: &ManagerCap,
        ctx: &mut TxContext,
    ) {
        transfer::share_object(StakeVault {
            id: object::new(ctx),
            program_id: adaptive_funding::program::program_id(cap),
            total_staked: 0,
        });
    }

    public fun total_staked(vault: &StakeVault): u64 { vault.total_staked }
}
