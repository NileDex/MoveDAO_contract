module dao_addr::council {
    use std::vector;
    use std::option;
    use std::signer;
    use std::error;
    use aptos_framework::object::{Self, Object};
    use dao_addr::admin;

    const ENOT_ADMIN: u64 = 1;
    const ECOUNCIL_MEMBER_NOT_FOUND: u64 = 2;
    const EMIN_MEMBERS_CONSTRAINT: u64 = 8;
    const EMAX_MEMBERS_CONSTRAINT: u64 = 9;

    struct CouncilConfig has key {
        members: vector<address>,
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
        assert!(vector::length(&initial_members) <= max_members, error::invalid_argument(EMAX_MEMBERS_CONSTRAINT));

        let council = CouncilConfig {
            members: initial_members,
            min_members,
            max_members
        };

        let constructor_ref = object::create_object_from_account(account);
        let object_signer = object::generate_signer(&constructor_ref);
        move_to(&object_signer, council);
        object::object_from_constructor_ref(&constructor_ref)
    }

    // Direct object-based functions
    public fun add_council_member_to_object(admin: &signer, council_obj: Object<CouncilConfig>, new_member: address) acquires CouncilConfig {
        let addr = signer::address_of(admin);
        assert!(admin::is_admin(addr, addr), error::invalid_argument(ENOT_ADMIN));

        let config = borrow_global_mut<CouncilConfig>(object::object_address(&council_obj));
        let current_len = vector::length(&config.members);
        assert!(current_len < config.max_members, error::invalid_argument(EMAX_MEMBERS_CONSTRAINT));

        vector::push_back(&mut config.members, new_member);
    }

    public fun remove_council_member_from_object(admin: &signer, council_obj: Object<CouncilConfig>, member: address) acquires CouncilConfig {
        let addr = signer::address_of(admin);
        assert!(admin::is_admin(addr, addr), error::invalid_argument(ENOT_ADMIN));

        let config = borrow_global_mut<CouncilConfig>(object::object_address(&council_obj));
        let index_option = find_index(&config.members, member);
        assert!(option::is_some(&index_option), error::invalid_argument(ECOUNCIL_MEMBER_NOT_FOUND));

        let index = option::extract(&mut index_option);
        vector::remove(&mut config.members, index);

        assert!(vector::length(&config.members) >= config.min_members, error::invalid_argument(EMIN_MEMBERS_CONSTRAINT));
    }

    public fun get_council_members_from_object(council_obj: Object<CouncilConfig>): vector<address> acquires CouncilConfig {
        let config = borrow_global<CouncilConfig>(object::object_address(&council_obj));
        config.members
    }

    public fun is_council_member_in_object(council_obj: Object<CouncilConfig>, member: address): bool acquires CouncilConfig {
        let config = borrow_global<CouncilConfig>(object::object_address(&council_obj));
        vector::contains(&config.members, &member)
    }

    // Legacy functions - temporarily stubbed out to avoid circular dependency
    public fun add_council_member(admin: &signer, _new_member: address) {
        // This will be implemented once the circular dependency is resolved
        let _ = admin; // Suppress unused warning
        abort 999 // Temporary placeholder
    }

    public fun remove_council_member(admin: &signer, _member: address) {
        // This will be implemented once the circular dependency is resolved  
        let _ = admin; // Suppress unused warning
        abort 999 // Temporary placeholder
    }

    public fun replace_council_member(admin: &signer, _old_member: address, _new_member: address) {
        // This will be implemented once the circular dependency is resolved
        let _ = admin; // Suppress unused warning
        abort 999 // Temporary placeholder
    }

    public fun get_council_members(_dao_addr: address): vector<address> {
        // This will be implemented once the circular dependency is resolved
        vector::empty() // Temporary placeholder
    }

    public fun is_council_member(_dao_addr: address, _member: address): bool {
        // This will be implemented once the circular dependency is resolved
        false // Temporary placeholder
    }

    fun find_index(vec: &vector<address>, value: address): option::Option<u64> {
        let len = vector::length(vec);
        let i = 0;
        while (i < len) {
            if (*vector::borrow(vec, i) == value) {
                return option::some(i)
            };
            i = i + 1;
        };
        option::none()
    }
}