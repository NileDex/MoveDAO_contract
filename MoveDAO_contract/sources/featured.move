// Featured Badge System - Allows DAOs to purchase featured badges for visibility
module movedao_addrx::featured {
    use std::signer;
    use std::vector;
    use std::string;
    use aptos_std::simple_map::{Self, SimpleMap};
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::timestamp;
    use movedao_addrx::errors;
    use movedao_addrx::admin;
    use movedao_addrx::dao_core_file;
    use movedao_addrx::activity_tracker;

    // =============================================================================
    // CONSTANTS
    // =============================================================================
    
    const SECONDS_PER_MONTH: u64 = 2592000; // 30 days in seconds
    const SECONDS_PER_YEAR: u64 = 31536000; // 365 days in seconds

    // =============================================================================
    // DATA STRUCTURES
    // =============================================================================

    /// Featured badge data for a DAO
    struct BadgeData has copy, drop, store {
        purchased_at: u64,      // Timestamp when badge was purchased
        expires_at: u64,        // Timestamp when badge expires
        duration_months: u64,   // Number of months purchased (1 or 12)
    }

    /// Global registry tracking all featured badges
    struct FeaturedRegistry has key {
        badges: SimpleMap<address, BadgeData>, // Map of DAO address to badge data
        featured_addresses: vector<address>,   // List of addresses with (potentially) active badges
        monthly_price: u64,     // Price for 1 month in Octas
        yearly_price: u64,      // Price for 12 months in Octas
        fee_recipient: address, // Address to receive badge payments
    }

    // =============================================================================
    // EVENTS
    // =============================================================================

    #[event]
    struct BadgePurchased has drop, store {
        dao_address: address,
        purchaser: address,
        duration_months: u64,
        amount_paid: u64,
        expires_at: u64,
        timestamp: u64,
    }

    // =============================================================================
    // MODULE INITIALIZATION
    // =============================================================================

    /// Initialize featured registry on module deployment
    fun init_module(account: &signer) {
        move_to(account, FeaturedRegistry {
            badges: simple_map::create<address, BadgeData>(),
            featured_addresses: vector::empty<address>(),
            monthly_price: 5000000000,  // 50 MOVE (50 * 10^8 Octas)
            yearly_price: 60000000000,  // 600 MOVE (600 * 10^8 Octas)
            fee_recipient: signer::address_of(account),
        });
    }

    // =============================================================================
    // ENTRY FUNCTIONS
    // =============================================================================

    /// Purchase a featured badge for a DAO
    /// @param account - The signer purchasing the badge (must be DAO admin)
    /// @param dao_address - The address of the DAO to feature
    /// @param is_yearly - true for yearly badge (12 months), false for monthly (1 month)
    public entry fun purchase_featured_badge(
        account: &signer,
        dao_address: address,
        is_yearly: bool
    ) acquires FeaturedRegistry {
        let purchaser = signer::address_of(account);
        
        // Validate DAO exists
        assert!(dao_core_file::dao_exists(dao_address), errors::not_found());
        
        // Validate caller is admin of the DAO
        assert!(admin::is_admin(dao_address, purchaser), errors::not_admin());
        
        // Get registry
        assert!(exists<FeaturedRegistry>(@movedao_addrx), errors::not_found());
        let registry = borrow_global_mut<FeaturedRegistry>(@movedao_addrx);
        
        // Calculate payment amount and duration
        let (amount, duration_months, duration_seconds) = if (is_yearly) {
            (registry.yearly_price, 12u64, SECONDS_PER_YEAR)
        } else {
            (registry.monthly_price, 1u64, SECONDS_PER_MONTH)
        };
        
        // Transfer payment to fee recipient
        coin::transfer<AptosCoin>(account, registry.fee_recipient, amount);
        
        // Calculate expiration timestamp - extend if already active
        let now = timestamp::now_seconds();
        let expires_at = if (simple_map::contains_key(&registry.badges, &dao_address)) {
            let existing_badge = simple_map::borrow(&registry.badges, &dao_address);
            if (existing_badge.expires_at > now) {
                existing_badge.expires_at + duration_seconds
            } else {
                now + duration_seconds
            }
        } else {
            now + duration_seconds
        };
        
        // Create badge data
        let badge_data = BadgeData {
            purchased_at: now,
            expires_at,
            duration_months,
        };
        
        // Add or update badge in registry
        if (simple_map::contains_key(&registry.badges, &dao_address)) {
            // Update existing badge
            let existing_badge = simple_map::borrow_mut(&mut registry.badges, &dao_address);
            *existing_badge = badge_data;
        } else {
            // Add new badge
            simple_map::add(&mut registry.badges, dao_address, badge_data);
            // Add to featured addresses list if not already there (safety check)
            if (!vector::contains(&registry.featured_addresses, &dao_address)) {
                vector::push_back(&mut registry.featured_addresses, dao_address);
            };
        };
        
        // Emit badge purchased event
        0x1::event::emit(BadgePurchased {
            dao_address,
            purchaser,
            duration_months,
            amount_paid: amount,
            expires_at,
            timestamp: now,
        });
        
        // Log activity
        activity_tracker::emit_activity(
            dao_address,
            14, // ACTIVITY_TYPE_FEATURED_BADGE_PURCHASE
            purchaser,
            string::utf8(b"Featured Badge Purchased"),
            if (is_yearly) {
                string::utf8(b"Purchased yearly featured badge (12 months)")
            } else {
                string::utf8(b"Purchased monthly featured badge (1 month)")
            },
            amount,
            vector::empty<u8>(),
            vector::empty<u8>(),
            expires_at
        );
    }

    /// Update badge pricing (admin only)
    public entry fun update_badge_pricing(
        admin: &signer,
        new_monthly_price: u64,
        new_yearly_price: u64
    ) acquires FeaturedRegistry {
        let addr = signer::address_of(admin);
        assert!(addr == @movedao_addrx, errors::not_admin());
        
        assert!(exists<FeaturedRegistry>(@movedao_addrx), errors::not_found());
        let registry = borrow_global_mut<FeaturedRegistry>(@movedao_addrx);
        
        registry.monthly_price = new_monthly_price;
        registry.yearly_price = new_yearly_price;
    }

    /// Update fee recipient (admin only)
    public entry fun update_fee_recipient(
        admin: &signer,
        new_recipient: address
    ) acquires FeaturedRegistry {
        let addr = signer::address_of(admin);
        assert!(addr == @movedao_addrx, errors::not_admin());
        assert!(exists<FeaturedRegistry>(@movedao_addrx), errors::not_found());
        let registry = borrow_global_mut<FeaturedRegistry>(@movedao_addrx);
        
        registry.fee_recipient = new_recipient;
    }

    /// Prune expired badges from the registry to save storage and improve performance
    /// Can be called by anyone to help maintain the system
    public entry fun prune_expired_badges() acquires FeaturedRegistry {
        assert!(exists<FeaturedRegistry>(@movedao_addrx), errors::not_found());
        let registry = borrow_global_mut<FeaturedRegistry>(@movedao_addrx);
        
        let now = timestamp::now_seconds();
        let i = 0;
        let len = vector::length(&registry.featured_addresses);
        let new_featured_addresses = vector::empty<address>();
        
        while (i < len) {
            let dao_addr = *vector::borrow(&registry.featured_addresses, i);
            let remove = false;
            
            if (simple_map::contains_key(&registry.badges, &dao_addr)) {
                let badge = simple_map::borrow(&registry.badges, &dao_addr);
                if (badge.expires_at <= now) {
                    remove = true;
                };
            } else {
                // If it's in the list but not in the map, it shouldn't be here
                remove = true;
            };
            
            if (remove) {
                // Remove from map if it exists
                if (simple_map::contains_key(&registry.badges, &dao_addr)) {
                    simple_map::remove(&mut registry.badges, &dao_addr);
                };
                // Don't add to new_featured_addresses
            } else {
                vector::push_back(&mut new_featured_addresses, dao_addr);
            };
            
            i = i + 1;
        };
        
        registry.featured_addresses = new_featured_addresses;
    }

    // =============================================================================
    // VIEW FUNCTIONS
    // =============================================================================

    #[view]
    /// Get all currently featured DAO addresses (with active, non-expired badges)
    public fun get_featured_daos(): vector<address> acquires FeaturedRegistry {
        assert!(exists<FeaturedRegistry>(@movedao_addrx), errors::not_found());
        let registry = borrow_global<FeaturedRegistry>(@movedao_addrx);
        
        let featured = vector::empty<address>();
        let now = timestamp::now_seconds();
        
        // Use the tracked list of featured addresses for O(N_featured) performance
        let i = 0;
        let len = vector::length(&registry.featured_addresses);
        
        while (i < len) {
            let dao_addr = *vector::borrow(&registry.featured_addresses, i);
            
            // Check if DAO has an active badge
            if (simple_map::contains_key(&registry.badges, &dao_addr)) {
                let badge = simple_map::borrow(&registry.badges, &dao_addr);
                if (badge.expires_at > now) {
                    vector::push_back(&mut featured, dao_addr);
                }
            };
            
            i = i + 1;
        };
        
        featured
    }

    #[view]
    /// Check if a specific DAO is currently featured
    public fun is_dao_featured(dao_address: address): bool acquires FeaturedRegistry {
        assert!(exists<FeaturedRegistry>(@movedao_addrx), errors::not_found());
        let registry = borrow_global<FeaturedRegistry>(@movedao_addrx);
        
        if (!simple_map::contains_key(&registry.badges, &dao_address)) {
            return false
        };
        
        let badge = simple_map::borrow(&registry.badges, &dao_address);
        let now = timestamp::now_seconds();
        
        badge.expires_at > now
    }

    #[view]
    /// Get badge information for a specific DAO
    /// Returns (purchased_at, expires_at, duration_months, is_active)
    public fun get_badge_info(dao_address: address): (u64, u64, u64, bool) acquires FeaturedRegistry {
        assert!(exists<FeaturedRegistry>(@movedao_addrx), errors::not_found());
        let registry = borrow_global<FeaturedRegistry>(@movedao_addrx);
        
        assert!(simple_map::contains_key(&registry.badges, &dao_address), errors::not_found());
        let badge = simple_map::borrow(&registry.badges, &dao_address);
        
        let now = timestamp::now_seconds();
        let is_active = badge.expires_at > now;
        
        (badge.purchased_at, badge.expires_at, badge.duration_months, is_active)
    }

    #[view]
    /// Get current badge pricing
    /// Returns (monthly_price, yearly_price)
    public fun get_badge_pricing(): (u64, u64) acquires FeaturedRegistry {
        assert!(exists<FeaturedRegistry>(@movedao_addrx), errors::not_found());
        let registry = borrow_global<FeaturedRegistry>(@movedao_addrx);
        
        (registry.monthly_price, registry.yearly_price)
    }

    #[view]
    /// Get fee recipient address
    public fun get_fee_recipient(): address acquires FeaturedRegistry {
        assert!(exists<FeaturedRegistry>(@movedao_addrx), errors::not_found());
        let registry = borrow_global<FeaturedRegistry>(@movedao_addrx);
        
        registry.fee_recipient
    }
}
