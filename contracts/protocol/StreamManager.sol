// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./Stream.sol";
import "./Escrow.sol";
import "./ManagerInterface.sol";

contract StreamManager is Ownable {
    struct StreamRequest {
        bool approved;
        bool refund;
        bool ended;
        address client;
        address stream;
        uint256[] profiles;
        uint256 streamId;
        string[] aiModels; // AI-specific workloads or models
        uint256[] computeRequirements; // Compute requirements like GPU, CPU needs
    }

    string public version;
    IERC20 public paymentToken;
    mapping(uint256 => StreamRequest) public requests;
    mapping(uint256 => string) public profiles;
    uint256 public serviceSharePercent;

    event StreamRequested(address indexed client, uint256 indexed streamId);
    event StreamApproved(uint256 indexed streamId);
    event StreamCreated(address indexed streamAddress, uint256 indexed streamId);
    event RefundAllowed(uint256 indexed streamId);
    event RefundRevoked(uint256 indexed streamId);
    event ServiceSharePercentUpdated(uint256 indexed percent);

    constructor(IERC20 _paymentToken) Ownable(msg.sender) {
        paymentToken = _paymentToken;
        serviceSharePercent = 20; // Default service share percent
        version = "1.0.0";
    }

    /**
     * @notice Request a new stream with specific AI workloads.
     * @param streamId Unique ID for the stream.
     * @param profileNames Array of profile name strings.
     * @param aiModels Array of AI workload descriptions.
     * @param computeRequirements Array of compute resource requirements.
     */
    function requestStream(
        uint256 streamId,
        string[] memory profileNames,
        string[] memory aiModels,
        uint256[] memory computeRequirements
    ) public returns (uint256) {
        require(requests[streamId].client == address(0), "Stream ID already exists");
        require(profileNames.length != 0, "Profiles required");
        require(aiModels.length == computeRequirements.length, "Mismatch in AI models and requirements");

        uint256[] memory profileHashes = new uint256[](profileNames.length);

        for (uint256 i = 0; i < profileNames.length; i++) {
            uint256 profileHash = uint256(keccak256(abi.encodePacked(profileNames[i])));
            profiles[profileHash] = profileNames[i];
            profileHashes[i] = profileHash;
        }

        requests[streamId] = StreamRequest({
            approved: false,
            refund: false,
            ended: false,
            client: msg.sender,
            stream: address(0),
            profiles: profileHashes,
            streamId: streamId,
            aiModels: aiModels,
            computeRequirements: computeRequirements
        });

        emit StreamRequested(msg.sender, streamId);

        return streamId;
    }

    /**
     * @notice Approve a stream request.
     * @param streamId ID of stream to approve.
     */
    function approveStream(uint256 streamId) public onlyOwner {
        StreamRequest storage request = requests[streamId];
        require(request.client != address(0), "Stream not found");
        request.approved = true;

        emit StreamApproved(streamId);
    }

    /**
     * @notice Create a stream after approval and deposit tokens.
     * @param streamId ID of the stream to create.
     * @param depositAmount Amount of tokens to deposit.
     */
    function createStream(uint256 streamId, uint256 depositAmount) public returns (address) {
        StreamRequest storage request = requests[streamId];
        require(request.approved, "Stream not approved");
        require(request.client == msg.sender, "Only client can create");
        require(request.stream == address(0), "Stream already created");

        require(paymentToken.transferFrom(msg.sender, address(this), depositAmount), "Token transfer failed");

        // Replace with your Stream contract instantiation logic
        address stream = address(new Stream(streamId, msg.sender, request.profiles, paymentToken));
        request.stream = stream;

        emit StreamCreated(stream, streamId);

        return stream;
    }

    /**
     * @notice Allow refund for a specific stream.
     * @param streamId ID of stream for refund.
     */
    function allowRefund(uint256 streamId) public onlyOwner {
        StreamRequest storage request = requests[streamId];
        require(request.client != address(0), "Stream not found");
        require(!request.refund, "Refund already allowed");

        request.refund = true;

        emit RefundAllowed(streamId);
    }

    /**
     * @notice Revoke refund permission for a stream.
     * @param streamId ID of stream to revoke refund.
     */
    function revokeRefund(uint256 streamId) public onlyOwner {
        StreamRequest storage request = requests[streamId];
        require(request.client != address(0), "Stream not found");
        require(request.refund, "Refund not allowed");

        request.refund = false;

        emit RefundRevoked(streamId);
    }

    /**
     * @notice Update service share percentage.
     * @param percent New service share percentage.
     */
    function setServiceSharePercent(uint256 percent) public onlyOwner {
        require(percent <= 100, "Percent must be <= 100");
        serviceSharePercent = percent;

        emit ServiceSharePercentUpdated(percent);
    }

    /**
     * @notice Query if a refund is allowed for a stream.
     * @param streamId ID of the stream.
     * @return True if refund is allowed, false otherwise.
     */
    function refundAllowed(uint256 streamId) public view returns (bool) {
        return requests[streamId].refund;
    }
}
