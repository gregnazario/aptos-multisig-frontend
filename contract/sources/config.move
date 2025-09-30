/// Package defines the config, no functions here will be public, only package level
module mm_addr::config {
    use mm_addr::owner::Owner;

    /// Invalid key type, must match an existing type
    const E_INVALID_KEY_TYPE: u64 = 4;

    /// Ed25519 key type
    const KEY_TYPE_ED25519: u8 = 0;

    /// Configuration for a Multisig
    enum MultisigConfig has store, copy, drop {
        /// Legacy off-chain multisig for Aptos
        MultiEd25519 {
            // TODO: Do I need a bitmap?
            /// Address of the multisig account
            multisig_address: address,
            /// Threshold, must be 0 < threshold <= owners.len()
            signatures_required: u8,
            /// List of owners
            owners: vector<Owner>
        }
    }

    /// Creates a new Legacy MultiEd25519 config
    package fun new_ed25519_config(
        multisig_address: address, signatures_required: u8, owners: vector<Owner>
    ): MultisigConfig {
        MultisigConfig::MultiEd25519 { multisig_address, signatures_required, owners }
    }

    package fun signatures_required(self: &MultisigConfig): u8 {
        self.signatures_required
    }
    
    /// Returns the owners of the multisig config
    package fun owners(self: &MultisigConfig): vector<Owner> {
        self.owners
    }

    package fun update_multied25519(self: &mut MultisigConfig, signatures_required: u8, owners: vector<Owner>) {
        self.signatures_required = signatures_required;
        self.owners = owners;
    }
}
