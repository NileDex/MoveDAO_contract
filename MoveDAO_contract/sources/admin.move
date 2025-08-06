// Admin system - manages DAO administrators with different roles and permissions (Super, Standard, Temporary)
module dao_addr::admin {
    use std::signer;
    use std::vector;
    use std::simple_map::{Self, SimpleMap};
    use std::event;
    use aptos_framework::timestamp;
    use dao_addr::errors;

    // Role constants
    const ROLE_SUPER_ADMIN: u8 = 255;
    const ROLE_STANDARD: u8 = 100;
    const ROLE_TEMPORARY: u8 = 50;

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
        dao_addr: address,
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
        errors::require_admin(is_admin(dao_addr, admin_addr));
        let admin_list = borrow_global_mut<AdminList>(dao_addr);
        let now = timestamp::now_seconds();
        let expires_at = if (expires_in_secs > 0) now + expires_in_secs else 0;

        // Require at least 2 seconds for temporary admins to avoid race conditions
        if (expires_at > 0 && expires_in_secs < 2) abort errors::expiration_past();

        simple_map::add(&mut admin_list.admins, new_admin, Admin {
            role,
            added_at: now,
            expires_at
        });

        emit_admin_event(dao_addr, new_admin, b"added", role, expires_at);
    }

    // Remove admin
    public entry fun remove_admin(
        admin_account: &signer,
        dao_addr: address,
        admin_to_remove: address
    ) acquires AdminList {
        let admin_addr = signer::address_of(admin_account);
        errors::require_admin(is_admin(dao_addr, admin_addr));
        
        let admin_list = borrow_global_mut<AdminList>(dao_addr);
        errors::require_exists(simple_map::contains_key(&admin_list.admins, &admin_to_remove), errors::admin_not_found());
        
        let admin = simple_map::borrow(&admin_list.admins, &admin_to_remove);
        let role = admin.role;
        let expires_at = admin.expires_at;
        
        // Prevent removing super admins if it would violate minimum constraint
        if (role == ROLE_SUPER_ADMIN) {
            let super_admin_count = count_super_admins(admin_list);
            assert!(super_admin_count > admin_list.min_super_admins, errors::min_members_constraint());
        };
        
        simple_map::remove(&mut admin_list.admins, &admin_to_remove);
        emit_admin_event(dao_addr, admin_to_remove, b"removed", role, expires_at);
    }

    // View functions
    #[view]
    public fun is_admin(dao_addr: address, addr: address): bool acquires AdminList {
        if (!exists<AdminList>(dao_addr)) return false;
        let admin_list = borrow_global<AdminList>(dao_addr);
        simple_map::contains_key(&admin_list.admins, &addr) && !is_expired(admin_list, addr)
    }

    #[view]
    public fun get_admin_role(dao_addr: address, addr: address): u8 acquires AdminList {
        errors::require_exists(exists<AdminList>(dao_addr), errors::admin_not_found());
        let admin_list = borrow_global<AdminList>(dao_addr);
        errors::require_exists(simple_map::contains_key(&admin_list.admins, &addr), errors::admin_not_found());
        simple_map::borrow(&admin_list.admins, &addr).role
    }

    #[view]
    public fun get_admins(dao_addr: address): vector<address> acquires AdminList {
        let admin_list = borrow_global<AdminList>(dao_addr);
        // Direct access to keys is more efficient than manual iteration
        simple_map::keys(&admin_list.admins)
    }

    // New efficient helper functions
    #[view]
    public fun get_admin_count(dao_addr: address): u64 acquires AdminList {
        let admin_list = borrow_global<AdminList>(dao_addr);
        simple_map::length(&admin_list.admins)
    }

    #[view]
    public fun not_admin_error_code(): u64 { errors::not_admin() }

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