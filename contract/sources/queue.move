module mm_addr::queue {
    use mm_addr::transaction::PendingTransaction;
    use mm_addr::events;
    use mm_addr::transaction::Signature;
    use aptos_framework::timestamp;
    use aptos_framework::account;

    /// A queue for transactions, right now it's a vector cause it's easy and short
    ///
    /// Could consider ordered map later
    enum MultisigQueue has store {
        V1 {
            transactions: vector<PendingTransaction>
        }
    }

    /// Creates a new MultisigQueue
    package fun new_multisig_queue(): MultisigQueue {
        MultisigQueue::V1 { transactions: vector[] }
    }

    /// Inserts in the the Multisig queue and already processed transaction
    package fun insert_to_queue(
        self: &mut MultisigQueue, txn: PendingTransaction
    ) {
        match(self) {
            MultisigQueue::V1 { transactions } => {
                let hash = *txn.hash();
                let signatures = *txn.signatures();
                let multisig_addr = txn.metadata().sender();
                transactions.push_back(txn);
                // TODO: later add manager addr?
                events::add_transaction(multisig_addr, @0x0, hash, signatures)
            }
        }
    }

    package fun add_sig_to_queue_item(
        self: &mut MultisigQueue, num: u64, signature: Signature
    ) {
        assert!(num < self.transactions.length(), 22);
        let txn = &mut self.transactions[num];
        let hash = *txn.hash();
        let multisig_addr = txn.metadata().sender();
        let signatures = txn.signatures_mut();
        assert!(!signatures.any(|sig| sig.public_key() == signature.public_key()), 22);
        signatures.push_back(signature);
        events::add_signature(multisig_addr, @0x0, hash, *signatures);
    }

    package fun clear_invalid(self: &mut MultisigQueue, multisig_addr: address) {
        let sequence_number = account::get_sequence_number(multisig_addr);
        let now = timestamp::now_seconds();
        let hashes = vector[];
        match(self) {
            MultisigQueue::V1 { transactions } => {
                let to_remove = vector[];
                let len = transactions.length();
                for (i in 0..len) {
                    let txn = &transactions[i];
                    
                    if (txn.is_expired(now)) {
                        to_remove.push_back(i);
                    } else if (txn.is_out_of_date_seq_num(sequence_number)) {
                        to_remove.push_back(i);
                    }
                };

                // Now, remove them in reverse order so that nothing messes up
                while (!to_remove.is_empty()) {
                    let remove_index = to_remove.pop_back();
                    let txn = transactions.remove(remove_index);
                    hashes.push_back(*txn.hash());
                }
            }
        };
        events::clear_transactions(multisig_addr, @0x0, hashes);
    }

    package fun transactions(self: &MultisigQueue): vector<PendingTransaction> {
        self.transactions
    }
}
