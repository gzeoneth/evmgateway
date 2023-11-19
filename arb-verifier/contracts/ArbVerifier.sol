//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
import {StateProof, EVMProofHelper} from '@ensdomains/evm-verifier/contracts/EVMProofHelper.sol';
import {IEVMVerifier} from '@ensdomains/evm-verifier/contracts/IEVMVerifier.sol';
import {Node, IRollupCore} from '@arbitrum/nitro-contracts/src/rollup/IRollupCore.sol';
import {RLPReader} from '@eth-optimism/contracts-bedrock/src/libraries/rlp/RLPReader.sol';

struct ArbWitnessData {
    bytes32 version;
    bytes32 sendRoot;
    bytes32 blockHash;
    uint64 nodeIndex;
    bytes rlpEncodedBlock;
}

contract ArbVerifier is IEVMVerifier {
    IRollupCore public immutable rollup;
    string[] _gatewayURLs;

    constructor(IRollupCore _rollupAddress, string[] memory _urls) {
        rollup = _rollupAddress;
        _gatewayURLs = _urls;
    }

    /*
     * Retrieves an array of gateway URLs used by the contract.
     * @returns {string[]} An array containing the gateway URLs.
     *     */
    function gatewayURLs() external view returns (string[] memory) {
        return _gatewayURLs;
    }

    /*
     * Retrieves storage values from the specified target address
     *
     * @param {address} target - The target address from which storage values are to be retrieved.
     * @param {bytes32[]} commands - An array of storage keys (commands) to query.
     * @param {bytes[]} constants - An array of constant values corresponding to the storage keys.
     * @param {bytes} proof - The proof data containing Arbitrum witness data and state proof.
     */
    function getStorageValues(
        address target,
        bytes32[] memory commands,
        bytes[] memory constants,
        bytes memory proof
    ) external view returns (bytes[] memory values) {
        (ArbWitnessData memory arbData, StateProof memory stateProof) = abi
            .decode(proof, (ArbWitnessData, StateProof));

        //The confirm data is the keccak256 hash of the block hash and the send root. It is used to verify that the block hash is correct.
        bytes32 confirmData = keccak256(
            abi.encodePacked(arbData.blockHash, arbData.sendRoot)
        );
        //Get the node from the rollup contract
        Node memory rblock = rollup.getNode(arbData.nodeIndex);

        //Verify that the block hash is correct
        require(rblock.confirmData == confirmData, 'confirmData mismatch');
        //Verifiy that the block that is being proven is the same as the block that was passed in
        require(
            arbData.blockHash == keccak256(arbData.rlpEncodedBlock),
            'blockHash encodedBlockArray mismatch'
        );
        //Now that we know that the block is valid, we can get the state root from the block.
        bytes32 stateRoot = decodeBlock(arbData.rlpEncodedBlock);

        values = EVMProofHelper.getStorageValues(
            target,
            commands,
            constants,
            stateRoot,
            stateProof
        );
    }

    /*
     * Decodes a block by extracting and converting the bytes32 value from the RLP-encoded block information.
     *
     * @param {bytes} rlpEncodedBlock - The RLP-encoded block information.
     * @returns {bytes32} The decoded bytes32 value extracted from the RLP-encoded block information.
     *
     * @notice This function is designed to be used internally within the contract.
     */
    function decodeBlock(
        bytes memory rlpEncdoedBlock
    ) internal pure returns (bytes32) {
        RLPReader.RLPItem[] memory i = RLPReader.readList(rlpEncdoedBlock);
        return bytes32(RLPReader.readBytes(i[3]));
    }
}