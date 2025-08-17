// Treasury system - manages DAO funds with secure deposit/withdrawal and reentrancy protection
module dao_addr::treasury {
    use std::signer;
    use std::event;
    use std::vector;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::timestamp;
    use dao_addr::admin;
    use dao_addr::membership;
    use dao_addr::errors;

    friend dao_addr::dao_core;

    // Activity tracking events
    #[event]
    struct TreasuryDepositEvent has drop, store {
        dao_address: address,
        depositor: address,
        amount: u64,
        new_balance: u64,
        timestamp: u64,
        transaction_hash: vector<u8>,
    }

    #[event]
    struct TreasuryWithdrawalEvent has drop, store {
        dao_address: address,
        withdrawer: address,
        amount: u64,
        remaining_balance: u64,
        timestamp: u64,
        transaction_hash: vector<u8>,
    }

    #[event]
    struct TreasuryRewardWithdrawalEvent has drop, store {
        dao_address: address,
        recipient: address,
        amount: u64,
        remaining_balance: u64,
        timestamp: u64,
        transaction_hash: vector<u8>,
    }

    // Reentrancy protection
    struct ReentrancyGuard has key {
        locked: bool,
    }

    struct Treasury has key {
        balance: coin::Coin<AptosCoin>,
        daily_withdrawal_limit: u64,
        last_withdrawal_day: u64,
        daily_withdrawn: u64,
        dao_address: address, // Track which DAO this treasury belongs to
        allow_public_deposits: bool, // Allow non-members to deposit (disabled by default)
    }

    public fun init_treasury(account: &signer): Object<Treasury> {
        let addr = signer::address_of(account);
        assert!(!exists<Treasury>(addr), errors::already_exists());
        
        let treasury = Treasury { 
            balance: coin::zero<AptosCoin>(),
            daily_withdrawal_limit: 1000000000, // 10 APT in octas
            last_withdrawal_day: 0,
            daily_withdrawn: 0,
            dao_address: addr, // Store the DAO address
            allow_public_deposits: false, // Default to member-only deposits (secure)
        };

        // Initialize reentrancy guard
        let guard = ReentrancyGuard {
            locked: false,
        };

        let constructor_ref = object::create_object_from_account(account);
        let object_signer = object::generate_signer(&constructor_ref);
        move_to(&object_signer, treasury);
        move_to(&object_signer, guard);
        object::object_from_constructor_ref(&constructor_ref)
    }

    // Direct object-based functions
    public entry fun deposit_to_object(account: &signer, treasury_obj: Object<Treasury>, amount: u64) acquires Treasury {
        let depositor = signer::address_of(account);
        let treasury = borrow_global_mut<Treasury>(object::object_address(&treasury_obj));
        let dao_addr = treasury.dao_address;
        
        // MEMBER-ONLY DEPOSITS: Only members or admins can deposit
        // This ensures only committed community members can fund the treasury
        if (!admin::is_admin(dao_addr, depositor)) {
            assert!(membership::is_member(dao_addr, depositor), errors::not_member());
        };
        
        // Validate amount
        assert!(amount > 0, errors::invalid_amount());
        
        let coins = coin::withdraw<AptosCoin>(account, amount);
        coin::merge(&mut treasury.balance, coins);
        
        // Emit deposit event
        event::emit(TreasuryDepositEvent {
            dao_address: dao_addr,
            depositor,
            amount,
            new_balance: coin::value(&treasury.balance),
            timestamp: timestamp::now_seconds(),
            transaction_hash: vector::empty(), // TODO: Add actual transaction hash
        });
    }

    public entry fun withdraw_from_object(account: &signer, dao_addr: address, treasury_obj: Object<Treasury>, amount: u64) acquires Treasury, ReentrancyGuard {
        assert!(admin::is_admin(dao_addr, signer::address_of(account)), errors::not_admin());
        
        let treasury_addr = object::object_address(&treasury_obj);
        
        // Reentrancy protection
        let guard = borrow_global_mut<ReentrancyGuard>(treasury_addr);
        assert!(!guard.locked, errors::invalid_state(1));
        guard.locked = true;
        
        let treasury = borrow_global_mut<Treasury>(treasury_addr);
        
        // Check daily withdrawal limits
        let current_day = timestamp::now_seconds() / 86400; // seconds in a day
        if (treasury.last_withdrawal_day != current_day) {
            treasury.last_withdrawal_day = current_day;
            treasury.daily_withdrawn = 0;
        };
        assert!(treasury.daily_withdrawn + amount <= treasury.daily_withdrawal_limit, errors::withdrawal_limit_exceeded());
        treasury.daily_withdrawn = treasury.daily_withdrawn + amount;
        
        // Validate sufficient balance
        let current_balance = coin::value(&treasury.balance);
        assert!(current_balance >= amount, errors::insufficient_treasury());
        
        // Extract coins before external call
        let coins = coin::extract(&mut treasury.balance, amount);
        let recipient = signer::address_of(account);
        
        // CRITICAL FIX: Keep lock until after external call
        coin::deposit(recipient, coins);

        // Emit withdrawal event
        event::emit(TreasuryWithdrawalEvent {
            dao_address: dao_addr,
            withdrawer: recipient,
            amount,
            remaining_balance: coin::value(&treasury.balance),
            timestamp: timestamp::now_seconds(),
            transaction_hash: vector::empty(),
        });
        
        // Unlock AFTER external interaction
        guard.locked = false;
    }

    // Internal function for reward distribution - RESTRICTED ACCESS
    // This function should ONLY be called by dao_core after proper validation
    public(friend) fun withdraw_rewards_from_object(recipient: address, treasury_obj: Object<Treasury>, amount: u64) acquires Treasury, ReentrancyGuard {
        let treasury_addr = object::object_address(&treasury_obj);
        
        // Reentrancy protection
        let guard = borrow_global_mut<ReentrancyGuard>(treasury_addr);
        assert!(!guard.locked, errors::invalid_state(1)); // Custom error for reentrancy
        guard.locked = true;
        
        let treasury = borrow_global_mut<Treasury>(treasury_addr);
        
        // Double-check treasury has sufficient balance before withdrawal
        let current_balance = coin::value(&treasury.balance);
        assert!(current_balance >= amount, errors::insufficient_treasury());
        
        // Checks-Effects-Interactions pattern: modify state before external call
        let coins = coin::extract(&mut treasury.balance, amount);
        
        // CRITICAL FIX: Keep lock until after external call
        coin::deposit(recipient, coins);

        // Emit reward withdrawal event
        event::emit(TreasuryRewardWithdrawalEvent {
            dao_address: object::object_address(&treasury_obj),
            recipient,
            amount,
            remaining_balance: coin::value(&treasury.balance),
            timestamp: timestamp::now_seconds(),
            transaction_hash: vector::empty(),
        });
        
        // Unlock AFTER external interaction
        guard.locked = false;
    }

    #[view]
    public fun get_balance_from_object(treasury_obj: Object<Treasury>): u64 acquires Treasury {
        let treasury = borrow_global<Treasury>(object::object_address(&treasury_obj));
        coin::value(&treasury.balance)
    }

    // Enhanced treasury view functions
    #[view]
    public fun get_treasury_info(treasury_obj: Object<Treasury>): (u64, u64, u64, u64, address, bool) acquires Treasury {
        let treasury = borrow_global<Treasury>(object::object_address(&treasury_obj));
        (
            coin::value(&treasury.balance),
            treasury.daily_withdrawal_limit,
            treasury.last_withdrawal_day,
            treasury.daily_withdrawn,
            treasury.dao_address,
            treasury.allow_public_deposits
        )
    }

    #[view]
    public fun get_daily_withdrawal_status(treasury_obj: Object<Treasury>): (u64, u64, u64) acquires Treasury {
        let treasury = borrow_global<Treasury>(object::object_address(&treasury_obj));
        let current_day = timestamp::now_seconds() / 86400;
        let remaining_limit = if (treasury.last_withdrawal_day == current_day) {
            if (treasury.daily_withdrawn >= treasury.daily_withdrawal_limit) {
                0
            } else {
                treasury.daily_withdrawal_limit - treasury.daily_withdrawn
            }
        } else {
            treasury.daily_withdrawal_limit
        };
        (treasury.daily_withdrawal_limit, treasury.daily_withdrawn, remaining_limit)
    }

    #[view]
    public fun can_withdraw_amount(treasury_obj: Object<Treasury>, amount: u64): bool acquires Treasury {
        let treasury = borrow_global<Treasury>(object::object_address(&treasury_obj));
        let current_day = timestamp::now_seconds() / 86400;
        let available_daily = if (treasury.last_withdrawal_day == current_day) {
            if (treasury.daily_withdrawn >= treasury.daily_withdrawal_limit) {
                0
            } else {
                treasury.daily_withdrawal_limit - treasury.daily_withdrawn
            }
        } else {
            treasury.daily_withdrawal_limit
        };
        amount <= available_daily && amount <= coin::value(&treasury.balance)
    }

    // Admin functions for treasury management
    public entry fun set_public_deposits(admin: &signer, dao_addr: address, treasury_obj: Object<Treasury>, allow: bool) acquires Treasury {
        assert!(admin::is_admin(dao_addr, signer::address_of(admin)), errors::not_admin());
        
        let treasury = borrow_global_mut<Treasury>(object::object_address(&treasury_obj));
        treasury.allow_public_deposits = allow;
    }

    #[view]
    public fun allows_public_deposits(treasury_obj: Object<Treasury>): bool acquires Treasury {
        let treasury = borrow_global<Treasury>(object::object_address(&treasury_obj));
        treasury.allow_public_deposits
    }

    // Legacy functions - these operate directly on DAO addresses without circular dependency
    // These functions assume treasury exists at the DAO address for backward compatibility
    public entry fun deposit(account: &signer, dao_addr: address, amount: u64) acquires Treasury {
        let depositor = signer::address_of(account);
        let treasury_addr = get_legacy_treasury_addr(dao_addr);
        assert!(exists<Treasury>(treasury_addr), errors::not_found());
        
        let treasury = borrow_global_mut<Treasury>(treasury_addr);
        
        // MEMBER-ONLY DEPOSITS: Only members or admins can deposit
        // This ensures only committed community members can fund the treasury
        if (!admin::is_admin(dao_addr, depositor)) {
            assert!(membership::is_member(dao_addr, depositor), errors::not_member());
        };
        
        // Validate amount
        assert!(amount > 0, errors::invalid_amount());
        
        let coins = coin::withdraw<AptosCoin>(account, amount);
        coin::merge(&mut treasury.balance, coins);
        
        // Emit deposit event
        event::emit(TreasuryDepositEvent {
            dao_address: dao_addr,
            depositor,
            amount,
            new_balance: coin::value(&treasury.balance),
            timestamp: timestamp::now_seconds(),
            transaction_hash: vector::empty(), // TODO: Add actual transaction hash
        });
    }

    public entry fun withdraw(account: &signer, dao_addr: address, amount: u64) acquires Treasury, ReentrancyGuard {
        assert!(admin::is_admin(dao_addr, signer::address_of(account)), errors::not_admin());
        
        let treasury_addr = get_legacy_treasury_addr(dao_addr);
        
        // Reentrancy protection
        let guard = borrow_global_mut<ReentrancyGuard>(treasury_addr);
        assert!(!guard.locked, errors::invalid_state(1));
        guard.locked = true;
        
        let treasury = borrow_global_mut<Treasury>(treasury_addr);
        
        // Check daily withdrawal limits
        let current_day = timestamp::now_seconds() / 86400;
        if (treasury.last_withdrawal_day != current_day) {
            treasury.last_withdrawal_day = current_day;
            treasury.daily_withdrawn = 0;
        };
        assert!(treasury.daily_withdrawn + amount <= treasury.daily_withdrawal_limit, errors::withdrawal_limit_exceeded());
        treasury.daily_withdrawn = treasury.daily_withdrawn + amount;
        
        // Validate sufficient balance
        let current_balance = coin::value(&treasury.balance);
        assert!(current_balance >= amount, errors::insufficient_treasury());
        
        // Extract coins before external call
        let coins = coin::extract(&mut treasury.balance, amount);
        let recipient = signer::address_of(account);
        
        // CRITICAL FIX: Keep lock until after external call
        coin::deposit(recipient, coins);

        // Emit withdrawal event
        event::emit(TreasuryWithdrawalEvent {
            dao_address: dao_addr,
            withdrawer: recipient,
            amount,
            remaining_balance: coin::value(&treasury.balance),
            timestamp: timestamp::now_seconds(),
            transaction_hash: vector::empty(),
        });
        
        // Unlock AFTER external interaction
        guard.locked = false;
    }

    #[view]
    public fun get_balance(dao_addr: address): u64 acquires Treasury {
        let treasury_addr = get_legacy_treasury_addr(dao_addr);
        if (!exists<Treasury>(treasury_addr)) return 0;
        
        let treasury = borrow_global<Treasury>(treasury_addr);
        coin::value(&treasury.balance)
    }

    // Helper function to determine treasury address for legacy functions
    #[view]
    fun get_legacy_treasury_addr(dao_addr: address): address {
        // For object-based treasuries created through dao_core, we need to compute the object address
        // This is a simplified approach - in production, you might want to store this mapping
        dao_addr // Simplified: assume treasury is at DAO address for legacy compatibility
    }
}