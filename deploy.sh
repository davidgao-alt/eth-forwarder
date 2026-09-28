#!/usr/bin/env bash
# Deploy Forwarder to Ethereum mainnet. Usage: ./deploy.sh
set -euo pipefail
cd "$(dirname "$0")"

for bin in forge cast jq; do
  command -v "$bin" >/dev/null || { echo "Missing dependency: $bin"; exit 1; }
done

[[ -f .env ]] || { echo "No .env found. Run: cp .env.example .env  and fill it in."; exit 1; }
set -a; source .env; set +a

for v in MAINNET_RPC_URL ETHERSCAN_API_KEY OWNER DESTINATION KEYSTORE_ACCOUNT; do
  [[ -n "${!v:-}" ]] || { echo "$v is not set in .env"; exit 1; }
done

OWNER=$(cast to-check-sum-address "$OWNER") || { echo "OWNER is not a valid address"; exit 1; }
DESTINATION=$(cast to-check-sum-address "$DESTINATION") || { echo "DESTINATION is not a valid address"; exit 1; }

CHAIN_ID=$(cast chain-id --rpc-url "$MAINNET_RPC_URL")
[[ "$CHAIN_ID" == "1" ]] || { echo "RPC is not Ethereum mainnet (chain id = $CHAIN_ID)"; exit 1; }

cast wallet list | grep -q "^$KEYSTORE_ACCOUNT" || {
  echo "Keystore account '$KEYSTORE_ACCOUNT' not found. Run: cast wallet import $KEYSTORE_ACCOUNT --interactive"; exit 1; }

echo "== Running tests =="
forge test

echo
echo "== Unlocking deployer wallet (enter keystore password) =="
DEPLOYER=$(cast wallet address --account "$KEYSTORE_ACCOUNT")
BALANCE=$(cast balance "$DEPLOYER" --ether --rpc-url "$MAINNET_RPC_URL")
GAS_PRICE=$(cast gas-price --rpc-url "$MAINNET_RPC_URL")
EST_COST=$(cast from-wei $((GAS_PRICE * 900000)))

cat <<INFO

============== Mainnet deployment ==============
Deployer          : $DEPLOYER
Deployer balance  : $BALANCE ETH
Gas price         : $(cast from-wei "$GAS_PRICE" gwei) gwei
Estimated cost    : ~$EST_COST ETH (assuming 900k gas; usually less)

OWNER (admin)     : $OWNER
DESTINATION       : $DESTINATION
================================================
INFO

if [[ "$OWNER" == "$DEPLOYER" ]]; then
  echo "WARNING: OWNER is the same as the deployer wallet. A hardware wallet or multisig is recommended."
fi

read -r -p "Are both addresses correct? Type 'yes' to deploy to mainnet: " ans
[[ "$ans" == "yes" ]] || { echo "Aborted."; exit 1; }

forge script script/Deploy.s.sol \
  --rpc-url "$MAINNET_RPC_URL" \
  --account "$KEYSTORE_ACCOUNT" \
  --sender "$DEPLOYER" \
  --broadcast \
  --verify

ADDR=$(jq -r '.transactions[] | select(.transactionType=="CREATE") | .contractAddress' \
  broadcast/Deploy.s.sol/1/run-latest.json | tail -1)
ADDR=$(cast to-check-sum-address "$ADDR")

echo
echo "== On-chain check =="
echo "Forwarder     : $ADDR"
echo "owner()       : $(cast call "$ADDR" 'owner()(address)' --rpc-url "$MAINNET_RPC_URL")"
echo "destination() : $(cast call "$ADDR" 'destination()(address)' --rpc-url "$MAINNET_RPC_URL")"
echo "Etherscan     : https://etherscan.io/address/$ADDR#code"
