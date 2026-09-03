use std::str::FromStr;

use clap_v3::ArgMatches;
use colored::Colorize;
use eyre::eyre;
use solana_clap_v3_utils::keypair::signer_from_path;
use solana_sdk::{pubkey::Pubkey, signer::Signer, transaction::VersionedTransaction};
use squads_multisig::solana_rpc_client::nonblocking::rpc_client::RpcClient;
use squads_multisig::solana_rpc_client_api::{
    client_error::ErrorKind as ClientErrorKind,
    request::{RpcError, RpcResponseErrorData},
    response::RpcSimulateTransactionResult,
};

pub fn create_signer_from_path(
    keypair_path: String,
) -> Result<Box<dyn Signer>, Box<dyn std::error::Error>> {
    let mut wallet_manager = None;
    let matches = ArgMatches::default();

    signer_from_path(&matches, &keypair_path, "Keypair", &mut wallet_manager)
}

/// Resolves the `--program-id` flag, defaulting to the deployed program's own ID
/// so it tracks `declare_id!` instead of a literal that can drift from it.
pub fn resolve_program_id(program_id: Option<String>) -> Pubkey {
    let program_id =
        program_id.unwrap_or_else(|| squads_multisig::squads_multisig_program::ID.to_string());
    Pubkey::from_str(&program_id).expect("Invalid program ID")
}

pub async fn send_and_confirm_transaction(
    transaction: &VersionedTransaction,
    rpc_client: &RpcClient,
) -> eyre::Result<String> {
    // Try to send and confirm the transaction
    match rpc_client.send_and_confirm_transaction(transaction).await {
        Ok(signature) => {
            println!(
                "Transaction confirmed: {}\n\n",
                signature.to_string().green()
            );
            Ok(signature.to_string())
        }
        Err(err) => {
            if let ClientErrorKind::RpcError(RpcError::RpcResponseError {
                data:
                    RpcResponseErrorData::SendTransactionPreflightFailure(
                        RpcSimulateTransactionResult {
                            logs: Some(logs), ..
                        },
                    ),
                ..
            }) = &err.kind
            {
                println!("Simulation logs:\n\n{}\n", logs.join("\n").yellow());
            }

            Err(eyre!("Transaction failed: {}", err.to_string().red()))
        }
    }
}
