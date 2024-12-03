// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title Escrow
 * @dev Abstract contract for handling token-based escrows.
 */
abstract contract Escrow {
    address public client; // The client who initiated the stream.
    IERC20 public paymentToken; // The ERC-20 token used for payments.

    event Deposited(address indexed depositor, uint256 amount);
    event Refunded(address indexed client, uint256 amount);
    event PaymentTransferred(address indexed recipient, uint256 amount);

    /**
     * @notice Constructor.
     * @param _client Address of the client that requested the escrow.
     * @param _paymentToken Address of the ERC-20 token used for payments.
     */
    constructor(address _client, IERC20 _paymentToken) {
        require(_client != address(0), "Escrow: Invalid client address");
        require(address(_paymentToken) != address(0), "Escrow: Invalid token address");

        client = _client;
        paymentToken = _paymentToken;
    }

    /**
     * @notice Deposit tokens into the escrow.
     * @param amount Amount of tokens to deposit.
     */
    function deposit(uint256 amount) external {
        require(amount > 0, "Escrow: Deposit amount must be greater than zero");
        require(paymentToken.transferFrom(msg.sender, address(this), amount), "Escrow: Transfer failed");

        emit Deposited(msg.sender, amount);
    }

    /**
     * @notice Refund remaining tokens to the client.
     */
    function refund() external {
        require(refundAllowed(), "Escrow: Refund not allowed");

        uint256 balance = paymentToken.balanceOf(address(this));
        require(balance > 0, "Escrow: No funds to refund");

        require(paymentToken.transfer(client, balance), "Escrow: Refund transfer failed");

        emit Refunded(client, balance);
    }

    /**
     * @notice Transfer tokens to a specified recipient.
     * @param recipient Address of the recipient.
     * @param amount Amount of tokens to transfer.
     */
    function transferPayment(address recipient, uint256 amount) internal {
        require(recipient != address(0), "Escrow: Invalid recipient address");
        require(amount > 0, "Escrow: Transfer amount must be greater than zero");

        uint256 balance = paymentToken.balanceOf(address(this));
        require(balance >= amount, "Escrow: Insufficient funds");

        require(paymentToken.transfer(recipient, amount), "Escrow: Transfer failed");

        emit PaymentTransferred(recipient, amount);
    }

    /**
     * @notice Check if a refund is allowed.
     * @dev Must be implemented by derived contracts.
     * @return True if refund is allowed, otherwise false.
     */
    function refundAllowed() public view virtual returns (bool);
}
