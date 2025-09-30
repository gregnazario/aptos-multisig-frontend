/// Defines events for the package, none of these will be public
module mm_addr::events {
    use mm_addr::config::{MultisigConfig};
    use mm_addr::transaction::Signature;
    use aptos_framework::event;

    #[event]
    enum MultisigManagerEvent has store, copy, drop {
        Register {
            multisig_addr: address,
            manager_addr: address,
            config: MultisigConfig
        }
        Update {
            multisig_addr: address,
            manager_addr: address,
            config: MultisigConfig
        }
        AddTransaction {
            multisig_addr: address,
            manager_addr: address,
            hash: vector<u8>,
            signatures: vector<Signature>
        }
        AddSignature {
            multisig_addr: address,
            manager_addr: address,
            hash: vector<u8>,
            signatures: vector<Signature>
        }
        ClearTransactions {
            multisig_addr: address,
            manager_addr: address,
            hashes: vector<vector<u8>>
        }
    }

    package fun register(
        multisig_addr: address, 
        manager_addr: address, 
        config: MultisigConfig
    ) {
        event::emit(
            MultisigManagerEvent::Register { multisig_addr, manager_addr, config }
        )
    }

    package fun update(
        multisig_addr: address, 
        manager_addr: address, 
        config: MultisigConfig
    ) {
        event::emit(
            MultisigManagerEvent::Update { multisig_addr, manager_addr, config }
        )
    }

    package fun add_transaction(
        multisig_addr: address, 
        manager_addr: address, 
        hash: vector<u8>,
        signatures: vector<Signature>
    ) {
        event::emit(
            MultisigManagerEvent::AddTransaction { 
                multisig_addr, 
                manager_addr, 
                hash,
                signatures
            }
        )
    }

    package fun add_signature(
        multisig_addr: address, 
        manager_addr: address, 
        hash: vector<u8>,
        signatures: vector<Signature>
    ) {
        event::emit(
            MultisigManagerEvent::AddSignature { 
                multisig_addr, 
                manager_addr, 
                hash,
                signatures
            }
        )
    }

        package fun clear_transactions(
        multisig_addr: address, 
        manager_addr: address, 
        hashes: vector<vector<u8>>
    ) {
        event::emit(
            MultisigManagerEvent::ClearTransactions { 
                multisig_addr, 
                manager_addr, 
                hashes,
            }
        )
    }
}
