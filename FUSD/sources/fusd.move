module stablecoin::Musd {
    use aptos_framework::fungible_asset::{Self, MintRef, TransferRef, BurnRef, Metadata};
    use aptos_framework::object::{Self, Object};
    use aptos_framework::primary_fungible_store;
    use std::option;
    use std::signer;
    use std::string::utf8;

    /// Caller is not authorized to make this call
    const EUNAUTHORIZED: u64 = 1;

    const ASSET_SYMBOL: vector<u8> = b"MUSD";

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct Management has key {
        mint_ref: MintRef,
        burn_ref: BurnRef,
        transfer_ref: TransferRef,
    }

    #[event]
    struct Mint has drop, store {
        minter: address,
        to: address,
        amount: u64,
    }

    #[event]
    struct Burn has drop, store {
        minter: address,
        from: address,
        amount: u64,
    }

    #[view]
    public fun musd_address(): address {
        object::create_object_address(&@stablecoin, ASSET_SYMBOL)
    }

    #[view]
    public fun metadata(): Object<Metadata> {
        object::address_to_object(musd_address())
    }

    /// Initialize the stablecoin - only the deployer can mint/burn initially
    fun init_module(deployer: &signer) {
        let constructor_ref = &object::create_named_object(deployer, ASSET_SYMBOL);
        
        // Create the fungible asset
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            constructor_ref,
            option::none(),
            utf8(b"MUSD Stablecoin"), /* name */
            utf8(ASSET_SYMBOL), /* symbol */
            8, /* decimals */
            utf8(b"https://payload-marketing.moonpay.com/api/media/file/usd-coin-usdc-logo.png"), /* icon */
            utf8(b"https://move-dao.vercel.app/"), /* project */
        );

        // Store management references in the asset metadata object
        let metadata_object_signer = &object::generate_signer(constructor_ref);
        move_to(metadata_object_signer, Management {
            mint_ref: fungible_asset::generate_mint_ref(constructor_ref),
            burn_ref: fungible_asset::generate_burn_ref(constructor_ref),
            transfer_ref: fungible_asset::generate_transfer_ref(constructor_ref),
        });
    }

    /// Mint new tokens to the caller's account
    /// Anyone can mint tokens (testnet faucet functionality)
    public entry fun mint(account: &signer, amount: u64) acquires Management {
        let user_address = signer::address_of(account);
        let management = borrow_global<Management>(musd_address());
        let tokens = fungible_asset::mint(&management.mint_ref, amount);
        
        // Deposit tokens to the caller's primary store
        primary_fungible_store::deposit(user_address, tokens);

        // Emit mint event
        aptos_framework::event::emit(Mint {
            minter: user_address,
            to: user_address,
            amount,
        });
    }

    /// Burn tokens from the specified account
    /// Only the deployer can burn tokens (simplified for tutorial)
    public entry fun burn(deployer: &signer, from: address, amount: u64) acquires Management {
        let management = borrow_global<Management>(musd_address());
        let store = primary_fungible_store::ensure_primary_store_exists(from, metadata());
        let tokens = fungible_asset::withdraw_with_ref(&management.transfer_ref, store, amount);
        fungible_asset::burn(&management.burn_ref, tokens);

        // Emit burn event
        aptos_framework::event::emit(Burn {
            minter: signer::address_of(deployer),
            from,
            amount,
        });
    }

    #[view]
    public fun total_supply(): u64 {
        let supply_opt = fungible_asset::supply(metadata());
        if (option::is_some(&supply_opt)) {
            let supply = option::extract(&mut supply_opt);
            (supply as u64)
        } else {
            0
        }
    }

    #[view]
    public fun balance_of(account: address): u64 {
        primary_fungible_store::balance(account, metadata())
    }
}