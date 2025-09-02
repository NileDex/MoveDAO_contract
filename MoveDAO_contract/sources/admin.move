// Admin system - manages DAO administrators with different roles and permissions (Super, Standard, Temporary)
module movedaoaddrx::admin {
    use std::signer;
    use std::vector;
    use std::simple_map::{Self, SimpleMap};
    use std::event;
    use aptos_framework::timestamp;
    use movedaoaddrx::errors;

    // Role constants
    const ROLE_SUPER_ADMIN: u8 = 255;
    const ROLE_STANDARD: u8 = 100;
    const ROLE_TEMPORARY: u8 = 50;
    
    // Security limits
    const MAX_SUPER_ADMINS: u64 = 5;

    struct Admin has store, copy, drop {
        role: u8,
        added_at: u64,
        expires_at: u64
    }

    struct AdminList has key {
        admins: SimpleMap<address, Admin>,
        min_super_admins: u64
    }

    #[event]
    struct AdminChanged has drop, store {
        actor: address,
        target: address,
        action: vector<u8>,
        role: u8,
        expires_at: u64
    }

    // Public role getters 
    public fun role_super_admin(): u8 { ROLE_SUPER_ADMIN }
    public fun role_standard(): u8 { ROLE_STANDARD }
    public fun role_temporary(): u8 { ROLE_TEMPORARY }

    // Initialize admin module
    public fun init_admin(account: &signer, min_super_admins: u64) {
        let addr = signer::address_of(account);
        errors::require_not_exists(!exists<AdminList>(addr), errors::admin_list_exists());
        
        let admins = simple_map::new();
        simple_map::add(&mut admins, addr, Admin {
            role: ROLE_SUPER_ADMIN,
            added_at: timestamp::now_seconds(),
            expires_at: 0
        });

        let admin_list = AdminList {
            admins,
            min_super_admins
        };

        // Move the AdminList directly to the account (keeping direct storage for admin)
        move_to(account, admin_list);

        emit_admin_event(addr, addr, b"added", ROLE_SUPER_ADMIN, 0);
    }

    // Add new admin
    public entry fun add_admin(
        admin_account: &signer,
        movedaoaddrx: address,
        new_admin: address,
        role: u8,
        expires_in_secs: u64
    ) acquires AdminList {
        assert!(
            role == ROLE_SUPER_ADMIN || 
            role == ROLE_STANDARD || 
            role == ROLE_TEMPORARY, 
            errors::invalid_role()
        );
        
        let admin_addr = signer::address_of(admin_account);
        errors::require_admin(is_admin(movedaoaddrx, admin_addr));
        
        // Get caller's role before acquiring mutable reference
        let caller_role = get_admin_role(movedaoaddrx, admin_addr);
        let admin_list = borrow_global_mut<AdminList>(movedaoaddrx);
        
        // Role hierarchy enforcement: only super admins can add super admins
        if (role == ROLE_SUPER_ADMIN) {
            assert!(caller_role == ROLE_SUPER_ADMIN, errors::not_authorized());
            // Security check: limit total number of super admins to prevent governance takeover
            let current_super_admin_count = count_super_admins(admin_list);
            assert!(current_super_admin_count < MAX_SUPER_ADMINS, errors::invalid_amount());
        };
        
        // Only super admins can create permanent admins (expires_in_secs = 0)
        if (expires_in_secs == 0) {
            assert!(caller_role == ROLE_SUPER_ADMIN, errors::not_authorized());
        };
        
        let now = timestamp::now_seconds();
        let expires_at = if (expires_in_secs > 0) now + expires_in_secs else 0;

        // Require at least 300 seconds (5 minutes) for temporary admins to prevent race conditions
        if (expires_at > 0 && expires_in_secs < 300) abort errors::expiration_past();

        simple_map::add(&mut admin_list.admins, new_admin, Admin {
            role,
            added_at: now,
            expires_at
        });

        emit_admin_event(movedaoaddrx, new_admin, b"added", role, expires_at);
    }

    // Remove admin
    public entry fun remove_admin(
        admin_account: &signer,
        movedaoaddrx: address,
        admin_to_remove: address
    ) acquires AdminList {
        let admin_addr = signer::address_of(admin_account);
        errors::require_admin(is_admin(movedaoaddrx, admin_addr));
        
        // Get caller's role before acquiring mutable reference
        let caller_role = get_admin_role(movedaoaddrx, admin_addr);
        
        let admin_list = borrow_global_mut<AdminList>(movedaoaddrx);
        errors::require_exists(simple_map::contains_key(&admin_list.admins, &admin_to_remove), errors::admin_not_found());
        
        let admin = simple_map::borrow(&admin_list.admins, &admin_to_remove);
        let role = admin.role;
        let expires_at = admin.expires_at;
        
        // Role hierarchy enforcement: only super admins can remove super admins
        if (role == ROLE_SUPER_ADMIN) {
            assert!(caller_role == ROLE_SUPER_ADMIN, errors::not_authorized());
            // Prevent removing super admins if it would violate minimum constraint
            let super_admin_count = count_super_admins(admin_list);
            assert!(super_admin_count > admin_list.min_super_admins, errors::min_members_constraint());
        };
        
        simple_map::remove(&mut admin_list.admins, &admin_to_remove);
        emit_admin_event(movedaoaddrx, admin_to_remove, b"removed", role, expires_at);
    }

    // View functions
    #[view]
    public fun is_admin(movedaoaddrx: address, addr: address): bool acquires AdminList {
        if (!exists<AdminList>(movedaoaddrx)) return false;
        let admin_list = borrow_global<AdminList>(movedaoaddrx);
        simple_map::contains_key(&admin_list.admins, &addr) && !is_expired(admin_list, addr)
    }

    #[view]
    public fun get_admin_role(movedaoaddrx: address, addr: address): u8 acquires AdminList {
        errors::require_exists(exists<AdminList>(movedaoaddrx), errors::admin_not_found());
        let admin_list = borrow_global<AdminList>(movedaoaddrx);
        errors::require_exists(simple_map::contains_key(&admin_list.admins, &addr), errors::admin_not_found());
        simple_map::borrow(&admin_list.admins, &addr).role
    }

    #[view]
    public fun get_admins(movedaoaddrx: address): vector<address> acquires AdminList {
        let admin_list = borrow_global<AdminList>(movedaoaddrx);
        // Direct access to keys is more efficient than manual iteration
        simple_map::keys(&admin_list.admins)
    }

    // New efficient helper functions
    #[view]
    public fun get_admin_count(movedaoaddrx: address): u64 acquires AdminList {
        let admin_list = borrow_global<AdminList>(movedaoaddrx);
        simple_map::length(&admin_list.admins)
    }

    #[view]
    public fun not_admin_error_code(): u64 { errors::not_admin() }

    // Check if admin system is initialized for a DAO
    #[view]
    public fun exists_admin_list(movedaoaddrx: address): bool {
        exists<AdminList>(movedaoaddrx)
    }

    // Helper functions
    fun is_expired(admin_list: &AdminList, addr: address): bool {
        let admin = simple_map::borrow(&admin_list.admins, &addr);
        admin.expires_at > 0 && timestamp::now_seconds() >= admin.expires_at
    }

    fun count_super_admins(admin_list: &AdminList): u64 {
        let i = 0;
        let count = 0;
        let keys = simple_map::keys(&admin_list.admins);
        let len = vector::length(&keys);
        
        while (i < len) {
            let addr = vector::borrow(&keys, i);
            let admin = simple_map::borrow(&admin_list.admins, addr);
            if (admin.role == ROLE_SUPER_ADMIN && !is_expired(admin_list, *addr)) {
                count = count + 1;
            };
            i = i + 1;
        };
        count
    }

    fun emit_admin_event(
        actor: address,
        target: address,
        action: vector<u8>,
        role: u8,
        expires_at: u64
    ) {
        event::emit(AdminChanged {
            actor,
            target,
            action,
            role,
            expires_at
        });
    }
}