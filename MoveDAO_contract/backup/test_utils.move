#[test_only]
module movedaoaddrx::test_utils_backup {
    use std::signer;
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin;
    use aptos_framework::timestamp;

    struct TestData has key {
        mint_cap: coin::MintCapability<aptos_coin::AptosCoin>,
        burn_cap: coin::BurnCapability<aptos_coin::AptosCoin>,
    }

    /// Initialize the Aptos framework for testing
    /// This should be called once per test with the aptos_framework signer
    public fun setup_aptos(account: &signer) {
        // Note: timestamp should already be set up by the test framework
        // before calling this function
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(account);
        move_to(account, TestData { mint_cap, burn_cap });
    }

    /// Set up a test account with AptosCoin registration and initial balance
    public fun setup_test_account(account: &signer) acquires TestData {
        // Ensure the framework is initialized
        if (!exists<TestData>(@0x1)) {
            let aptos_framework = account::create_signer_for_test(@0x1);
            setup_aptos(&aptos_framework);
        };

        // Register coin for the test account if not already registered
        if (!coin::is_account_registered<aptos_coin::AptosCoin>(signer::address_of(account))) {
            coin::register<aptos_coin::AptosCoin>(account);
        };

        // Mint and deposit initial coins (1000 APTOS)
        let mint_cap = &borrow_global<TestData>(@0x1).mint_cap;
        let coins = coin::mint(1000, mint_cap);
        coin::deposit(signer::address_of(account), coins);
    }

    /// Mint additional AptosCoin for a test account
    public fun mint_aptos(account: &signer, amount: u64) acquires TestData {
        // Ensure the account has AptosCoin registered
        if (!coin::is_account_registered<aptos_coin::AptosCoin>(signer::address_of(account))) {
            coin::register<aptos_coin::AptosCoin>(account);
        };

        let mint_cap = &borrow_global<TestData>(@0x1).mint_cap;
        let coins = coin::mint(amount, mint_cap);
        coin::deposit(signer::address_of(account), coins);
    }

    #[view]
    public fun get_aptos_balance(account_addr: address): u64 {
        if (coin::is_account_registered<aptos_coin::AptosCoin>(account_addr)) {
            coin::balance<aptos_coin::AptosCoin>(account_addr)
        } else {
            0
        }
    }

    /// Clean up test capabilities - should be called at the end of each test
    public fun destroy_caps(account: &signer) acquires TestData {
        let account_addr = signer::address_of(account);
        if (exists<TestData>(account_addr)) {
            let TestData { mint_cap, burn_cap } = move_from<TestData>(account_addr);
            coin::destroy_mint_cap<aptos_coin::AptosCoin>(mint_cap);
            coin::destroy_burn_cap<aptos_coin::AptosCoin>(burn_cap);
        }
    }

    #[test_only]
    public fun set_time_for_test(time_secs: u64) {
        timestamp::update_global_time_for_test_secs(time_secs);
    }

    #[test_only]
    public fun fast_forward_time(seconds: u64) {
        let current_time = timestamp::now_seconds();
        timestamp::update_global_time_for_test_secs(current_time + seconds);
    }

    /// Create and fund a new test account with specified amount
    public fun create_funded_account(account_addr: address, amount: u64): signer acquires TestData {
        account::create_account_for_test(account_addr);
        let account_signer = account::create_signer_for_test(account_addr);
        setup_test_account(&account_signer);
        if (amount > 1000) {
            mint_aptos(&account_signer, amount - 1000); // setup_test_account already gives 1000
        };
        account_signer
    }

    /// Burn AptosCoin from an account (useful for testing edge cases)
    public fun burn_aptos(account: &signer, amount: u64) acquires TestData {
        let burn_cap = &borrow_global<TestData>(@0x1).burn_cap;
        let coins = coin::withdraw<aptos_coin::AptosCoin>(account, amount);
        coin::burn(coins, burn_cap);
    }

    #[view]
    public fun is_test_account_ready(account_addr: address): bool {
        coin::is_account_registered<aptos_coin::AptosCoin>(account_addr) &&
        coin::balance<aptos_coin::AptosCoin>(account_addr) > 0
    }

    /// Initialize DAO registry for testing
    /// This mimics the init_module behavior for test environment
    public fun init_dao_registry_for_test() {
        // Create the module account signer for @movedaoaddrx
        let dao_module_signer = account::create_signer_for_test(@movedaoaddrx);
        
        // Check if registry already exists to avoid duplicate initialization
        if (!exists<DAORegistry>(@movedaoaddrx)) {
            move_to(&dao_module_signer, DAORegistry {
                dao_addresses: vector::empty(),
                total_daos: 0
            });
        }
    }

    // Mirror the DAORegistry struct from dao_core for test initialization
    struct DAORegistry has key {
        dao_addresses: vector<address>,
        total_daos: u64
    }
}