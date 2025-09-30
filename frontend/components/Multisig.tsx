import { useEffect, useState } from "react";
import { useWallet } from "@aptos-labs/wallet-adapter-react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
// Internal components
import { toast } from "@/components/ui/use-toast";
import { aptosClient } from "@/utils/aptosClient";
import { Button } from "@/components/ui/button";
import { getAccountAPTBalance } from "@/view-functions/getAccountBalance";
import { TransactionPayloadEntryFunction, AccountAddress, DEFAULT_MAX_GAS_AMOUNT, parseTypeTag, stringStructTag, TypeTagAddress, TypeTagStruct, TypeTagU64, TypeTagU8, TypeTagVector, U64, MultiEd25519PublicKey, Ed25519PublicKey, Ed25519PrivateKey } from "@aptos-labs/ts-sdk";

type QueuedTransaction = {
  __variant__: "V1", // TODO: add types
  hash: string,
  metadata: {
    __variant__: "V1", // TODO: add types
    expiration_timestamp_secs: string,
    gas_unit_price: string,
    max_gas_amount: string,
    fee_payer: {vec: string[]} // an option
    secondary_signers: string[],
    sender: string,
    sequence_number: string
  },
  payload: {
    __variant__: "EntryFunction",
    module_address: string,
    module_name: string,
    function_name: string,
    type_arguments: string[],
    arguments: string[],
  },
  signatures: {
    __variant__: "Ed25519",
    public_key: string,
    signature: string, 
  }[]
}

type MultisigConfig = {
  __variant__: "MultiEd25519",
  multisig_address: string,
  signatures_required: number,
  owners: Owner[],
}

type Owner = {
  __variant__: "Ed25519",
  public_key: string,
}


export function Multisig() {
  const { account, signAndSubmitTransaction, signTransaction } = useWallet();
  const queryClient = useQueryClient();

  // TODO: take in as input
  const multisigAddr = "0x10f46f1de034b33ac68c8ba5d5ccc7ef441e4eac90d82ce74270f316ce0fbc9f"; //TODO: Get from UI

  const {data: queuedTxns} = useQuery({
    queryKey: ["multisig-txns", multisigAddr],
    refetchInterval: 10_000,
    queryFn: async () => {
        if (account === null) {
          console.error("Account not available");
        }
        let output = await aptosClient().view<[QueuedTransaction[]]>({payload: {
          function: "0xb98022721f97da65950435386a5209be2fc54bed5f12fc8ea0a1c3d0c76f562f::multisig_manager::queued_transactions",
          typeArguments: [],
          functionArguments: [multisigAddr]
        }});

        return output[0]
    },
  });

  const {data: multisigConfig} = useQuery({
    queryKey: ["multisig-config", multisigAddr],
    refetchInterval: 10_000,
    queryFn: async () => {
        if (account === null) {
          console.error("Account not available");
        }
        let output = await aptosClient().view<[MultisigConfig]>({payload: {
          function: "0xb98022721f97da65950435386a5209be2fc54bed5f12fc8ea0a1c3d0c76f562f::multisig_manager::config",
          typeArguments: [],
          functionArguments: [multisigAddr]
        }});

        return output[0]
    },
  });

  const onClickButton = async () => {
    if (!account) {
      return;
    }

    try {
      const key = Ed25519PrivateKey.generate();
      const placeholderPublicKey = key.publicKey();
      const committedTransaction = await signAndSubmitTransaction(
        {
          data: {
            function: "0xb98022721f97da65950435386a5209be2fc54bed5f12fc8ea0a1c3d0c76f562f::multisig_manager::register_multied25519_manager",
            typeArguments: [],
            functionArguments: [
              null, 1, [account.publicKey.toUint8Array(), placeholderPublicKey.toUint8Array()] // TODO: Actually provide two real public keys
            ],
            abi: {
              typeParameters: [],
              parameters: [parseTypeTag("0x1::option::Option<address>"), new TypeTagU8(), new TypeTagVector(new TypeTagVector(new TypeTagU8()))]
            }
          }
        }
      );
      const executedTransaction = await aptosClient().waitForTransaction({
        transactionHash: committedTransaction.hash,
      });
      queryClient.invalidateQueries();
      toast({
        title: "Success",
        description: `Transaction succeeded, hash: ${executedTransaction.hash}`,
      });
    } catch (error) {
      console.error(error);
    }
  };

  const onClickButtonSubmitTransaction = async () => {
    if (!account) {
      return;
    }

    try {
      // First build the transaction and sign
      const multisigTxn = await aptosClient().transaction.build.simple({
        sender: multisigAddr,
        data: {
          function: "0x1::aptos_account::transfer",
          typeArguments: [],
          functionArguments: [AccountAddress.ONE, new U64(123)]
        },
        options: {
          expireTimestamp: 11759163294,
          //accountSequenceNumber: 2
        }
      });

      // TODO: Simulate
      const authenticator = (await signTransaction({ transactionOrPayload: multisigTxn})).authenticator
      if (!authenticator.isEd25519()) {
        throw new Error("Unsupported signature type");
      }
      const signature = authenticator.signature.toUint8Array();

      // Convert it to the storable version
      const entryFunctionPayload = multisigTxn.rawTransaction.payload as TransactionPayloadEntryFunction;
      const typeArgs = entryFunctionPayload.entryFunction.type_args.map((val)=> val.bcsToBytes())
      const args = entryFunctionPayload.entryFunction.args.map((val)=> val.bcsToBytes())
      const committedTransaction = await signAndSubmitTransaction(
        {
          data: {
            function: "0xb98022721f97da65950435386a5209be2fc54bed5f12fc8ea0a1c3d0c76f562f::multisig_manager::submit_multisig_entry_function",
            typeArguments: [],
            functionArguments: [
              multisigAddr,
              entryFunctionPayload.entryFunction.module_name.address,
              entryFunctionPayload.entryFunction.module_name.name.identifier,
              entryFunctionPayload.entryFunction.function_name.identifier,
              typeArgs,
              args,
              multisigTxn.rawTransaction.sequence_number, // sequence number
              multisigTxn.rawTransaction.expiration_timestamp_secs, // Expiration timestamp (purposely large)
              multisigTxn.rawTransaction.gas_unit_price, // gas unit price
              multisigTxn.rawTransaction.max_gas_amount,
              [], // secondary signers
              null, // fee payer
              0, // key type
              account.publicKey.toUint8Array(),
              signature
            ],
            abi: {
              typeParameters: [],
              parameters: [
                new TypeTagAddress(),
                new TypeTagAddress(),
                new TypeTagStruct(stringStructTag()),
                new TypeTagStruct(stringStructTag()),
                new TypeTagVector(new TypeTagVector(new TypeTagU8())),
                new TypeTagVector(new TypeTagVector(new TypeTagU8())),
                new TypeTagU64(),
                new TypeTagU64(),
                new TypeTagU64(),
                new TypeTagU64(),
                new TypeTagVector(new TypeTagAddress()),
                parseTypeTag("0x1::option::Option<address>"),
                new TypeTagU8(),
                new TypeTagVector(new TypeTagU8()),
                new TypeTagVector(new TypeTagU8()),
              ]
            }
          }
        }
      );
      const executedTransaction = await aptosClient().waitForTransaction({
        transactionHash: committedTransaction.hash,
      });
      queryClient.invalidateQueries();
      toast({
        title: "Success",
        description: `Transaction succeeded, hash: ${executedTransaction.hash}`,
      });
    } catch (error) {
      console.error(error);
    }
  };

  const onClickSubmitOnChainTxn = async () => {
    if (!queuedTxns || queuedTxns.length == 0) {
      return;
    }

    let queuedTxn = queuedTxns[0];
    let payload = queuedTxn.payload;
    let metadata = queuedTxn.metadata;



    try {
      // First build the transaction and sign
      const multisigTxn = await aptosClient().transaction.build.simple({
        sender: metadata.sender,
        data: {
          function: `${payload.module_address}::${payload.module_name}::${payload.function_name}`,
          typeArguments: [], // TODO: Handle type arguments
          functionArguments: payload.arguments, // Deserialize arguments, then reserialize
          // Cheat the ABI to not convert
        },
        options: {
          expireTimestamp: parseInt(metadata.expiration_timestamp_secs), // TODO: need to be able to manage larger numbers
          gasUnitPrice: parseInt(metadata.gas_unit_price),
          maxGasAmount: parseInt(metadata.max_gas_amount),
          accountSequenceNumber: BigInt(metadata.sequence_number)
        }
      });

      // Make a combined public key
      const combinedPublicKey = new MultiEd25519PublicKey({publicKeys: multisigConfig?.owners.map((owner) => new Ed25519PublicKey(owner.public_key)) ?? [], threshold: multisigConfig?.signatures_required ?? 0});

      const response = await aptosClient().transaction.simulate.simple({transaction: multisigTxn, signerPublicKey: combinedPublicKey})
      
      console.log("OUT: ", response);

      queryClient.invalidateQueries();
      toast({
        title: "Success",
        description: `Transaction submitted.  Status: ${response[0].vm_status}, hash: ${response[0].hash} || ${JSON.stringify(response[0])}`,
      
      });
    } catch (error) {
      console.error(error);
    }
  };


  // TODO: make a table
  return (
    <div className="flex flex-col gap-6">
      <Button
        disabled={!account}
        onClick={onClickButton}
      >
        Register new Multisig
      </Button>
      <Button
        disabled={!account}
        onClick={onClickButtonSubmitTransaction}
      >
        Submit a transaction
      </Button>
      <Button
        disabled={!account}
        onClick={onClickSubmitOnChainTxn}
      >
        Execute onchain transaction
      </Button>

      {queuedTxns?.map((txn, i) => {
        return `TXN: ${i} SEQ NO: ${txn.metadata.sequence_number} Function: ${txn.payload.module_address}::${txn.payload.module_name}::${txn.payload.function_name}`
      })}

    </div>
  );
}
