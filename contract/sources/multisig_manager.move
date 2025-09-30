/// A module for managing an off-chain multisig...
///
/// Manages a MultiEd25519 (someday MultiKey), similar to Msafe V1.  It should be compatible, if you know all the public keys, and the wallets supporting them.
module mm_addr::multisig_manager {
    use std::string::String;
    use std::option::Option;
    use std::signer;
    use aptos_framework::object;
    use aptos_framework::account;
    use aptos_framework::hash;
    use aptos_framework::from_bcs;
    use aptos_framework::bcs;
    use aptos_std::table;
    use mm_addr::queue::{Self, MultisigQueue};
    use mm_addr::config::{Self, MultisigConfig};
    use mm_addr::events;
    use mm_addr::owner;
    use mm_addr::transaction::{Self, PendingTransaction};

    /// Invalid threshold, must be > 0 and less than or equal to the number of owners
    const E_INVALID_THRESHOLD: u64 = 1;

    /// Must provide the multisig address, deriving is not currently implemented
    const E_DERIVE_MULTISIG_ADDRESS_NOT_IMPLEMENTED: u64 = 5;

    /// Ed25519 key type
    const KEY_TYPE_ED25519: u8 = 0;

    fun init_module(contract: &signer) {
        initialize_registry(contract)
    }

    /// Tracks object addresses matched to each multisig address
    ///
    /// We have to do this, because we don't necessarily have the signers to setup the full multisig
    struct MultisigRegistry has key {
        registry: table::Table<address, address>
    }

    fun initialize_registry(contract: &signer) {
        move_to(contract, MultisigRegistry { registry: table::new() })
    }

    #[resource_group = object::ObjectGroup]
    /// Manages a multisig for an account
    ///
    /// TODO: put these on an object
    struct MultisigManager has key {
        /// Manages the signer
        extend_ref: object::ExtendRef,
        /// Can only be deleted by the owner
        delete_ref: object::DeleteRef,
        config: MultisigConfig,
        queue: MultisigQueue
    }

    // -- Main API -- //
    entry fun register_multied25519_manager(
        caller: &signer,
        addr: Option<address>,
        signatures_required: u8,
        public_keys: vector<vector<u8>>
    ) acquires MultisigManager, MultisigRegistry {
        // We're going to get the signer's address from the public key, public key must match
        let caller_addr = signer::address_of(caller);
        let caller_public_key = public_keys[0];
        let caller_auth_key = bcs::to_bytes(&caller_addr);
        let derived_auth_key = derive_ed25519_auth_key(caller_public_key);

        assert!(public_keys.length() >= 2, 123);

        assert!(derived_auth_key == caller_auth_key, 6);

        // Now, we need to validate it's one of the public keys
        assert!(public_keys.contains(&caller_public_key), 7);

        // Now, we can derive the address, if one wasn't provided
        let multisig_auth_key =
            derive_multied25519_auth_key(public_keys, signatures_required);

        let multisig_addr =
            if (addr.is_some()) {
                // Need to verify if the account was already rotated to this new auth key
                let multisig_addr = addr.destroy_some();
                let auth_key = account::get_authentication_key(multisig_addr);
                assert!(auth_key == multisig_auth_key, 8);
                multisig_addr
            } else {
                // Otherwise, we can just derive directly
                from_bcs::to_address(multisig_auth_key)
            };

        // Now, we can create the owners
        let owners = public_keys.map(|key| { owner::new_ed25519_owner(key) });

        // Check if the object exists, and if it does, just update it
        let is_registered = MultisigRegistry[@mm_addr].registry.contains(multisig_addr);

        if (!is_registered) {

            // Put the multisig manager in the caller's account via an object
            let const_ref = object::create_object(multisig_addr);
            let obj_signer = object::generate_signer(&const_ref);
            let extend_ref = object::generate_extend_ref(&const_ref);
            let delete_ref = object::generate_delete_ref(&const_ref);
            let manager_addr = object::address_from_constructor_ref(&const_ref);

            MultisigRegistry[@mm_addr].registry.upsert(multisig_addr, manager_addr);

            // Ensure this is soulbound to the multisig account
            let transfer_ref = object::generate_transfer_ref(&const_ref);
            object::disable_ungated_transfer(&transfer_ref);
            let config =
                config::new_ed25519_config(
                    multisig_addr, signatures_required, owners
                );
            move_to(
                &obj_signer,
                MultisigManager {
                    extend_ref,
                    delete_ref,
                    queue: queue::new_multisig_queue(),
                    config
                }
            );

            events::register(multisig_addr, manager_addr, config);
        } else {
            let manager_addr = multisig_manager_addr(multisig_addr);
            let manager_config = &mut multisig_manager_mut(multisig_addr).config;
            manager_config.update_multied25519(signatures_required, owners);
            events::update(multisig_addr, manager_addr, *manager_config);
        }
    }

    inline fun multisig_manager_addr(multisig_addr: address): address {
        let registry = &MultisigRegistry[@mm_addr].registry;
        assert!(registry.contains(multisig_addr), 123);
        *registry.borrow(multisig_addr)
    }

    inline fun multisig_manager(multisig_addr: address): &MultisigManager {
        let multisig_manager_addr = multisig_manager_addr(multisig_addr);
        assert!(exists<MultisigManager>(multisig_manager_addr), 9);
        &MultisigManager[multisig_manager_addr]
    }

    inline fun multisig_manager_mut(multisig_addr: address): &mut MultisigManager {
        let multisig_manager_addr = multisig_manager_addr(multisig_addr);
        assert!(exists<MultisigManager>(multisig_manager_addr), 9);
        &mut MultisigManager[multisig_manager_addr]
    }

    inline fun remove_manager(multisig_addr: address): MultisigManager {
        assert!(exists<MultisigManager>(multisig_addr), 9);
        move_from(multisig_addr)
    }

    // TODO: have to add public key authorization so people don't push crap
    entry fun submit_multisig_entry_function(
        _caller: &signer,
        multisig_addr: address,
        module_address: address,
        module_name: String,
        function_name: String,
        type_arguments: vector<vector<u8>>,
        arguments: vector<vector<u8>>,
        sequence_number: u64,
        expiration_timestamp_secs: u64,
        gas_unit_price: u64,
        max_gas_amount: u64,
        secondary_signers: vector<address>,
        fee_payer: Option<address>,
        key_type: u8,
        init_public_key: vector<u8>,
        init_signature: vector<u8>
    ) acquires MultisigManager, MultisigRegistry {
        let multisig_manager = multisig_manager_mut(multisig_addr);

        // Verify the signature with the public key
        assert!(key_type == 0, 10); // TODO: fix constant
        /*
        use aptos_framework::ed25519;
        let sig = ed25519::new_signature_from_bytes(signature);
        let key = ed25519::new_validated_public_key_from_bytes(public_key);
        assert!(key.is_some(), 11);
        let key = key.destroy_some();

        // TODO: Build message properly
        let message = vector[];
        assert!(ed25519::signature_verify_strict(&sig, &key, &message), 12);
        */

        // Verify that the public key is in the multisig
        assert!(
            multisig_manager.config.owners().any(|owner| {
                owner.public_key() == init_public_key
            }),
            13
        );

        // TODO: Make a hash here
        let sig = transaction::new_ed25519_signature(init_public_key, init_signature);
        let payload = transaction::new_entry_function_payload(module_address, module_name, function_name, type_arguments, arguments);
        let metadata = transaction::new_v1_transaction_metadata(multisig_addr, sequence_number, expiration_timestamp_secs, gas_unit_price, max_gas_amount, secondary_signers, fee_payer);
        let pending_transaction = transaction::new_v1_pending_transaction(payload, metadata, vector[sig]);
        multisig_manager.queue.insert_to_queue(pending_transaction);
    }

    entry fun add_signature_to_transaction(
        _caller: &signer,
        multisig_addr: address,
        num: u64,
        key_type: u8,
        public_key: vector<u8>,
        signature: vector<u8>
    ) acquires MultisigManager, MultisigRegistry {
        assert!(key_type == KEY_TYPE_ED25519, 23);
        let signature = transaction::new_ed25519_signature(public_key, signature);

        // Has to be one of the public keys in the multisig
        let manager = multisig_manager_mut(multisig_addr);
        assert!(
            manager.config.owners().any(|owner| {
                owner.public_key() == public_key
            }),
            12345
        );
        manager.queue.add_sig_to_queue_item(num, signature);
    }

    entry fun clear_invalid(_caller: &signer, multisig_addr: address) acquires MultisigManager, MultisigRegistry {
        multisig_manager_mut(multisig_addr).queue.clear_invalid(multisig_addr);
    }

    #[view]
    package fun view_transaction(
        multisig_addr: address, num: u64
    ): PendingTransaction acquires MultisigManager, MultisigRegistry {
        multisig_manager(multisig_addr).queue.transactions()[num]
    }

    #[view]
    package fun transaction_count(multisig_addr: address): u64 acquires MultisigManager, MultisigRegistry {
        multisig_manager(multisig_addr).queue.transactions().length()
    }

    #[view]
    package fun queued_transactions(
        multisig_addr: address
    ): vector<PendingTransaction> acquires MultisigManager, MultisigRegistry {
        multisig_manager(multisig_addr).queue.transactions()
    }

    #[view]
    package fun config(multisig_addr: address): MultisigConfig acquires MultisigManager, MultisigRegistry {
        multisig_manager(multisig_addr).config
    }

    /// Derives an ed25519 address from a public key
    inline fun derive_ed25519_auth_key(public_key: vector<u8>): vector<u8> {
        public_key.push_back(0x00);
        hash::sha3_256(public_key)
    }

    /// Derives an auth key from a multi-ed25519 multisig
    inline fun derive_multied25519_auth_key(
        public_keys: vector<vector<u8>>, threshold: u8
    ): vector<u8> {
        let bytes = vector[];
        public_keys.for_each(|key| bytes.append(key));
        bytes.push_back(threshold);
        bytes.push_back(1);
        hash::sha3_256(bytes)
    }
}
