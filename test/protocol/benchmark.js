const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Stream and StreamManager", function () {
  let Stream, StreamManager;
  let streamManager, stream;
  let managerAcc, client, miner, validator;
  const wattage = ethers.BigNumber.from(10).pow(16);
  const wattagesArr = Array(10).fill(wattage);
  const streamId = ethers.BigNumber.from(1);

  before(async function () {
    [managerAcc, client, miner, validator] = await ethers.getSigners();
    StreamManager = await ethers.getContractFactory("StreamManager");
    Stream = await ethers.getContractFactory("Stream");
  });

  beforeEach(async function () {
    streamManager = await StreamManager.deploy();
    await streamManager.deployed();
    stream = null;
  });

  describe("Benchmark Smart Contracts", function () {
    const chunks = [ethers.BigNumber.from(1), ethers.BigNumber.from(2), ethers.BigNumber.from(3)];
    const profiles = ["profile1", "profile2", "profile3"];
    const wattages = wattagesArr.slice(0, profiles.length);
    const profile = ethers.utils.keccak256(ethers.utils.toUtf8Bytes(profiles[0]));

    describe("Manager Deploy Benchmark", function () {
      it("should log gas used for deployment", async function () {
        const txHash = streamManager.deployTransaction.hash;
        const receipt = await ethers.provider.getTransactionReceipt(txHash);
        console.log(`Manager deployment gas: ${receipt.gasUsed}`);
      });
    });

    describe("Stream Deploy Benchmark - Lower Bound", function () {
      it("should log gas usage for stream deployment", async function () {
        const value = ethers.utils.parseEther("0.1"); // 0.1 Ether
        let totalGas = 0;

        // Request Stream
        let tx = await streamManager.connect(client).requestStream(streamId, profiles);
        let receipt = await tx.wait();
        console.log(`requestStream: ${receipt.gasUsed}`);
        totalGas += receipt.gasUsed;

        // Approve Stream Creation
        tx = await streamManager.connect(managerAcc).approveStreamCreation(streamId);
        receipt = await tx.wait();
        console.log(`approveStreamCreation: ${receipt.gasUsed}`);
        totalGas += receipt.gasUsed;

        // Create Stream
        tx = await streamManager.connect(client).createStream(streamId, { value });
        receipt = await tx.wait();
        console.log(`createStream: ${receipt.gasUsed}`);
        totalGas += receipt.gasUsed;

        console.log(`Stream deployment total gas: ${totalGas}`);
      });
    });

    describe("Chunk Processing Benchmark - Lower Bound", function () {
      it("should log gas usage for chunk processing", async function () {
        let totalGas = 0;

        const value = ethers.utils.parseEther("10"); // 10 Ether
        const chunkId = 1, proof = 1, outChunkId = 1;

        // Add Validator
        await streamManager.connect(managerAcc).addValidator(validator.address);

        // Request Stream
        await streamManager.connect(client).requestStream(streamId, profiles);

        // Approve Stream Creation
        await streamManager.connect(managerAcc).approveStreamCreation(streamId);

        // Create Stream
        const tx = await streamManager.connect(client).createStream(streamId, { value });
        const receipt = await tx.wait();
        const streamAddr = receipt.events.find((e) => e.event === "StreamCreated").args.streamAddress;
        stream = await Stream.attach(streamAddr);

        // Add Input Chunk
        let res = await streamManager.connect(managerAcc).addInputChunkId(streamId, chunks[0], wattages);
        let gas = (await res.wait()).gasUsed;
        console.log(`addInputChunkId: ${gas}`);
        totalGas += gas;

        // Submit Proof
        res = await stream.connect(miner).submitProof(profile, chunkId, proof, outChunkId);
        gas = (await res.wait()).gasUsed;
        console.log(`submitProof: ${gas}`);
        totalGas += gas;

        // Validate Proof
        res = await stream.connect(validator).validateProof(profile, chunkId);
        gas = (await res.wait()).gasUsed;
        console.log(`validateProof: ${gas}`);
        totalGas += gas;

        console.log(`Chunk processing total gas: ${totalGas}`);
      });
    });
  });
});
