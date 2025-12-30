import { expect } from "chai";
import { network } from "hardhat";

const { ethers, networkHelpers } = await network.connect();

import { longFixture, shortFixture, setupFixture } from "./fixtures/setup.js";
import { WETH, USDC, AAVE_WETH, AAVE_USDC } from "./helpers/constants.js";

describe("Position", function () {
  describe("Long Position", () => {
    it("Opens an active position", async () => {
      const { position, snapshot, INITIAL_CAPITAL_AMOUNT } = await networkHelpers.loadFixture(longFixture);

      const AAVE_WETH_BALANCE = await position.getTokenBalance(AAVE_WETH);
      expect(AAVE_WETH_BALANCE).to.equal(0);

      const WETH_BALANCE = await position.getTokenBalance(WETH);
      expect(WETH_BALANCE).to.equal(0);

      const AAVE_USDC_BALANCE = await position.getTokenBalance(AAVE_USDC);
      expect(AAVE_USDC_BALANCE).to.equal(0);

      const USDC_BALANCE = await position.getTokenBalance(USDC);
      expect(USDC_BALANCE).to.be.greaterThan(INITIAL_CAPITAL_AMOUNT);

      console.table({
        "aWETH": `${Number(ethers.formatUnits(AAVE_WETH_BALANCE.toString(), 18)).toFixed(2)}`,
        "WETH": `${Number(ethers.formatUnits(WETH_BALANCE.toString(), 18)).toFixed(2)}`,
        "aUSDC": `${Number(ethers.formatUnits(AAVE_USDC_BALANCE.toString(), 6)).toFixed(2)}`,
        "USDC": `${Number(ethers.formatUnits(USDC_BALANCE.toString(), 6)).toFixed(2)}`,
      });

      await snapshot.restore();
    });
  });

  describe("Short Position", () => {
    it("Opens an active position", async () => {
      const { position, INITIAL_CAPITAL_AMOUNT, snapshot } = await networkHelpers.loadFixture(shortFixture);

      const AAVE_WETH_BALANCE = await position.getTokenBalance(AAVE_WETH);
      expect(AAVE_WETH_BALANCE).to.equal(0);

      const WETH_BALANCE = await position.getTokenBalance(WETH);
      expect(WETH_BALANCE).to.be.greaterThan(INITIAL_CAPITAL_AMOUNT);

      const AAVE_USDC_BALANCE = await position.getTokenBalance(AAVE_USDC);
      expect(AAVE_USDC_BALANCE).to.equal(0);

      const USDC_BALANCE = await position.getTokenBalance(USDC);
      expect(USDC_BALANCE).to.equal(0);

      console.table({
        "aWETH": `${Number(ethers.formatUnits(AAVE_WETH_BALANCE.toString(), 18)).toFixed(2)}`,
        "WETH": `${Number(ethers.formatUnits(WETH_BALANCE.toString(), 18)).toFixed(2)}`,
        "aUSDC": `${Number(ethers.formatUnits(AAVE_USDC_BALANCE.toString(), 6)).toFixed(2)}`,
        "USDC": `${Number(ethers.formatUnits(USDC_BALANCE.toString(), 6)).toFixed(2)}`,
      });

      await snapshot.restore();
    });
  });

  describe("Withdrawing", () => {
    it("Allows owner to withdraw tokens", async () => {
      const { position, owner, weth, snapshot } = await networkHelpers.loadFixture(setupFixture);

      const INITIAL_CAPITAL_AMOUNT = ethers.parseUnits("1", 18);

      await (await position.connect(owner).getWETH({ value: INITIAL_CAPITAL_AMOUNT })).wait();

      const INITIAL_WETH_BALANCE = await position.getTokenBalance(WETH);
      expect(INITIAL_WETH_BALANCE).to.equal(INITIAL_CAPITAL_AMOUNT);

      await (await position.connect(owner).withdrawTokens(
        WETH,
        INITIAL_WETH_BALANCE,
      )).wait();

      const CONTRACT_WETH_BALANCE = await position.getTokenBalance(WETH);
      expect(CONTRACT_WETH_BALANCE).to.equal(0);

      const OWNER_WETH_BALANCE = await weth.connect(owner).balanceOf(owner.address);
      expect(OWNER_WETH_BALANCE).to.be.greaterThanOrEqual(INITIAL_WETH_BALANCE);

      await snapshot.restore();
    });
  });
});
