# EVM CCIP-Read Gateway
This repository implements a generic CCIP-Read gateway framework for fetching state proofs of data on other EVM chains.

## Usage

 1. Have your contract extend `EVMFetcher`.
 2. In a view/pure context, call `getStorageSlots` to fetch the value of slots from another contract (potentially on another chain). Calling `getStorageSlots` terminates execution and generates a callback to the same contract on a function you specify.
 3. In the callback function, use the information from the relevant slots as you see fit.

`getStorageSlots` is defined as follows:
```
function getStorageSlots(
    IEVMVerifier verifier,
    address addr,
    bytes32[][] memory paths,
    bytes4 callback,
    bytes memory callbackData) internal view;
```

Arguments:
 - `verifier` - A reference to a contract that verifies the returned storage proofs. Each EVM target chain has its own
     verifier contract.
 - `addr` - The address of the contract on the target chain that you wish to fetch storage data from.
 - `paths` - An array of paths to storage elements you want to fetch, documented below.
 - `callback` - The 4 byte selector of the function on this contract that should be called with verified storage data.
 - `callbackData` - Arbitrary extra data that will be passed to the callback function.

Each element in `paths` specifies a series of hashing operations to derive the final slot ID. See https://docs.soliditylang.org/en/v0.8.17/internals/layout_in_storage.html for details on how Solidity lays out storage variables.

In order to support additional functionality, special values are permitted for each element of a path. The MSB of the first element of a path is reserved to indicate if the value to be retrieved is fixed or dynamic length. If the MSB is 1,
the value is treated as a dynamic length Solidity type and retrieved as such. Each subsequent element of the path has an arbitrary value, MAGIC_SLOT subtracted from it; if the result is less than the number of previous entries, the value of the previous entry is substituted.

The examples below assume a Solidity contract with the following storage mapping:

```
contract Test {
        uint256 latest;
        string name;
        mapping(uint256=>uint256) highscores;
        mapping(uint256=>string) highscorers;
}
```

Examples:
 - `[[0x0]]` - Fetches a fixed-length storage proof for `latest`.
 - `[[0x8...1]]` - Fetches a dynamic-length storage proof for `name`.
 - `[[0x2, 0x0]]` - Fetches a fixed-length storage proof for `highscores[0]`.
 - `[[0x8...3, 0x0]]` - Fetches a dynamic-length storage proof for `highscorers[0]`.
 - `[[0x0], [0x2, MAGIC_SLOT], [0x8...3, MAGIC_SLOT]]` - Fetches fixed length storage proofs for `latest` and `highscores[latest]` and a dynamic-length storage proof for `highscorers[latest]`.

## Example

The example below fetches its own storage value `testUint` in the most byzantine possible manner.

```
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { EVMFetcher } from '@ensdomains/evm-verifier/contracts/EVMFetcher.sol';
import { IEVMVerifier } from '@ensdomains/evm-verifier/contracts/IEVMVerifier.sol';

contract TestTarget is EVMFetcher {
    IEVMVerifier verifier;      // Slot 0
    uint256 testUint;           // Slot 1

    constructor(IEVMVerifier _verifier) {
        verifier = _verifier;
        testUint = 42;
    }

    function getTestUint() public view returns(uint256) {
        bytes32[][] memory paths = new bytes32[][](1);
        paths[0] = new bytes32[](1);
        paths[0][0] = bytes32(uint256(1));

        getStorageSlots(verifier, address(this), paths, this.getSingleStorageSlotCallback.selector, "");
    }

    function getSingleStorageSlotCallback(bytes[] memory values, bytes memory) public pure returns(uint256) {
        return uint256(bytes32(values[0]));
    }
}
```

## Packages

This is a monorepo divided up into several packages:

### [evm-gateway](/evm-gateway/)
A framework for constructing generic CCIP-Read gateways targeting different EVM-compatible chains. This repository
implements all the functionality required to fetch and verify multiple storage slots from an EVM-compatible chain,
omitting only the L2-specific logic of determining a block to target, and verifying the root of the generated proof.

### [l1-gateway](/l1-gateway/)
An instantiation of `evm-gateway` that targets Ethereum L1 - that is, it implements a CCIP-Read gateway that generates
proofs of contract state on L1.

This may at first seem useless, but as the simplest possible practical EVM gateway implementation, it acts as an excellent
target for testing the entire framework end-to-end.

It may also prove useful for contracts that wish to trustlessly establish the content of storage variables of other contracts,
or historic values for storage variables of any contract.

### [evm-verifier](/evm-verifier/)
A Solidity library that verifies state proofs generated by an `evm-gateway` instance. This library implements all the
functionality required make CCIP-Read calls to an EVM gateway and verify the responses, except for verifying the root of the
proof. This library is intended to be used by libraries for specific EVM-compatible chains that implement the missing 
functionality.

### [l1-verifier](/l1-verifier/)
A complete Solidity library that facilitates sending CCIP-Read requests for L1 state, and verifying the responses.

This repository also contains the end-to-end tests for the entire stack.
