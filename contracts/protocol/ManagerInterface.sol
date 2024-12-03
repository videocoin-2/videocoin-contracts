// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title Stream Manager Smart Contract Interface
 * @notice Interface for the Stream Manager to avoid infinite recursive includes.
 */
interface ManagerInterface {
    /**
     * @notice Can query whether a client can refund the coins from a stream contract.
     * @param streamId ID of the stream to query.
     * @return True if the stream is refundable, false otherwise.
     */
    function refundAllowed(uint256 streamId) external view returns (bool);

    /**
     * @notice Query whether a certain address is a validator.
     * @param v Address of the validator to query.
     * @return True if the address is a validator, false otherwise.
     */
    function isValidator(address v) external view returns (bool);

    /**
     * @notice Query the contract version.
     * @return The version string of the contract.
     */
    function getVersion() external view returns (string memory);

    /**
     * @notice Query the service share percentage.
     * @return The service share percentage as a uint256.
     */
    function getServiceSharePercent() external view returns (uint256);
}
