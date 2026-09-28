# ETH / ERC20 Forwarder

A minimal Ethereum contract that forwards every ETH and ERC20 it receives to an admin-controlled `destination` address.

- **ETH** is forwarded automatically in the same transaction it arrives in. If forwarding fails, the whole deposit reverts, so ETH never gets stuck.
- **ERC20** transfers do not notify the receiving contract, so tokens wait in the contract until someone calls `flushToken(token)`. Flushing is permissionless: funds can only ever go to `destination`. Non-standard tokens such as USDT are supported via OpenZeppelin `SafeERC20`.
- **Admin**: only the owner can call `setDestination`. Ownership transfer is two-step (`transferOwnership` → `acceptOwnership`). `renounceOwnership` is disabled so the destination can never be frozen by accident.

## Contract interface

| Function | Who | Description |
|---|---|---|
| `receive()` | anyone | Plain ETH transfers are forwarded to `destination` |
| `flushToken(address token)` | anyone | Sends the contract's full balance of `token` to `destination` |
| `flushTokens(address[] tokens)` | anyone | Batch version of `flushToken` |
| `flushETH()` | anyone | Sweeps ETH that arrived without triggering `receive()` (e.g. sent before deployment, `SELFDESTRUCT`) |
| `setDestination(address)` | owner | Changes the destination (cannot be zero or the contract itself) |
| `destination()` / `owner()` | view | Current settings |

| Event | Emitted when |
|---|---|
| `ETHForwarded(from, to, amount)` | ETH is forwarded (`receive` or `flushETH`) |
| `TokenForwarded(token, to, amount)` | An ERC20 is flushed |
| `DestinationChanged(previous, new)` | Destination is set or changed |

## Project layout

| Path | Purpose |
|---|---|
| `src/Forwarder.sol` | The contract |
| `test/Forwarder.t.sol` | Foundry tests |
| `script/Deploy.s.sol` | Foundry deployment script |
| `deploy.sh` | One-command mainnet deploy: validates config → runs tests → shows cost and addresses → asks for `yes` → deploys and verifies on Etherscan → reads back on-chain state |
| `.env.example` | Configuration template |

## Development

Requires [Foundry](https://book.getfoundry.sh/getting-started/installation).

```bash
git clone --recurse-submodules <repo-url>
cd eth-forwarder
forge build
forge test
```

## Deploying to mainnet

### 1. Prerequisites
- A **deployer wallet** holding ~0.01 ETH for gas
- An **OWNER** address — ideally a hardware wallet or Safe multisig, not the deployer wallet
- A **DESTINATION** address
- A mainnet **RPC URL** (e.g. [Alchemy](https://alchemy.com) or [Infura](https://infura.io))
- An **Etherscan API key** ([etherscan.io/myapikey](https://etherscan.io/myapikey))

### 2. Import the deployer key (once)
```bash
cast wallet import deployer --interactive
```
The key is stored encrypted in `~/.foundry/keystores/deployer`, never in this repo.

### 3. Configure
```bash
cp .env.example .env
```
Fill in the values in `.env`.

### 4. Deploy
```bash
./deploy.sh
```
You will be asked for the keystore password twice (once to read the address, once to sign). Check OWNER and DESTINATION carefully, then type `yes`.

## After deployment

Replace `$FWD` with the deployed address.

Flush a token (e.g. USDT) to the destination:
```bash
cast send $FWD "flushToken(address)" 0xdAC17F958D2ee523a2206206994597C13D831ec7 --account deployer --rpc-url $MAINNET_RPC_URL
```
Or on Etherscan: Contract → Write Contract → Connect wallet → `flushToken`.

Change the destination: call `setDestination` from the OWNER wallet (via Etherscan, or as a Safe transaction if OWNER is a Safe).

Read the current destination:
```bash
cast call $FWD "destination()(address)" --rpc-url $MAINNET_RPC_URL
```

## Notes
- The contract is not upgradeable. Whoever controls OWNER controls where future funds go.
- A few legacy contracts send ETH with only a 2300 gas stipend; such transfers will revert back to the sender (no funds lost). Regular wallets and exchange withdrawals are unaffected.
- This contract has not been audited by a third party.

## License

MIT
