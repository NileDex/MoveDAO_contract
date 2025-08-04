module dao_addr::treasury {
    use std::signer;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::object::{Self, Object};
    use dao_addr::admin;
    use dao_addr::errors;

    friend dao_addr::dao_core;

    // Reentrancy protection
    struct ReentrancyGuard has key {
        locked: bool,
    }

    struct Treasury has key {
        balance: coin::Coin<AptosCoin>,
    }

    public fun init_treasury(account: &signer): Object<Treasury> {
        let addr = signer::address_of(account);
        assert!(!exists<Treasury>(addr), errors::already_exists());
        
        let treasury = Treasury { 
            balance: coin::zero<AptosCoin>(),
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
        
        // Validate sufficient balance
        let current_balance = coin::value(&treasury.balance);
        assert!(current_balance >= amount, errors::insufficient_treasury());
        
        // Extract coins before external call
        let coins = coin::extract(&mut treasury.balance, amount);
        let recipient = signer::address_of(account);
        
        // Unlock before external call
        guard.locked = false;
        
        // External interaction last
        coin::deposit(recipient, coins);
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
        
        // Unlock before external call
        guard.locked = false;
        
        // External interaction last
        coin::deposit(recipient, coins);
    }

    #[view]
    public fun get_balance_from_object(treasury_obj: Object<Treasury>): u64 acquires Treasury {
        let treasury = borrow_global<Treasury>(object::object_address(&treasury_obj));
        coin::value(&treasury.balance)
    }

    // For now, provide legacy functions that will be updated later with proper DAO integration
    public entry fun deposit(_account: &signer, _dao_addr: address, _amount: u64) {
        // This will be implemented once the circular dependency is resolved
        abort 999 // Temporary placeholder
    }

    public entry fun withdraw(_account: &signer, _dao_addr: address, _amount: u64) {
        // This will be implemented once the circular dependency is resolved
        abort 999 // Temporary placeholder
    }

    #[view]
    public fun get_balance(_dao_addr: address): u64 {
        // This will be implemented once the circular dependency is resolved
        0 // Temporary placeholder
    }
}