module adaptive_funding::pool {
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::clock::Clock;
    use sui::event;
    use adaptive_funding::program::ManagerCap;

    // === Constants ===

    const MS_PER_YEAR: u64 = 31_536_000_000;
    const BASIS_POINTS: u64 = 10_000;

    // === Errors ===

    const EPoolPaused: u64 = 0;
    const EInsufficientBalance: u64 = 1;

    // === Objects ===

    public struct FundingPool<phantom T> has key {
        id: UID,
        program_id: address,
        balance: Balance<T>,
        yield_reserve: Balance<T>,
        apy_bps: u64,
        last_accrual_ms: u64,
        paused: bool,
        total_deposited: u64,
        total_allocated: u64,
        total_recycled: u64,
        total_bonuses_paid: u64,
    }

    // === Events ===

    public struct PoolCreated has copy, drop {
        pool_id: address,
        program_id: address,
        apy_bps: u64,
    }

    public struct Deposited has copy, drop {
        pool_id: address,
        amount: u64,
    }

    public struct YieldReserveDeposited has copy, drop {
        pool_id: address,
        amount: u64,
    }

    public struct YieldAccrued has copy, drop {
        pool_id: address,
        amount: u64,
    }

    public struct BonusPaid has copy, drop {
        pool_id: address,
        amount: u64,
        recipient: address,
    }

    public struct FundsAllocated has copy, drop {
        pool_id: address,
        amount: u64,
    }

    public struct FundsReturned has copy, drop {
        pool_id: address,
        amount: u64,
    }

    public struct PoolPaused has copy, drop { pool_id: address }
    public struct PoolUnpaused has copy, drop { pool_id: address }

    // === Functions ===

    public fun create_pool<T>(
        cap: &ManagerCap,
        apy_bps: u64,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let pool = FundingPool<T> {
            id: object::new(ctx),
            program_id: adaptive_funding::program::program_id(cap),
            balance: balance::zero(),
            yield_reserve: balance::zero(),
            apy_bps,
            last_accrual_ms: clock.timestamp_ms(),
            paused: false,
            total_deposited: 0,
            total_allocated: 0,
            total_recycled: 0,
            total_bonuses_paid: 0,
        };
        let pool_id = object::id_address(&pool);
        event::emit(PoolCreated {
            pool_id,
            program_id: adaptive_funding::program::program_id(cap),
            apy_bps,
        });
        transfer::share_object(pool);
    }

    public fun deposit<T>(pool: &mut FundingPool<T>, coin: Coin<T>) {
        let amount = coin.value();
        pool.total_deposited = pool.total_deposited + amount;
        pool.balance.join(coin.into_balance());
        event::emit(Deposited { pool_id: object::id_address(pool), amount });
    }

    public fun deposit_yield_reserve<T>(pool: &mut FundingPool<T>, coin: Coin<T>) {
        let amount = coin.value();
        pool.yield_reserve.join(coin.into_balance());
        event::emit(YieldReserveDeposited { pool_id: object::id_address(pool), amount });
    }

    public fun accrue_yield<T>(pool: &mut FundingPool<T>, clock: &Clock) {
        let now = clock.timestamp_ms();
        let elapsed = now - pool.last_accrual_ms;
        if (elapsed == 0 || pool.yield_reserve.value() == 0 || pool.balance.value() == 0) {
            pool.last_accrual_ms = now;
            return
        };
        let principal = pool.balance.value();
        let yield_amount = (
            (principal as u128) * (pool.apy_bps as u128) * (elapsed as u128)
            / ((BASIS_POINTS as u128) * (MS_PER_YEAR as u128))
        ) as u64;
        if (yield_amount == 0) {
            pool.last_accrual_ms = now;
            return
        };
        let reserve_bal = pool.yield_reserve.value();
        let actual = if (yield_amount > reserve_bal) { reserve_bal } else { yield_amount };
        let yield_bal = pool.yield_reserve.split(actual);
        pool.balance.join(yield_bal);
        pool.last_accrual_ms = now;
        event::emit(YieldAccrued { pool_id: object::id_address(pool), amount: actual });
    }

    public fun pause_pool<T>(_cap: &ManagerCap, pool: &mut FundingPool<T>) {
        pool.paused = true;
        event::emit(PoolPaused { pool_id: object::id_address(pool) });
    }

    public fun unpause_pool<T>(_cap: &ManagerCap, pool: &mut FundingPool<T>) {
        pool.paused = false;
        event::emit(PoolUnpaused { pool_id: object::id_address(pool) });
    }

    // === Package-internal APIs (called by agreement module) ===

    public(package) fun allocate<T>(pool: &mut FundingPool<T>, amount: u64): Balance<T> {
        assert!(!pool.paused, EPoolPaused);
        assert!(pool.balance.value() >= amount, EInsufficientBalance);
        pool.total_allocated = pool.total_allocated + amount;
        event::emit(FundsAllocated { pool_id: object::id_address(pool), amount });
        pool.balance.split(amount)
    }

    public(package) fun return_funds<T>(pool: &mut FundingPool<T>, bal: Balance<T>) {
        let amount = bal.value();
        pool.total_recycled = pool.total_recycled + amount;
        pool.balance.join(bal);
        event::emit(FundsReturned { pool_id: object::id_address(pool), amount });
    }

    public(package) fun pay_bonus<T>(
        pool: &mut FundingPool<T>,
        amount: u64,
        recipient: address,
        ctx: &mut TxContext,
    ) {
        assert!(!pool.paused, EPoolPaused);
        if (amount == 0 || pool.balance.value() < amount) return;
        let bonus_bal = pool.balance.split(amount);
        pool.total_bonuses_paid = pool.total_bonuses_paid + amount;
        event::emit(BonusPaid { pool_id: object::id_address(pool), amount, recipient });
        transfer::public_transfer(coin::from_balance(bonus_bal, ctx), recipient);
    }

    // === Getters ===

    public fun balance_value<T>(pool: &FundingPool<T>): u64 { pool.balance.value() }
    public fun reserve_value<T>(pool: &FundingPool<T>): u64 { pool.yield_reserve.value() }
    public fun is_paused<T>(pool: &FundingPool<T>): bool { pool.paused }
    public fun total_recycled<T>(pool: &FundingPool<T>): u64 { pool.total_recycled }
    public fun total_bonuses_paid<T>(pool: &FundingPool<T>): u64 { pool.total_bonuses_paid }
    public fun total_allocated<T>(pool: &FundingPool<T>): u64 { pool.total_allocated }
}
