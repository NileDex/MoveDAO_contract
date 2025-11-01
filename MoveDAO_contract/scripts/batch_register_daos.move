script {
    use movedao_addrx::dao_core_file as dao_core;
    use std::vector;

    fun batch_register_daos(admin: &signer, dao_addresses: vector<address>) {
        // Ensure registry is initialized (admin only)
        dao_core::check_and_init_registry(admin);
        
        // Add each DAO to registry
        let i = 0;
        let len = vector::length(&dao_addresses);
        while (i < len) {
            let dao_addr = *vector::borrow(&dao_addresses, i);
            if (dao_core::dao_exists(dao_addr)) {
                dao_core::add_dao_to_registry(admin, dao_addr);
            };
            i = i + 1;
        };
    }
}