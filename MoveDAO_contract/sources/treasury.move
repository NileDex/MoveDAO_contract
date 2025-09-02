// Treasury system - manages DAO funds with secure deposit/withdrawal and reentrancy protection
module movedaoaddrx::treasury {
    use std::signer;
    use std::event;
    use std::vector;
    use std::string;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::timestamp;
    use movedaoaddrx::admin;
    use movedaoaddrx::membership;
    use movedaoaddrx::errors;
    use movedaoaddrx::activity_tracker;

    friend movedaoaddrx::dao_core_file;

    // Activity tracking events
    #[event]
    struct TreasuryDepositEvent has drop, store {
        movedaoaddrxess: address,
        depositor: address,
        amount: u64,
        new_balance: u64,
        timestamp: u64,
        transaction_hash: vector<u8>,
    }

    #[event]
    struct TreasuryWithdrawalEvent has drop, store {
        movedaoaddrxess: address,
        withdrawer: address,
        amount: u64,
        remaining_balance: u64,
        timestamp: u64,
        transaction_hash: vector<u8>,
    }

    #[event]
    struct TreasuryRewardWithdrawalEvent has drop, store {
        movedaoaddrxess: address,
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
        movedaoaddrxess: address, // Track which DAO this treasury belongs to
        allow_public_deposits: bool, // Allow non-members to deposit (disabled by default)
        last_major_withdrawal_time: u64, // Track last significant withdrawal for rolling window
    }

    public fun init_treasury(account: &signer): Object<Treasury> {
        let addr = signer::address_of(account);
        assert!(!exists<Treasury>(addr), errors::already_exists());
        
        let treasury = Treasury { 
            balance: coin::zero<AptosCoin>(),
            daily_withdrawal_limit: 1000000000, // 10 APT in octas
            last_withdrawal_day: 0,
            daily_withdrawn: 0,
            movedaoaddrxess: addr, // Store the DAO address
            allow_public_deposits: false, // Default to member-only deposits (secure)
            last_major_withdrawal_time: 0, // Initialize withdrawal tracking
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
        let movedaoaddrx = treasury.movedaoaddrxess;
        
        // MEMBER-ONLY DEPOSITS: Only members or admins can deposit
        // This ensures only committed community members can fund the treasury
        if (!admin::is_admin(movedaoaddrx, depositor)) {
            assert!(membership::is_member(movedaoaddrx, depositor), errors::not_member());
        };
        
        // Validate amount
        assert!(amount > 0, errors::invalid_amount());
        
        let coins = coin::withdraw<AptosCoin>(account, amount);
        coin::merge(&mut treasury.balance, coins);
        
        // Emit deposit event
        event::emit(TreasuryDepositEvent {
            movedaoaddrxess: movedaoaddrx,
            depositor,
            amount,
            new_balance: coin::value(&treasury.balance),
            timestamp: timestamp::now_seconds(),
            transaction_hash: vector::empty(), // TODO: Add actual transaction hash
        });

        // Log treasury deposit activity
        activity_tracker::emit_activity(
            movedaoaddrx,                    // dao_address
            9,                               // activity_type: TREASURY_DEPOSIT
            depositor,                       // user_address
            string::utf8(b"Treasury Deposit"),                    // title
            string::utf8(b"Deposited tokens to DAO treasury"),   // description
            amount,                          // amount
            vector::empty<u8>(),             // metadata (empty for now)
            vector::empty<u8>(),             // transaction_hash (will be filled by the tracker)
            0                                // block_number (will be filled by the tracker)
        );
    }

    public entry fun withdraw_from_object(account: &signer, movedaoaddrx: address, treasury_obj: Object<Treasury>, amount: u64) acquires Treasury, ReentrancyGuard {
        assert!(admin::is_admin(movedaoaddrx, signer::address_of(account)), errors::not_admin());
        
        let treasury_addr = object::object_address(&treasury_obj);
        
        // Reentrancy protection
        let guard = borrow_global_mut<ReentrancyGuard>(treasury_addr);
        assert!(!guard.locked, errors::invalid_state(1));
        guard.locked = true;
        
        let treasury = borrow_global_mut<Treasury>(treasury_addr);
        
        // Check daily withdrawal limits using rolling 24-hour window to prevent bypass attacks
        let current_time = timestamp::now_seconds();
        let rolling_window_seconds = 86400; // 24 hours
        
        // Reset withdrawal counter if 24 hours have passed since last major withdrawal
        if (current_time >= treasury.last_major_withdrawal_time + rolling_window_seconds) {
            treasury.daily_withdrawn = 0;
            treasury.last_major_withdrawal_time = current_time;
        };
        
        // Also maintain the original daily reset for backward compatibility
        let current_day = current_time / 86400;
        if (treasury.last_withdrawal_day != current_day) {
            treasury.last_withdrawal_day = current_day;
            // Only reset if the rolling window hasn't been more restrictive
            if (current_time >= treasury.last_major_withdrawal_time + rolling_window_seconds) {
                treasury.daily_withdrawn = 0;
            };
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
            movedaoaddrxess: movedaoaddrx,
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
            movedaoaddrxess: object::object_address(&treasury_obj),
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
            treasury.movedaoaddrxess,
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
    public entry fun set_public_deposits(admin: &signer, movedaoaddrx: address, treasury_obj: Object<Treasury>, allow: bool) acquires Treasury {
        assert!(admin::is_admin(movedaoaddrx, signer::address_of(admin)), errors::not_admin());
        
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
    public entry fun deposit(account: &signer, movedaoaddrx: address, amount: u64) acquires Treasury {
        let depositor = signer::address_of(account);
        let treasury_addr = get_legacy_treasury_addr(movedaoaddrx);
        assert!(exists<Treasury>(treasury_addr), errors::not_found());
        
        let treasury = borrow_global_mut<Treasury>(treasury_addr);
        
        // MEMBER-ONLY DEPOSITS: Only members or admins can deposit
        // This ensures only committed community members can fund the treasury
        if (!admin::is_admin(movedaoaddrx, depositor)) {
            assert!(membership::is_member(movedaoaddrx, depositor), errors::not_member());
        };
        
        // Validate amount
        assert!(amount > 0, errors::invalid_amount());
        
        let coins = coin::withdraw<AptosCoin>(account, amount);
        coin::merge(&mut treasury.balance, coins);
        
        // Emit deposit event
        event::emit(TreasuryDepositEvent {
            movedaoaddrxess: movedaoaddrx,
            depositor,
            amount,
            new_balance: coin::value(&treasury.balance),
            timestamp: timestamp::now_seconds(),
            transaction_hash: vector::empty(), // TODO: Add actual transaction hash
        });

        // Log treasury deposit activity (for legacy function consistency)
        activity_tracker::emit_activity(
            movedaoaddrx,                    // dao_address
            9,                               // activity_type: TREASURY_DEPOSIT
            depositor,                       // user_address
            string::utf8(b"Treasury Deposit"),                    // title
            string::utf8(b"Deposited tokens to DAO treasury"),   // description
            amount,                          // amount
            vector::empty<u8>(),             // metadata (empty for now)
            vector::empty<u8>(),             // transaction_hash (will be filled by the tracker)
            0                                // block_number (will be filled by the tracker)
        );
    }

    public entry fun withdraw(account: &signer, movedaoaddrx: address, amount: u64) acquires Treasury, ReentrancyGuard {
        assert!(admin::is_admin(movedaoaddrx, signer::address_of(account)), errors::not_admin());
        
        let treasury_addr = get_legacy_treasury_addr(movedaoaddrx);
        
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
            movedaoaddrxess: movedaoaddrx,
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
    public fun get_balance(movedaoaddrx: address): u64 acquires Treasury {
        let treasury_addr = get_legacy_treasury_addr(movedaoaddrx);
        if (!exists<Treasury>(treasury_addr)) return 0;
        
        let treasury = borrow_global<Treasury>(treasury_addr);
        coin::value(&treasury.balance)
    }

    // Helper function to determine treasury address for legacy functions
    #[view]
    fun get_legacy_treasury_addr(movedaoaddrx: address): address {
        // For object-based treasuries created through dao_core, we need to compute the object address
        // This is a simplified approach - in production, you might want to store this mapping
        movedaoaddrx // Simplified: assume treasury is at DAO address for legacy compatibility
    }
}