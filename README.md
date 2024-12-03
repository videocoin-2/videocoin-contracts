# VideoCoin-2 Smart Contracts


## Proposed Modifications in the protocol contracts

### Modifications for AI Workloads and ERC-20 Token Payments

To adapt the provided Solidity contracts (`StreamManager.sol`, `Stream.sol`, and `Escrow.sol`) for media compute workloads such as AI tasks, while enabling payments in ERC-20 tokens:

#### 1. **Incorporate ERC-20 Token Support**
   - Replace `msg.value` and native Ether payments with ERC-20 token transfers.
   - Use the ERC-20 `IERC20` interface for token interactions:
     ```solidity
     import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

     IERC20 public paymentToken; // ERC-20 token contract address
     ```
   - Initialize `paymentToken` in the constructor of `StreamManager`.
   - Replace Ether payments with token transfers using `transferFrom` and `approve`.

#### 2. **Add Token-Specific Escrow Logic**
   - Update `Escrow` contract to support token-based deposits and refunds.
     ```solidity
     function deposit(uint256 amount) external {
         require(paymentToken.transferFrom(msg.sender, address(this), amount), "Deposit failed");
         emit Deposited(amount);
     }

     function refund() public {
         require(refundAllowed(), "Refund not allowed");
         uint256 balance = paymentToken.balanceOf(address(this));
         require(paymentToken.transfer(client, balance), "Refund failed");
         emit Refunded(balance);
     }
     ```

#### 3. **Service Fees in Tokens**
   - Replace Ether-based service fees with token-based deductions in the `Stream` contract's `validateProof` function:
     ```solidity
     uint256 serviceAmount = minerAmount.mul(percent).div(100);
     minerAmount = minerAmount.sub(serviceAmount);

     require(paymentToken.transfer(miner, minerAmount), "Miner payment failed");
     require(paymentToken.transfer(manager, serviceAmount), "Service fee payment failed");
     ```

#### 4. **Modify Stream Initialization**
   - Update `StreamManager` to accept token-based deposits for creating streams:
     ```solidity
     function createStream(uint256 streamId, uint256 depositAmount) public returns (address) {
         StreamRequest storage request = requests[streamId];
         require(request.approved, "Stream not approved");
         require(request.client == msg.sender, "Only client can create");
         require(request.stream == address(0), "Stream already created");

         require(paymentToken.transferFrom(msg.sender, address(this), depositAmount), "Deposit failed");

         Stream stream = new Stream(streamId, msg.sender, request.profiles, paymentToken);
         request.stream = address(stream);

         emit StreamCreated(address(stream), streamId);
         return address(stream);
     }
     ```

#### 5. **Support for AI-Specific Workloads**
   - **Flexible Profiles**: Extend profiles to include AI model types, compute resources, and GPU requirements.
     ```solidity
     struct StreamRequest {
         bool approved;
         bool refund;
         bool ended;
         address client;
         address stream;
         uint256[] profiles;
         uint256 streamId;
         string[] aiModels; // AI models or workloads
         uint256[] computeRequirements; // Compute resource requirements (e.g., GPUs, CPUs)
     }
     ```
   - Update `StreamManager` to handle AI-specific parameters in the `requestStream` function.

#### 6. **Enhanced Refund Logic**
   - Support partial refunds based on incomplete work:
     ```solidity
     function partialRefund(uint256 streamId, uint256 refundAmount) public {
         StreamRequest storage request = requests[streamId];
         require(request.client == msg.sender, "Only client can request refund");
         require(paymentToken.transfer(request.client, refundAmount), "Partial refund failed");

         emit PartialRefund(streamId, refundAmount);
     }
     ```

#### 7. **Improved Governance for Validators and Publishers**
   - Introduce staking for validators and publishers to ensure accountability.
   - Validators must stake ERC-20 tokens to validate proofs, with penalties for invalid or fraudulent activity.

#### 8. **Event Enhancements**
   - Include AI-specific and token-specific data in events:
     ```solidity
     event AIWorkloadRequested(address indexed client, uint256 indexed streamId, string[] models, uint256[] computeRequirements);
     event ERC20PaymentReceived(address indexed payer, uint256 amount);
     ```

#### 9. **Version Upgrades**
   - Increment the version number to reflect the new functionality and ensure backward compatibility.

#### 10. **Testing and Security**
   - Conduct thorough testing for ERC-20 token transfers, especially handling `transferFrom` failures due to insufficient allowance or balance.
   - Add reentrancy guards to critical functions like deposits and refunds using `ReentrancyGuard`.

---

### Sample Changes in `StreamManager`

#### Constructor
```solidity
constructor(IERC20 _paymentToken) public {
    paymentToken = _paymentToken;
    serviceSharePercent = 20;
    version = "1.0.0";
    addPublisher(msg.sender);
}
```

#### ERC-20 Integration Example
```solidity
function fundStream(uint256 streamId, uint256 amount) public {
    require(paymentToken.transferFrom(msg.sender, address(this), amount), "Payment failed");
    emit ERC20PaymentReceived(msg.sender, amount);
}
```

---

By implementing these changes, the contracts can better support AI workloads and integrate seamlessly with ERC-20 token payments.