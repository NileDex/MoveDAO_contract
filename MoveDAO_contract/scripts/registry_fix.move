script {
    use movedaoaddrx::dao_core_file as dao_core;
    use std::vector;

    fun fix_registry(admin: &signer) {
        // First, initialize the DAO registry (admin only)
        dao_core::check_and_init_registry(admin);
        
        // Define known existing DAOs that need to be added to registry
        let existing_daos = vector::empty<address>();
        vector::push_back(&mut existing_daos, @0xc2ed434a9696ec7e41d99b4d855159894a2b3f154ecbb0c4f3a4566b318aaf90);
        
        // Add each existing DAO to the registry if it exists and isn't already registered
        let i = 0;
        let len = vector::length(&existing_daos);
        while (i < len) {
            let dao_addr = *vector::borrow(&existing_daos, i);
            if (dao_core::dao_exists(dao_addr)) {
                dao_core::add_dao_to_registry(admin, dao_addr);
            };
            i = i + 1;
        };
    }
}