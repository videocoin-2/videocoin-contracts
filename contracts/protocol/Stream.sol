// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title Stream Contract
 * @dev Represents a stream for AI workloads. Integrates ERC-20 token payments.
 */
contract Stream {
    address public manager;
    uint256 public id;
    address public client;
    bool public ended;

    IERC20 public paymentToken;

    mapping(uint256 => bool) public isChunk;
    mapping(uint256 => uint256[]) public wattages;
    uint256[] private _inChunkIds;

    mapping(uint256 => OutStream) public outStreams;
    uint256[] private _profiles;

    struct Proof {
        address miner;
        uint256 outputChunkId;
        uint256 proof;
    }

    struct ChunkProofQueue {
        Proof[] proofs;
        uint256 head;
        address validator;
    }

    struct OutStream {
        bool required;
        uint256 index;
        uint256 validatedChunks;
        mapping(uint256 => ChunkProofQueue) proofQueues;
    }

    event ChunkProofSubmitted(uint256 indexed chunkId, uint256 indexed profile, uint256 indexed idx);
    event ChunkProofValidated(uint256 indexed profile, uint256 indexed chunkId);
    event ChunkProofScrapped(uint256 indexed profile, uint256 indexed chunkId, uint256 indexed idx);

    constructor(
        uint256 _id,
        address _client,
        uint256[] memory profiles,
        IERC20 _paymentToken
    ) {
        require(_client != address(0), "Invalid client address");

        id = _id;
        client = _client;
        paymentToken = _paymentToken;
        manager = msg.sender;

        _profiles = profiles;
        for (uint256 i = 0; i < _profiles.length; i++) {
            uint256 profile = _profiles[i];
            outStreams[profile].required = true; // Directly access the storage
            outStreams[profile].index = i;
        }
    }

    function addInputChunkId(uint256 chunkId, uint256[] memory wattage) public onlyManager {
        require(!isChunk[chunkId] && !ended, "Invalid chunk or stream ended");

        isChunk[chunkId] = true;
        wattages[chunkId] = wattage;
        _inChunkIds.push(chunkId);
    }

    function endStream() public onlyManager {
        require(!ended, "Stream already ended");
        ended = true;
    }

    function submitProof(
        uint256 profile,
        uint256 chunkId,
        uint256 proof,
        uint256 outChunkId
    ) public {
        ChunkProofQueue storage proofQueue = outStreams[profile].proofQueues[chunkId];
        require(isChunk[chunkId] && proofQueue.validator == address(0), "Invalid chunk or already validated");
        require(outStreams[profile].required, "Profile not required");

        proofQueue.proofs.push(Proof(msg.sender, outChunkId, proof));
        emit ChunkProofSubmitted(chunkId, profile, proofQueue.proofs.length - 1);
    }

    function validateProof(uint256 profile, uint256 chunkId) public onlyValidator {
        OutStream storage outStream = outStreams[profile];
        require(outStream.required, "Profile not required");

        ChunkProofQueue storage proofQueue = outStream.proofQueues[chunkId];
        require(isChunk[chunkId] && proofQueue.validator == address(0), "Invalid chunk or already validated");
        require(proofQueue.head < proofQueue.proofs.length, "No proofs available");

        Proof storage proof = proofQueue.proofs[proofQueue.head];
        uint256 minerAmount = wattages[chunkId][outStream.index];
        uint256 serviceAmount = (minerAmount * Manager(manager).getServiceSharePercent()) / 100;
        minerAmount -= serviceAmount;

        require(paymentToken.transfer(proof.miner, minerAmount), "Miner payment failed");
        require(paymentToken.transfer(manager, serviceAmount), "Service fee payment failed");

        proofQueue.validator = msg.sender;
        outStream.validatedChunks++;

        emit ChunkProofValidated(profile, chunkId);
    }

    function scrapProof(uint256 profile, uint256 chunkId) public onlyValidator {
        ChunkProofQueue storage proofQueue = outStreams[profile].proofQueues[chunkId];
        require(isChunk[chunkId] && proofQueue.validator == address(0), "Invalid chunk or already validated");
        require(proofQueue.head + 1 <= proofQueue.proofs.length, "No proofs to scrap");

        proofQueue.head++;
        emit ChunkProofScrapped(profile, chunkId, proofQueue.head - 1);
    }

    function isTranscodingDone() public view returns (bool) {
        for (uint256 i = 0; i < _profiles.length; i++) {
            if (!isProfileTranscoded(_profiles[i])) {
                return false;
            }
        }
        return true;
    }

    function isProfileTranscoded(uint256 profile) public view returns (bool) {
        OutStream storage outStream = outStreams[profile];
        require(outStream.required, "Profile not required");
        return outStream.validatedChunks == _inChunkIds.length;
    }

    modifier onlyValidator() {
        require(Manager(manager).isValidator(msg.sender), "Not a validator");
        _;
    }

    modifier onlyManager() {
        require(msg.sender == manager, "Not a manager");
        _;
    }
}

interface Manager {
    function getServiceSharePercent() external view returns (uint256);
    function isValidator(address account) external view returns (bool);
}
