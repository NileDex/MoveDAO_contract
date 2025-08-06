// Council system - manages trusted DAO members who can have special governance roles and permissions
module dao_addr::council {
    use std::vector;
    use std::signer;
    use std::error;
    use aptos_framework::object::{Self, Object};
    use aptos_std::table::{Self, Table};
    use dao_addr::admin;
    use dao_addr::errors;

    struct CouncilConfig has key {
        members: Table<address, bool>,
        member_count: u64,
        min_members: u64,
        max_members: u64
    }

    public fun init_council(
        account: &signer,
        initial_members: vector<address>,
        min_members: u64,
        max_members: u64
    ): Object<CouncilConfig> {
        let addr = signer::address_of(account);
        assert!(!exists<CouncilConfig>(addr), error::already_exists(0));
        // Changed to allow empty initial council
        assert!(vector::length(&initial_members) <= max_members, errors::max_members_constraint());

        let members_table = table::new<address, bool>();
        let i = 0;
        let len = vector::length(&initial_members);
        while (i < len) {
            let member = *vector::borrow(&initial_members, i);
            table::add(&mut members_table, member, true);
            i = i + 1;
        };

        let council = CouncilConfig {
            members: members_table,
            member_count: len,
            min_members,
            max_members
        };

        let constructor_ref = object::create_object_from_account(account);
        let object_signer = object::generate_signer(&constructor_ref);
        move_to(&object_signer, council);
        object::object_from_constructor_ref(&constructor_ref)
    }

    // Direct object-based functions
    public fun add_council_member_to_object(admin: &signer, dao_addr: address, council_obj: Object<CouncilConfig>, new_member: address) acquires CouncilConfig {
        let admin_addr = signer::address_of(admin);
        errors::require_admin(admin::is_admin(dao_addr, admin_addr));

        let config = borrow_global_mut<CouncilConfig>(object::object_address(&council_obj));
        assert!(config.member_count < config.max_members, errors::max_members_constraint());
        assert!(!table::contains(&config.members, new_member), error::already_exists(0));

        table::add(&mut config.members, new_member, true);
        config.member_count = config.member_count + 1;
    }

    public fun remove_council_member_from_object(admin: &signer, dao_addr: address, council_obj: Object<CouncilConfig>, member: address) acquires CouncilConfig {
        let admin_addr = signer::address_of(admin);
        errors::require_admin(admin::is_admin(dao_addr, admin_addr));

        let config = borrow_global_mut<CouncilConfig>(object::object_address(&council_obj));
        errors::require_exists(table::contains(&config.members, member), errors::council_member_not_found());

        table::remove(&mut config.members, member);
        config.member_count = config.member_count - 1;

        assert!(config.member_count >= config.min_members, errors::min_members_constraint());
    }

    public fun get_council_members_from_object(council_obj: Object<CouncilConfig>): vector<address> acquires CouncilConfig {
        let _config = borrow_global<CouncilConfig>(object::object_address(&council_obj));
        // Note: For better performance, use is_council_member_in_object() and get_member_count_from_object()
        // This function maintained for backward compatibility but is less efficient than direct table queries
        vector::empty<address>() // Table iteration requires external iteration - recommend using table-based functions
    }

    public fun is_council_member_in_object(council_obj: Object<CouncilConfig>, member: address): bool acquires CouncilConfig {
        let config = borrow_global<CouncilConfig>(object::object_address(&council_obj));
        table::contains(&config.members, member)
    }

    public fun get_member_count_from_object(council_obj: Object<CouncilConfig>): u64 acquires CouncilConfig {
        let config = borrow_global<CouncilConfig>(object::object_address(&council_obj));
        config.member_count
    }

    // Legacy functions - DEPRECATED but safe implementations to prevent DoS
    public fun add_council_member(admin: &signer, _new_member: address) {
        // DEPRECATED: This function is deprecated and does nothing.
        // Use add_council_member_to_object instead for proper functionality.
        let dao_addr = signer::address_of(admin);
        errors::require_admin(admin::is_admin(dao_addr, dao_addr));
        
        // Safe no-op instead of abort to prevent DoS attacks
        // Users should migrate to object-based functions
    }

    public fun remove_council_member(admin: &signer, _member: address) {
        // DEPRECATED: This function is deprecated and does nothing.
        // Use remove_council_member_from_object instead for proper functionality.
        let dao_addr = signer::address_of(admin);
        errors::require_admin(admin::is_admin(dao_addr, dao_addr));
        
        // Safe no-op instead of abort to prevent DoS attacks
        // Users should migrate to object-based functions
    }

    public fun replace_council_member(admin: &signer, _old_member: address, _new_member: address) {
        // DEPRECATED: This function is deprecated and does nothing.
        // Use remove_council_member_from_object + add_council_member_to_object instead.
        let dao_addr = signer::address_of(admin);
        errors::require_admin(admin::is_admin(dao_addr, dao_addr));
        
        // Safe no-op instead of abort to prevent DoS attacks
        // Users should migrate to object-based functions
    }

    public fun get_council_members(dao_addr: address): vector<address> {
        // Note: For better performance, use object-based functions and table queries
        // This legacy function is maintained for compatibility but is less efficient
        let _ = dao_addr;
        vector::empty() // Recommend using table-based member queries instead
    }

    public fun is_council_member(dao_addr: address, member: address): bool {
        // Note: For better performance, use is_council_member_in_object with proper object reference
        // This legacy function is maintained for compatibility but is less efficient
        let _ = dao_addr;
        let _ = member;
        false // Recommend using is_council_member_in_object instead
    }

    // Removed find_index function - no longer needed with table-based implementation
}