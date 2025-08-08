// Treasury system - manages DAO funds with secure deposit/withdrawal and reentrancy protection
module dao_addr::treasury {
    use std::signer;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::timestamp;
    use dao_addr::admin;
    use dao_addr::errors;

    friend dao_addr::dao_core;

    // Reentrancy protection
    struct ReentrancyGuard has key {
        locked: bool,
    }

    struct Treasury has key {
        balance: coin::Coin<AptosCoin>,
        daily_withdrawal_limit: u64,
        last_withdrawal_day: u64,
        daily_withdrawn: u64,
    }

    public fun init_treasury(account: &signer): Object<Treasury> {
        let addr = signer::address_of(account);
        assert!(!exists<Treasury>(addr), errors::already_exists());
        
        let treasury = Treasury { 
            balance: coin::zero<AptosCoin>(),
            daily_withdrawal_limit: 1000000000, // 10 APT in octas
            last_withdrawal_day: 0,
            daily_withdrawn: 0,
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
        let treasury = borrow_global_mut<Treasury>(object::object_address(&treasury_obj));
        let coins = coin::withdraw<AptosCoin>(account, amount);
        coin::merge(&mut treasury.balance, coins);
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
        
        // Unlock AFTER external interaction
        guard.locked = false;
    }

    #[view]
    public fun get_balance_from_object(treasury_obj: Object<Treasury>): u64 acquires Treasury {
        let treasury = borrow_global<Treasury>(object::object_address(&treasury_obj));
        coin::value(&treasury.balance)
    }

    // Legacy functions - these operate directly on DAO addresses without circular dependency
    // These functions assume treasury exists at the DAO address for backward compatibility
    public entry fun deposit(account: &signer, dao_addr: address, amount: u64) acquires Treasury {
        let treasury_addr = get_legacy_treasury_addr(dao_addr);
        assert!(exists<Treasury>(treasury_addr), errors::not_found());
        
        let treasury = borrow_global_mut<Treasury>(treasury_addr);
        let coins = coin::withdraw<AptosCoin>(account, amount);
        coin::merge(&mut treasury.balance, coins);
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