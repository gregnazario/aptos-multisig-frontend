module mm_addr::owner {
    /// Invalid key type, must match an existing type
    const E_INVALID_KEY_TYPE: u64 = 4;

    // Note that, this is essentially putting on-chain data for the off-chain multisig, we may put
    // extra information about the address of the owner.
    enum Owner has store, copy, drop {
        Ed25519 {
            public_key: vector<u8>
        }
    }

    package fun new_ed25519_owner(public_key: vector<u8>): Owner {
        Owner::Ed25519 { public_key }
    }

    package fun public_key(self: &Owner): vector<u8> {
        match(self) {
            Owner::Ed25519 { public_key } => { *public_key }
        }
    }

    fun new_owner(type: u8, public_key: vector<u8>): Owner {
        if (type == 0) {
            Owner::Ed25519 { public_key }
        } else {
            abort E_INVALID_KEY_TYPE
        }
    }
}
