const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("StakingManager", function () {
  let StakingManager, stakingManager;
  let manager, delegator, delegator2, slashFund, transcoder;
  const TranscoderState = {
    BONDING: ethers.BigNumber.from(0),
    BONDED: ethers.BigNumber.from(1),
    UNBONDED: ethers.BigNumber.from(2),
    UNBONDING: ethers.BigNumber.from(3),
  };

  const oneDay = 86400;
  const oneSec = 1;
  const minDelegation = ethers.utils.parseEther("6");
  const minSelfDelegation = ethers.utils.parseEther("10");
  const approvalPeriod = 5;
  const unbondingPeriod = 10;
  const slashRate = 50;
  const rewardRate = 10;

  before(async function () {
    [manager, delegator, delegator2, slashFund, transcoder] =
      await ethers.getSigners();
    StakingManager = await ethers.getContractFactory("StakingManager");
  });

  beforeEach(async function () {
    stakingManager = await StakingManager.deploy(
      minDelegation,
      minSelfDelegation,
      approvalPeriod,
      unbondingPeriod,
      slashRate,
      slashFund.address
    );
    await stakingManager.deployed();
  });

  describe("Deployment", function () {
    it("should deploy successfully", async function () {
      expect(stakingManager.address).to.not.be.undefined;
    });
  });

  describe("Manager Actions", function () {
    it("should allow manager to set a new minimum self-stake", async function () {
      await stakingManager.connect(manager).setSelfMinStake(minSelfDelegation);
      const newMinSelfStake = await stakingManager.minSelfStake();
      expect(newMinSelfStake).to.equal(minSelfDelegation);
    });
  });

  describe("Transcoder Registration", function () {
    beforeEach(async function () {
      await stakingManager
        .connect(transcoder)
        .registerTranscoder(rewardRate);
    });

    it("should allow a transcoder to register and be in BONDING state", async function () {
      const state = await stakingManager.getTranscoderState(
        transcoder.address
      );
      expect(state).to.equal(TranscoderState.BONDING);
    });

    it("should transition to BONDED after the approval period and meeting minimum self-delegation", async function () {
      await network.provider.send("evm_increaseTime", [approvalPeriod]);
      await network.provider.send("evm_mine");

      await stakingManager
        .connect(transcoder)
        .delegate(transcoder.address, { value: minSelfDelegation });

      const state = await stakingManager.getTranscoderState(
        transcoder.address
      );
      expect(state).to.equal(TranscoderState.BONDED);
    });
  });

  describe("Delegations", function () {
    beforeEach(async function () {
      await stakingManager
        .connect(transcoder)
        .registerTranscoder(rewardRate);
      await network.provider.send("evm_increaseTime", [approvalPeriod]);
      await network.provider.send("evm_mine");
    });

    it("should allow a delegator to delegate to a registered transcoder", async function () {
      await stakingManager
        .connect(delegator)
        .delegate(transcoder.address, { value: minDelegation });

      const stake = await stakingManager.getDelegatorStake(
        transcoder.address,
        delegator.address
      );
      const totalStake = await stakingManager.getTotalStake(
        transcoder.address
      );

      expect(stake).to.equal(minDelegation);
      expect(totalStake).to.equal(minDelegation);
    });

    it("should not allow delegations below the minimum amount", async function () {
      await expect(
        stakingManager
          .connect(delegator)
          .delegate(transcoder.address, { value: ethers.utils.parseEther("1") })
      ).to.be.revertedWith("Minimum delegation amount not met");
    });
  });

  describe("Slashing", function () {
    beforeEach(async function () {
      await stakingManager
        .connect(transcoder)
        .registerTranscoder(rewardRate);
      await stakingManager
        .connect(transcoder)
        .delegate(transcoder.address, { value: minSelfDelegation });
      await network.provider.send("evm_increaseTime", [approvalPeriod]);
      await network.provider.send("evm_mine");
    });

    it("should allow manager to slash a BONDED transcoder", async function () {
      const stakeBefore = await stakingManager.getTotalStake(
        transcoder.address
      );

      await stakingManager.connect(manager).slash(transcoder.address);

      const stakeAfter = await stakingManager.getTotalStake(
        transcoder.address
      );
      const expectedStake = stakeBefore.mul(slashRate).div(100);
      expect(stakeAfter).to.equal(expectedStake);
    });
  });
});
