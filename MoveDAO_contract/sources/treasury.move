module dao_addr::treasury {
    use std::signer;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::object::{Self, Object};
    use dao_addr::admin;

    const ENOT_ADMIN: u64 = 2;

    struct Treasury has key {
        balance: coin::Coin<AptosCoin>,
    }

    public fun init_treasury(account: &signer): Object<Treasury> {
        let addr = signer::address_of(account);
        assert!(!exists<Treasury>(addr), 1);
        
        let treasury = Treasury { 
            balance: coin::zero<AptosCoin>(),
        };

        let constructor_ref = object::create_object_from_account(account);
        let object_signer = object::generate_signer(&constructor_ref);
        move_to(&object_signer, treasury);
        object::object_from_constructor_ref(&constructor_ref)
    }

    // Direct object-based functions
    public entry fun deposit_to_object(account: &signer, treasury_obj: Object<Treasury>, amount: u64) acquires Treasury {
        let treasury = borrow_global_mut<Treasury>(object::object_address(&treasury_obj));
        let coins = coin::withdraw<AptosCoin>(account, amount);
        coin::merge(&mut treasury.balance, coins);
    }

    public entry fun withdraw_from_object(account: &signer, dao_addr: address, treasury_obj: Object<Treasury>, amount: u64) acquires Treasury {
        assert!(admin::is_admin(dao_addr, signer::address_of(account)), ENOT_ADMIN);
        
        let treasury = borrow_global_mut<Treasury>(object::object_address(&treasury_obj));
        let coins = coin::extract(&mut treasury.balance, amount);
        coin::deposit(signer::address_of(account), coins);
    }

    // Internal function for reward distribution - bypasses admin check
    public fun withdraw_rewards_from_object(recipient: address, treasury_obj: Object<Treasury>, amount: u64) acquires Treasury {
        let treasury = borrow_global_mut<Treasury>(object::object_address(&treasury_obj));
        let coins = coin::extract(&mut treasury.balance, amount);
        coin::deposit(recipient, coins);
    }

    #[view]
    public fun get_balance_from_object(treasury_obj: Object<Treasury>): u64 acquires Treasury {
        let treasury = borrow_global<Treasury>(object::object_address(&treasury_obj));
        coin::value(&treasury.balance)
    }

    // For now, provide legacy functions that will be updated later with proper DAO integration
    public entry fun deposit(account: &signer, _dao_addr: address, _amount: u64) {
        // This will be implemented once the circular dependency is resolved
        abort 999 // Temporary placeholder
    }

    public entry fun withdraw(account: &signer, _dao_addr: address, _amount: u64) {
        // This will be implemented once the circular dependency is resolved
        abort 999 // Temporary placeholder
    }

    #[view]
    public fun get_balance(_dao_addr: address): u64 {
        // This will be implemented once the circular dependency is resolved
        0 // Temporary placeholder
    }
}