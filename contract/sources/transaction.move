module mm_addr::transaction {
    use aptos_std::option::Option;
    use aptos_std::string::String;

    /// Authenticates a specific transaction
    enum Signature has store, copy, drop {
        Ed25519 {
            public_key: vector<u8>,
            signature: vector<u8>
        }
    }

    package fun new_ed25519_signature(public_key: vector<u8>, signature: vector<u8>): Signature {
        Signature::Ed25519 {
            public_key,
            signature
        }
    }

    package fun public_key(self: &Signature): vector<u8> {
        self.public_key
    }

    /// A pending transaction put on-chain
    enum PendingTransaction has store, copy, drop {
        // V1 is simple, readability would be nice
        V1 {
            hash: vector<u8>,
            payload: TransactionPayload,
            metadata: TransactionMetadata,
            signatures: vector<Signature>
        }
    }

    package fun is_expired(self: &PendingTransaction, time_secs: u64): bool {
       match(self) {
            PendingTransaction::V1 { metadata,.. } => {
                match(metadata) {
                    TransactionMetadata::V1 { expiration_timestamp_secs,.. } => {
                        *expiration_timestamp_secs <= time_secs
                    }
                }
            }
       }                       
    }

    package fun is_out_of_date_seq_num(self: &PendingTransaction, seq_num: u64): bool {
       match(self) {
            PendingTransaction::V1 { metadata,.. } => {
                match(metadata) {
                    TransactionMetadata::V1 { sequence_number,.. } => {
                        *sequence_number < seq_num
                    }
                }
            }
        } 
    }

    package fun hash(self: &PendingTransaction): &vector<u8> {
        &self.hash
    }

    package fun payload_mut(self: &mut PendingTransaction): &mut TransactionPayload {
        &mut self.payload
    }
    package fun payload(self: &PendingTransaction): &TransactionPayload {
        &self.payload
    }

    package fun metadata_mut(self: &mut PendingTransaction): &mut TransactionMetadata {
       &mut self.metadata
    }
    package fun metadata(self: &PendingTransaction): &TransactionMetadata {
       &self.metadata
    }

    package fun signatures_mut(self: &mut PendingTransaction): &mut vector<Signature> {
        &mut self.signatures
    }
    package fun signatures(self: &mut PendingTransaction): &mut vector<Signature> {
        &mut self.signatures
    }

    package fun new_v1_pending_transaction(
        payload: TransactionPayload,
        metadata: TransactionMetadata,
        signatures: vector<Signature>
    ): PendingTransaction {
        // TODO: make a hash automatically
        let hash = vector[];
        V1 { hash, payload, metadata, signatures }
    }

    enum TransactionPayload has store, copy, drop {
        /// An encoded transaction is just the full transaction BCS encoded for signing
        EntryFunction {
            module_address: address,
            module_name: String,
            function_name: String,
            type_arguments: vector<vector<u8>>,
            arguments: vector<vector<u8>>
        }
        /*Script {
            code: vector<u8>,
            type_args: vector<vector<u8>>,
            args: vector<vector<u8>>
        }*/
        /*Encoded {
            transaction: vector<u8>
        }*/
    }

    package fun new_entry_function_payload(
        module_address: address,
        module_name: String,
        function_name: String,
        type_arguments: vector<vector<u8>>,
        arguments: vector<vector<u8>>
    ): TransactionPayload {
        TransactionPayload::EntryFunction {
            module_address,
            module_name,
            function_name,
            type_arguments,
            arguments
        }
    }

    enum TransactionMetadata has store, copy, drop {
        V1 {
            /// Sender, it may not be the same person who signed the transaction (to allow for multi-agent)
            sender: address,
            /// Sequence number of the transaction
            sequence_number: u64,
            expiration_timestamp_secs: u64,
            gas_unit_price: u64,
            max_gas_amount: u64,
            secondary_signers: vector<address>,
            fee_payer: Option<address>
        }
        /*Encoded {
            sequence_number: u64,
            expiration_timestamp_secs: u64
        },*/
    }


    package fun new_v1_transaction_metadata(
        sender: address,
        sequence_number: u64,
        expiration_timestamp_secs: u64,
        gas_unit_price: u64,
        max_gas_amount: u64,
        secondary_signers: vector<address>,
        fee_payer: Option<address>
    ): TransactionMetadata {
        TransactionMetadata::V1 {
            sender,
            sequence_number,
            expiration_timestamp_secs,
            gas_unit_price,
            max_gas_amount,
            secondary_signers,
            fee_payer
        }
    }


    package fun sender(self: &TransactionMetadata): address {
        self.sender
    }


}
