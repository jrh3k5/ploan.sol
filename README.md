# Ploan

A tool used to loan someone (at 0% interest) and track the repayment of the loan.

Published contracts:

* Base Sepolia (v0.7.0)
  * Proxy contract: [0xEE69dBb8eE67D79Fa6C7fBf86D6dc51eaecb76d4](https://sepolia.basescan.org/address/0xEE69dBb8eE67D79Fa6C7fBf86D6dc51eaecb76d4)
  * Implementation contract: [0x86368C5e8804C1128fc3BD9500B8fE75564bf518](https://sepolia.basescan.org/address/0x86368C5e8804C1128fc3BD9500B8fE75564bf518)

## Development

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

## Pausing the Contract

The Ploan contract includes a pausable mechanism for emergency stops. When paused, most state-changing functions cannot be called.

### How to Pause/Unpause

- To pause the contract, call the `pause()` function.
- To unpause the contract, call the `unpause()` function.

> **Note:** In production, access to these functions should be restricted to an admin or owner account for security.

### Effects of Pausing

- While paused, actions such as proposing, executing, repaying, or deleting loans are disabled.
- Read-only/view functions are not affected and can still be called.

### Managing the Pauser Allowlist

Only addresses on the "pauser allowlist" can pause or unpause the contract. The deployer is automatically added as the first pauser. Any existing pauser can add or remove other pausers.

#### Add a Pauser

```solidity
// Add a new pauser (must be called by an existing pauser)
ploan.addPauser(newPauserAddress);
```

#### Remove a Pauser

```solidity
// Remove a pauser (must be called by an existing pauser)
ploan.removePauser(pauserAddress);
```

#### Check if an Address is a Pauser

```solidity
// Check if an address is a pauser
bool isPauser = ploan.isPauser(addressToCheck);
```

### Event Emissions

Whenever a pauser is added or removed, the contract emits an event. This allows off-chain services and UIs to track changes to the allowlists for auditability and transparency.

#### Emitted Events

- **Pauser changes:**
  - `PauserAllowlistModified(address indexed pauser, bool indexed allowed)`
    - Emitted when a pauser is added (`allowed = true`) or removed (`allowed = false`).
    - `pauser`: The address added or removed as a pauser.
    - `allowed`: `true` if added, `false` if removed.

---

## Managing the EntryPoint Allowlist (ERC-4337 Meta-Transaction Support)

### Why the EntryPoint Allowlist Exists

The Ploan contract supports ERC-4337 meta-transactions, allowing users to interact with the contract via smart contract wallets and bundlers. To ensure security, only approved EntryPoint contracts are allowed to submit meta-transactions to Ploan. This prevents unauthorized contracts from impersonating users or bypassing access control.

- **Meta-transaction security:** Only EntryPoints on the allowlist can relay user operations.
- **Access control:** Prevents malicious or unapproved contracts from acting as EntryPoints.
- **Governance:** The allowlist can be managed by trusted roles (EntryPoint managers), which are themselves managed by pausers.

### Managing EntryPoints

Only addresses on the EntryPoint allowlist can act as valid ERC-4337 EntryPoints for meta-transactions.

#### Add an EntryPoint

```solidity
// Add a new EntryPoint (must be called by an EntryPoint manager)
ploan.addEntryPoint(entryPointAddress);
```

#### Remove an EntryPoint

```solidity
// Remove an EntryPoint (must be called by an EntryPoint manager)
ploan.removeEntryPoint(entryPointAddress);
```

### Managing EntryPoint Managers

EntryPoint managers are addresses allowed to add or remove EntryPoints. Only pausers can add or remove EntryPoint managers.

#### Add an EntryPoint Manager

```solidity
// Add a new EntryPoint manager (must be called by a pauser)
ploan.addEntryPointManager(managerAddress);
```

#### Remove an EntryPoint Manager

```solidity
// Remove an EntryPoint manager (must be called by a pauser)
ploan.removeEntryPointManager(managerAddress);
```

### Event Emissions

Whenever an EntryPoint or EntryPoint manager is added or removed, the contract emits an event. This allows off-chain services and UIs to track changes to the allowlists for auditability and transparency.

#### Emitted Events

- **EntryPoint manager changes:**
  - `EntryPointManagerModified(address indexed manager, bool indexed allowed)`
    - Emitted when an EntryPoint manager is added (`allowed = true`) or removed (`allowed = false`).
    - `manager`: The address added or removed as an EntryPoint manager.
    - `allowed`: `true` if added, `false` if removed.

