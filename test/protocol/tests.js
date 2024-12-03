const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Stream and StreamManager", function () {
  let StreamManager, Stream;
  let streamManager, stream;
  let managerAcc, client, miner, validator, malicious, publisher, anyone;
  let streamId;

  const wattage = ethers.BigNumber.from("10").pow(16);
  const wattagesArr = Array(10).fill(wattage);

  before(async function () {
    [managerAcc, client, miner, validator, malicious, publisher, anyone] =
      await ethers.getSigners();
    StreamManager = await ethers.getContractFactory("StreamManager");
    Stream = await ethers.getContractFactory("Stream");
  });

  beforeEach(async function () {
    streamManager = await StreamManager.deploy();
    await streamManager.deployed();
    stream = null;
    streamId = ethers.BigNumber.from(1);
  });

  async function createNewStream(manager, client, profiles, chunks) {
    const id = Math.floor(Math.random() * 1000); // Random ID for the stream
    const value = ethers.BigNumber.from("10").pow(19); // Example value for stream funding

    await manager.connect(client).requestStream(id, profiles);
    await manager.connect(managerAcc).approveStreamCreation(id);
    const tx = await manager.connect(client).createStream(id, { value });
    const receipt = await tx.wait();
    const streamAddr = receipt.events.find((e) => e.event === "StreamCreated").args.streamAddress;
    const streamInstance = await Stream.attach(streamAddr);
    return { stream: streamInstance, streamId: id };
  }

  describe("StreamManager Contract Tests", function () {
    const chunks = [ethers.BigNumber.from(1), ethers.BigNumber.from(2)];
    const profiles = ["profile1", "profile2", "profile3"];

    it("should deploy correctly", async function () {
      expect(streamManager.address).to.not.be.undefined;
    });

    it("should have the deployer account as the owner", async function () {
      const owner = await streamManager.owner();
      expect(owner).to.equal(managerAcc.address);
    });

    it("should allow the owner to add validators", async function () {
      // Validator should not exist initially
      let isValidator = await streamManager.isValidator(validator.address);
      expect(isValidator).to.be.false;

      // Add validator
      await streamManager.connect(managerAcc).addValidator(validator.address);

      // Validator should now exist
      isValidator = await streamManager.isValidator(validator.address);
      expect(isValidator).to.be.true;
    });

    it("should allow the owner to remove validators", async function () {
      // Add and then remove validator
      await streamManager.connect(managerAcc).addValidator(validator.address);
      let isValidator = await streamManager.isValidator(validator.address);
      expect(isValidator).to.be.true;

      await streamManager.connect(managerAcc).removeValidator(validator.address);
      isValidator = await streamManager.isValidator(validator.address);
      expect(isValidator).to.be.false;
    });

    it("should only allow the owner to manage validators", async function () {
      // Attempt by malicious actor to add/remove validator
      await expect(
        streamManager.connect(malicious).addValidator(validator.address)
      ).to.be.revertedWith("Ownable: caller is not the owner");

      await expect(
        streamManager.connect(malicious).removeValidator(validator.address)
      ).to.be.revertedWith("Ownable: caller is not the owner");
    });
  });

  describe("Stream Creation and Management", function () {
    const profiles = ["profile1", "profile2", "profile3"];

    it("should allow a client to request a stream", async function () {
      const tx = await streamManager.connect(client).requestStream(streamId, profiles);
      const receipt = await tx.wait();

      // Check emitted event
      const event = receipt.events.find((e) => e.event === "StreamRequested");
      expect(event.args.client).to.equal(client.address);
      expect(event.args.streamId).to.equal(streamId);

      // Check request details
      const request = await streamManager.requests(streamId);
      expect(request.client).to.equal(client.address);
      expect(request.stream).to.equal(ethers.constants.AddressZero);
      expect(request.approved).to.be.false;
      expect(request.refund).to.be.false;
    });

    it("should allow the owner to approve a stream", async function () {
      // Request stream
      await streamManager.connect(client).requestStream(streamId, profiles);

      // Approve stream
      const tx = await streamManager.connect(managerAcc).approveStreamCreation(streamId);
      const receipt = await tx.wait();

      // Check emitted event
      const event = receipt.events.find((e) => e.event === "StreamApproved");
      expect(event.args.streamId).to.equal(streamId);

      // Check request details
      const request = await streamManager.requests(streamId);
      expect(request.client).to.equal(client.address);
      expect(request.approved).to.be.true;
    });

    it("should allow a client to create a stream", async function () {
      const value = ethers.utils.parseEther("1");

      // Request and approve stream
      await streamManager.connect(client).requestStream(streamId, profiles);
      await streamManager.connect(managerAcc).approveStreamCreation(streamId);

      // Create stream
      const tx = await streamManager.connect(client).createStream(streamId, { value });
      const receipt = await tx.wait();
      const streamAddr = receipt.events.find((e) => e.event === "StreamCreated").args.streamAddress;

      // Check emitted event
      const event = receipt.events.find((e) => e.event === "StreamCreated");
      expect(event.args.streamId).to.equal(streamId);
      expect(event.args.streamAddress).to.equal(streamAddr);

      // Check request details
      const request = await streamManager.requests(streamId);
      expect(request.client).to.equal(client.address);
      expect(request.stream).to.equal(streamAddr);
      expect(request.approved).to.be.true;

      // Check stream manager address
      const deployedStream = await Stream.attach(streamAddr);
      const managerAddress = await deployedStream.manager();
      expect(managerAddress).to.equal(streamManager.address);
    });
  });

  describe("Stream Contract Tests", function () {
    const profiles = ["profile1", "profile2"];
    const chunks = [ethers.BigNumber.from(1), ethers.BigNumber.from(2)];

    beforeEach(async function () {
      // Create stream
      const value = ethers.utils.parseEther("1");
      await streamManager.connect(client).requestStream(streamId, profiles);
      await streamManager.connect(managerAcc).approveStreamCreation(streamId);

      const tx = await streamManager.connect(client).createStream(streamId, { value });
      const receipt = await tx.wait();
      const streamAddr = receipt.events.find((e) => e.event === "StreamCreated").args.streamAddress;
      stream = await Stream.attach(streamAddr);
    });

    it("should allow a manager to add input chunks", async function () {
      const chunkId = ethers.BigNumber.from(1000);

      // Add chunk ID
      const tx = await streamManager
        .connect(managerAcc)
        .addInputChunkId(streamId, chunkId, wattagesArr);
      const receipt = await tx.wait();

      // Check emitted event
      const event = receipt.events.find((e) => e.event === "InputChunkAdded");
      expect(event.args.chunkId).to.equal(chunkId);
      expect(event.args.streamId).to.equal(streamId);

      // Check chunk in stream
      const isChunkAdded = await stream.isChunk(chunkId);
      expect(isChunkAdded).to.be.true;
    });
  });
});
