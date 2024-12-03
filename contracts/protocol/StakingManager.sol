// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title DPoS Staking Manager for Transcoders and Delegators
 * @notice Staking manager using an ERC-20 token for staking operations.
 */
contract StakingManager is Ownable, AccessControl {
    IERC20 public stakingToken;

    enum TranscoderState { BONDING, BONDED, UNBONDED, UNBONDING, UNREGISTERED }

    struct Transcoder {
        uint256 total;
        uint256 timestamp;
        uint256 rewardRate;
        uint256 rewards;
        uint256 zone;
        uint256 capacity;
        Slash[] slashes;
        address[] delegators;
        bool jailed;
        uint256 effectiveMinSelfStake;
    }

    struct Delegator {
        mapping(address => uint256) bondedAmounts;
        mapping(address => uint256) slashCounters;
        mapping(uint256 => UnbondingRequest) unbondingRequests;
        uint256 pending;
        uint256 next;
        bool managed;
    }

    struct UnbondingRequest {
        address transcoder;
        uint256 timestamp;
        uint256 amount;
    }

    struct Slash {
        uint256 timestamp;
        uint256 rate;
    }

    uint256 public minDelegation;
    uint256 public minSelfStake;
    uint256 public transcoderApprovalPeriod;
    uint256 public unbondingPeriod;
    uint256 public slashRate;
    address public slashPoolAddress;

    mapping(address => Transcoder) public transcoders;
    mapping(address => Delegator) public delegators;
    address[] public transcodersArray;

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    event TranscoderRegistered(address indexed transcoder);
    event Delegated(address indexed transcoder, address indexed delegator, uint256 amount);
    event Slashed(address indexed transcoder, uint256 rate);
    event Jailed(address indexed transcoder);
    event Unjailed(address indexed transcoder);
    event UnbondingRequested(
        uint256 indexed unbondingID,
        address indexed delegator,
        address indexed transcoder,
        uint256 readiness,
        uint256 amount
    );
    event StakeWithdrawal(uint256 indexed unbondingID, address indexed delegator, address indexed transcoder, uint256 amount);
    event ManagerAdded(address indexed manager);
    event ManagerRemoved(address indexed manager);

  /**
  * @notice Constructor.
  * @param _minDelegation min delegation
  * @param _minSelfStake  min self stake
  * @param _transcoderApprovalPeriod transcoder approval period
  * @param _unbondingPeriod unbonding period
  * @param _slashRate rate by which stakes are slashed
  */
    constructor(
        address _stakingToken,
        uint256 _minDelegation,
        uint256 _minSelfStake,
        uint256 _transcoderApprovalPeriod,
        uint256 _unbondingPeriod,
        uint256 _slashRate,
        address _slashPoolAddress
    ) Ownable(msg.sender) {
        stakingToken = IERC20(_stakingToken);
        minDelegation = _minDelegation;
        minSelfStake = _minSelfStake;
        transcoderApprovalPeriod = _transcoderApprovalPeriod;
        unbondingPeriod = _unbondingPeriod;
        slashRate = _slashRate;
        slashPoolAddress = _slashPoolAddress;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER_ROLE, msg.sender);
    }

  function addManager(address v) public onlyOwner {
    _grantRole(MANAGER_ROLE, v);
    emit ManagerAdded(v);
  }

  function removeManager(address v) public onlyOwner {
    _revokeRole(MANAGER_ROLE, v);
    emit ManagerRemoved(v);
  }

  function isManager(address v) public view returns (bool) {
    return hasRole(MANAGER_ROLE, v);
  }

  modifier onlyManager() {
    require(isManager(msg.sender), "not a manager");
    _;
  }


  /**
  * @notice Setter for minimum self-stake, i.e. bonding treshold.
  * @dev
  * @param amount minimum self stake amount
  */
  function setSelfMinStake(uint256 amount) public onlyOwner() {
    require(amount > 0);

    minSelfStake = amount;
  }

  /**
  * @notice Setter for approval period
  * @dev
  * @param period aproval period in seconds
  */
  function setApprovalPeriod(uint256 period) public onlyOwner() {
    transcoderApprovalPeriod = period;
  }

  /**
  * @notice Setter for trancoder zone.
  * @dev
  * @param addr transcoder address
  * @param zone zone id
  */
  function setZone(address addr, uint256 zone) public onlyOwner() {
    Transcoder storage transcoder = transcoders[addr];
    require(transcoder.timestamp > 0, "Transcoder not registered");

    transcoder.zone = zone;
  }

  /**
  * @notice Setter for slash rate.
  * @param rate from 0 to 100
  */
  function setSlashRate(uint256 rate) public onlyOwner() {
    slashRate = rate;
  }

  /**
  * @notice Setter for slash pool address.
  * @dev Can be 0x0
  * @param addr new slash pool address
  */
  function setSlashFundAddress(address payable addr) public onlyOwner() {
    require(slashPoolAddress != addr, "Already set to this address");
    slashPoolAddress = addr;
  }

  /**
  * @notice Setter for trancoder capacity.
  * @dev
  * @param addr transcoder address
  * @param capacity transcoder capacity in uwatt
  */
  function setCapacity(address addr, uint256 capacity) public onlyOwner() {
    Transcoder storage transcoder = transcoders[addr];
    require(transcoder.timestamp > 0, "Transcoder not registered");

    transcoder.capacity = capacity;
  }

  /**
  * @notice Method to register as transcoder.
  * @dev rate parameter not used for now
  * @param rate Percentage of rewards that the transcoder will share with delegators
  */
  function registerTranscoder(uint256 rate) external {
    require(rate < 100, "Rate must be a percentage between 0 and 100");
    address addr = msg.sender;

    Transcoder storage transcoder = transcoders[addr];
    require(transcoder.timestamp == 0, "Transcoder already registered");

    transcoder.timestamp = block.timestamp;
    transcoder.rewardRate = rate;
    transcoder.effectiveMinSelfStake = minSelfStake;
    transcodersArray.push(addr);
    emit TranscoderRegistered(addr);
  }
    function _delegate(address transcoderAddr, address delegatorAddr, uint256 amount) internal {
        Transcoder storage transcoder = transcoders[transcoderAddr];
        Delegator storage delegator = delegators[delegatorAddr];

        require(transcoderAddr != address(0), "Invalid transcoder address");
        require(amount >= minDelegation, "Amount below minimum delegation");

        if (delegator.bondedAmounts[transcoderAddr] == 0) {
            transcoder.delegators.push(delegatorAddr);
            delegator.slashCounters[transcoderAddr] = transcoder.slashes.length;
        }

        applySlash(transcoderAddr, delegatorAddr);

        require(stakingToken.transferFrom(delegatorAddr, address(this), amount), "Token transfer failed");

        transcoder.total += amount;
        delegator.bondedAmounts[transcoderAddr] += amount;

        emit Delegated(transcoderAddr, delegatorAddr, amount);
    }

    function delegate(address transcoderAddr, uint256 amount) public {
        Delegator storage delegator = delegators[msg.sender];
        require(!delegator.managed, "Delegator is managed");
        _delegate(transcoderAddr, msg.sender, amount);
    }

    function delegateManaged(address transcoderAddr, address delegatorAddr, uint256 amount) public onlyRole(MANAGER_ROLE) {
        Delegator storage delegator = delegators[delegatorAddr];
        delegator.managed = true;
        _delegate(transcoderAddr, delegatorAddr, amount);
    }

  function isManaged(address delegatorAddr) public view returns(bool) {
    Delegator storage delegator   = delegators[delegatorAddr];
    return delegator.managed;
  }

  function _requestUnbonding(address transcoderAddr, address delegatorAddr, uint256 amount) internal returns(uint256) {
    require(transcoderAddr != address(0), "Can`t use address 0x0");

    Transcoder storage transcoder = transcoders[transcoderAddr];
    Delegator storage delegator   = delegators[delegatorAddr];

    applySlash(transcoderAddr, delegatorAddr); // slash so we can update amounts to check what if we can unbond
    require(amount <= delegator.bondedAmounts[transcoderAddr], "Not enough funds");

    // if transcoder withdraws from himself, and the total ammount is less than minSelfStake transcoder will enter
    // BONDING state. And this will allow to withdraw everything immediatly.
    // after this change it is still possible for transcoder to withdraw just enough to enter BONDING state
    // and then withdraw everything else immediatly.
    TranscoderState state = getTranscoderState(transcoderAddr);

    delegator.bondedAmounts[transcoderAddr] = delegator.bondedAmounts[transcoderAddr] - amount;
    transcoder.total = transcoder.total - amount;

    uint256 unbondingID = delegator.next;
    delegator.next = delegator.next + 1;

    // stake can be withdrawn immediatly if:
    // - this is a withdrawal from delegator
    // - transcoder is wasn't bonded yet - BONDING
    // - or it is alread UNBONDED (stake slashed)
    // in all other cases we need to wait for unbondingPeriod to give us to apply potential penalties
    // e.g. slashing
    if(state == TranscoderState.BONDING || state == TranscoderState.UNBONDED || transcoderAddr != delegatorAddr) {
      emit UnbondingRequested(unbondingID, delegatorAddr, transcoderAddr, block.timestamp, amount);
      delegator.unbondingRequests[unbondingID] = UnbondingRequest(transcoderAddr, block.timestamp - unbondingPeriod, amount);
      require(withdrawStake(unbondingID, delegatorAddr), "failed to withdraw stake");
    } else {
      emit UnbondingRequested(unbondingID, delegatorAddr, transcoderAddr, block.timestamp + unbondingPeriod, amount);
      delegator.unbondingRequests[unbondingID] = UnbondingRequest(transcoderAddr, block.timestamp, amount);
    }
    return unbondingID;
  }

  /**
  * @notice Delegator requests stake unbonding. Delegator has to wait for unbondingPeriod before calling withdrawStake() with the returned ID.
  * @dev Requests get approved immediately if tcoder`s state is BONDING or UNBONDED
  * @param transcoderAddr transcoder address from which to unbond
  * @param amount amount to unbond
  */
  function requestUnbonding(address transcoderAddr, uint256 amount) public returns(uint256) {
    Delegator storage delegator = delegators[msg.sender];
    require(!delegator.managed, "this method can't be used by delegator that deposited ERC20 tokens");
    return _requestUnbonding(transcoderAddr, msg.sender, amount);
  }

  function requestUnbondingManaged(address transcoderAddr, address delegatorAddr, uint256 amount) public onlyManager returns(uint256) {
    Delegator storage delegator = delegators[delegatorAddr];
    require(delegator.managed, "this method can only be used only for delegator that deposited ERC20 tokens");
    return _requestUnbonding(transcoderAddr, delegatorAddr, amount);
  }

  /**
  * @notice Withdraw first pending unbonding request.
  * @dev Callable by both tcoders & delegators.
  * Delegators can also withdraw no matter what the tcoder state is if they made an unbonding requested and the wait period passed.
  * If transfer cannot be withdrawn transaction will fail.
  */
  function withdrawPending() external {
    Delegator storage delegator = delegators[msg.sender];
    require(delegator.pending < delegator.next, "no pending requests");
    require(withdrawStake(delegator.pending, msg.sender), "failed to withdraw stake");
    delegator.pending = delegator.pending + 1;
  }

  /**
  * @notice Withdraw all pending unbonding requests.
  * @dev Callable by both tcoders & delegators.
  * Delegators can also withdraw no matter what the tcoder state is if they made an unbonding requested and the wait period passed.
  * Silently returns if there are no pending transfers that can be withdrawn.
  */
  function withdrawAllPending() external {
    Delegator storage delegator = delegators[msg.sender];
    require(delegator.pending < delegator.next, "no pending requests");
    for (uint256 i = delegator.pending; i < delegator.next; i++) {
      bool executed = withdrawStake(i, msg.sender);
      if (!executed) return;
      delegator.pending = delegator.pending + 1;
    }
  }

  /**
  * @notice Query state if there are any pending withdrawals ready to be executed.
  */
  function pendingWithdrawalsExist() external view returns (bool) {
    Delegator storage delegator = delegators[msg.sender];
    for (uint256 i = delegator.pending; i < delegator.next; i++) {
      UnbondingRequest storage request = delegator.unbondingRequests[i];
      if (block.timestamp - request.timestamp >= unbondingPeriod) return true;
    }
    return false;
  }

  /**
  * @notice Withdraw stake in transcoder.
  * @dev Callable by both tcoders & delegators.
  * Delegators can also withdraw no matter what the tcoder state is if they made an unbonding requested and the wait period passed.
  * @param unbondingID ID of unbonding request
  */
  function withdrawStake(uint256 unbondingID, address delegatorAddr) internal returns (bool) {
      Delegator storage delegator = delegators[delegatorAddr];
      UnbondingRequest storage request = delegator.unbondingRequests[unbondingID];

      if (request.amount == 0) return false;
      if (block.timestamp - request.timestamp < unbondingPeriod) return false;

      uint256 amountToTransfer = request.amount;
      request.amount = 0;

      require(stakingToken.transfer(delegatorAddr, amountToTransfer), "Token transfer failed");

      emit StakeWithdrawal(unbondingID, delegatorAddr, request.transcoder, amountToTransfer);
      return true;
  }

  /**
  * @notice Getter for unbonding requests
  * @dev If the request does not exist all the fields will be 0
  * @param delegatorAddr delegator address
  * @param unbondingID unbonding request ID for which to rebond
  */
  function getUnbondingRequest(address delegatorAddr, uint256 unbondingID) external view returns (UnbondingRequest memory) {
    Delegator storage delegator = delegators[delegatorAddr];
    return delegator.unbondingRequests[unbondingID];
  }

  /**
  * @notice Slash the transcoder stake including it`s delegators.
  * @dev Callable only by a staking manager. Increments the slash counter for lazy slashing of delegators.
  * Transcoder total stake is slashed when method is called.
  * Actual delegator stake values are updated lazily when withdraw, delegate or unbond are called.
  * @param addr transcoder address
  */
    function _slash(address addr) external onlyOwner {
        Transcoder storage transcoder = transcoders[addr];

        require(addr != address(0), "Invalid transcoder address");
        require(transcoder.timestamp > 0, "Transcoder not registered");

        TranscoderState state = getTranscoderState(addr);
        require(state == TranscoderState.BONDED || state == TranscoderState.UNBONDING, "Cannot slash this transcoder");

        uint256 slashedAmount = (transcoder.total * slashRate) / 100;
        transcoder.total -= slashedAmount;
        transcoder.slashes.push(Slash(block.timestamp, slashRate));

        require(stakingToken.transfer(slashPoolAddress, slashedAmount), "Token transfer failed");

        jail(addr);

        emit Slashed(addr, slashRate);
    }

  /**
  * @notice Applies slashing.
  * @dev Lazy slash for delegators stakes.
  * Callable from anywhere; if conditions are met it will execute.
  * Applied during bonding or unbonding.
  * @param transcoderAddr transcoder address
  * @param delegatorAddr delegator address
  */
    function applySlash(address transcoderAddr, address delegatorAddr) internal {
        Delegator storage delegator = delegators[delegatorAddr];

        uint256 slashedAmount = getSlashableAmount(transcoderAddr, delegatorAddr);
        delegator.bondedAmounts[transcoderAddr] -= slashedAmount;

        require(stakingToken.transfer(slashPoolAddress, slashedAmount), "Token transfer failed");
    }
  /**
  * @notice Returns ammount that is up for slashing of a delegator`s stake.
  * @dev Used for lazy slash for delegators stakes and to compute the real bonded value of the stake
  * @param transcoderAddr transcoder address
  * @param delegatorAddr delegator address
  */
    function getSlashableAmount(address transcoderAddr, address delegatorAddr) public view returns (uint256) {
        Transcoder storage transcoder = transcoders[transcoderAddr];
        Delegator storage delegator = delegators[delegatorAddr];

        uint256 slashable = 0;

        uint256 startCounter = delegator.slashCounters[transcoderAddr];
        for (uint256 i = startCounter; i < transcoder.slashes.length; i++) {
            uint256 rate = transcoder.slashes[i].rate;
            uint256 slashedAmount = (delegator.bondedAmounts[transcoderAddr] * rate) / 100;
            slashable += slashedAmount;
        }

        return slashable;
    }

  /**
  * @notice Jail a transcoder.
  * @dev Called when slashing
  * @param transcoderAddr transcoder address
  */
    function jail(address transcoderAddr) internal {
        Transcoder storage transcoder = transcoders[transcoderAddr];
        require(transcoder.timestamp > 0, "Transcoder not registered");
        transcoder.jailed = true;

        emit Jailed(transcoderAddr);
    }

    /**
  * @notice Unjail a transcoder.
  * @dev
  * @param transcoderAddr transcoder address
  */
  function unjail(address transcoderAddr) external onlyOwner() {
    require(transcoderAddr != address(0), "can't use zero address");
    Transcoder storage transcoder = transcoders[transcoderAddr];
    require(transcoder.timestamp > 0, "Registered transcoder only");
    transcoder.jailed = false;

    emit Unjailed(transcoderAddr);
  }

  /**
  * @notice Get total amount staked for a transcoder
  * @dev
  * @param _addr transcoder address
  */
  function getTotalStake(address _addr) public view returns (uint256) {
    require(_addr != address(0), "can't use zero address");
    return transcoders[_addr].total;
  }

  /**
  * @notice Get transcoder self-stake
  * @dev
  * @param _addr transcoder address
  */
  function getSelfStake(address _addr) public view returns (uint256) {
    return getDelegatorStake(_addr, _addr);
  }

  /**
  * @notice Get delegator stake in a transcoder
  * @dev
  * @param transcoderAddr transcoder address
  * @param delegAddr delegator address
  */
  function getDelegatorStake(address transcoderAddr, address delegAddr) public view returns (uint256) {
    require(transcoderAddr != address(0), "can't use zero address");
    require(delegAddr != address(0), "can't use zero address");
    uint256 slashable = getSlashableAmount(transcoderAddr, delegAddr);
    return delegators[delegAddr].bondedAmounts[transcoderAddr] - slashable;
  }

  /**
  * @notice Get number of slashes applied to a transcoder
  * @dev
  * @param transcoderAddr transcoder address
  */
  function getTrancoderSlashes(address transcoderAddr) public view returns (uint256) {
    require(transcoderAddr != address(0), "can't use zero address");
    Transcoder storage transcoder = transcoders[transcoderAddr];
    require(transcoder.timestamp > 0, "Transcoder not registered");
    return transcoder.slashes.length;
  }

  /**
  * @notice Get number of registered transcoders.
  **/
  function transcodersCount() external view returns (uint256) {
    return transcodersArray.length;
  }

  /**
  * @notice Get the transcoder state
  * @dev Used by miner sleection, slashing, rewards. enum TranscoderState { BONDING, BONDED, UNBONDED }
  * @param transcoderAddr transcoder address
  */
    function getTranscoderState(address transcoderAddr) public view returns (TranscoderState) {
      require(transcoderAddr != address(0), "can't use zero address");
        Transcoder storage transcoder = transcoders[transcoderAddr];
        Delegator storage delegator = delegators[transcoderAddr];

        if (transcoder.timestamp == 0) return TranscoderState.UNREGISTERED;

        if (transcoder.jailed) return TranscoderState.UNBONDED;

        if (block.timestamp - transcoder.timestamp >= transcoderApprovalPeriod) {
            if (delegator.bondedAmounts[transcoderAddr] >= transcoder.effectiveMinSelfStake) {
                return TranscoderState.BONDED;
            }
        else {
        // iff sum of incomplete self-stake unbonding requests plus bondedAmount higher than min self stake
        uint256 sum = 0;
        for (uint256 i = delegator.pending; i < delegator.next; i++) {
          UnbondingRequest storage request = delegator.unbondingRequests[i];
          if (request.transcoder != transcoderAddr) continue;
          if (block.timestamp - request.timestamp < unbondingPeriod) {
            sum = sum + request.amount;
          }
        }
        if (sum + delegator.bondedAmounts[transcoderAddr] >= minSelfStake) {
          return TranscoderState.UNBONDING;
        }
      }
    }

        return TranscoderState.BONDING;
  }
      /**
  * @notice Gettter for jailed state
  * @dev
  * @param transcoderAddr transcoder address
  */
  function isJailed(address transcoderAddr) public view returns (bool) {
    require(transcoderAddr != address(0), "can't use zero address");

    Transcoder storage transcoder = transcoders[transcoderAddr];
    require(transcoder.timestamp > 0, "Transcoder not registered");

    return transcoder.jailed;
  }
}
