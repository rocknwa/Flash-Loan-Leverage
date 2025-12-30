import { network } from "hardhat";
const { ethers, networkHelpers } = await network.connect();

import IERC20 from "@openzeppelin/contracts/build/contracts/ERC20.json";

import { swap } from "../helpers/swap.js";
import { quote } from "../helpers/quote.js";
import { getPrice } from "../helpers/price.js";
import { WETH, USDC, UNLOCKED_ACCOUNT } from "../helpers/constants.js";

export async function setupFixture() {
  // We take a snapshot of the blockchain state so we can
  // reset back to this initial starting point after
  // a test case.
  const snapshot = await networkHelpers.takeSnapshot();

  const { maxFeePerGas } = await ethers.provider.getFeeData();

  const position = await ethers.deployContract("Position", { maxFeePerGas });
  const [owner] = await ethers.getSigners();

  // We'll impersonate an account that has USDC. This is so that
  // we can manipulate the WETH/USDC pool on Uniswap to
  // simulate prices increasing or decreasing
  await (await ethers.getSigners())[1].sendTransaction({
    to: UNLOCKED_ACCOUNT,
    value: ethers.parseUnits("8000", 18),
  });

  const impersonator = await ethers.getImpersonatedSigner(UNLOCKED_ACCOUNT);

  const usdc = new ethers.Contract(USDC, IERC20.abi);
  const weth = new ethers.Contract(WETH, IERC20.abi);

  return { position, usdc, weth, owner, impersonator, snapshot }
}

export async function longFixture() {
  const { position, usdc, owner, impersonator, snapshot } = await setupFixture();

  /*** 
   * 
   * INITIAL SUPPLY TO AAVE
   * Even though the flash loan is used for opening & closing a 
   * position, there needs to be extra liquidity supplied in 
   * order to borrow enough to repay the flash loan
   * 
   * ***/

  const INITIAL_CAPITAL_AMOUNT = ethers.parseUnits("1000", 6);
  const BORROW_AMOUNT = ethers.parseUnits("2000", 6);

  await (await usdc.connect(impersonator).transfer(
    await position.getAddress(),
    INITIAL_CAPITAL_AMOUNT,
  ));

  const INITIAL_USDC_BALANCE = ethers.formatUnits(
    await position.getTokenBalance(USDC),
    6
  );

  console.log(`\nInitial Capital: ${INITIAL_USDC_BALANCE} USDC\n`);


  /*** 
   * 
   * OPEN LONG POSITION 
   * 
   * ***/

  const OPEN_PARAMS = {
    assetToSupply: WETH,
    assetToBorrow: USDC,
    assetToBorrowAmount: BORROW_AMOUNT,
    initialCapital: INITIAL_CAPITAL_AMOUNT,
    expectedSwapAmount: await quote(USDC, WETH, BORROW_AMOUNT, ethers.provider),
  }

  await (await position.connect(owner).openPosition(
    OPEN_PARAMS,
  )).wait();

  const INITIAL_HEALTH_FACTOR = await position.getHealthFactor();

  /*** 
   * 
   * MANIPULATE PRICE 
   * 
   * ***/

  console.log(`Price before: ${await getPrice(ethers)}`);
  console.log(`Current Health Factor: ${ethers.formatUnits(INITIAL_HEALTH_FACTOR, 18)}\n`);

  console.log(`Swapping...\n`);

  await swap(
    USDC,
    WETH,
    ethers.parseUnits("10000000", 6),
    impersonator,
  );

  const NEW_HEALTH_FACTOR = await position.getHealthFactor();

  console.log(`Price after: ${await getPrice(ethers)}`);
  console.log(`Current Health Factor: ${ethers.formatUnits(NEW_HEALTH_FACTOR, 18)}\n`);

  /*** 
   * 
   * CLOSE LONG POSITION 
   * 
   * ***/

  const CLOSE_PARAMS = {
    assetToWithdraw: WETH,
    assetToRepay: USDC,
  }

  await (await position.connect(owner).closePosition(
    CLOSE_PARAMS,
  )).wait();

  return { position, INITIAL_CAPITAL_AMOUNT, snapshot };
}

export async function shortFixture() {
  const { position, owner, impersonator, snapshot } = await setupFixture();

  /*** 
   * 
   * INITIAL SUPPLY TO AAVE
   * Even though the flash loan is used for opening & closing a 
   * position, there needs to be extra liquidity supplied in 
   * order to borrow enough to repay the flash loan
   * 
   * ***/

  const INITIAL_CAPITAL_AMOUNT = ethers.parseUnits("1", 18);
  const BORROW_AMOUNT = ethers.parseUnits("2", 18);

  await (await position.connect(owner).getWETH({ value: INITIAL_CAPITAL_AMOUNT })).wait();

  const INITIAL_WETH_BALANCE = ethers.formatUnits(
    await position.getTokenBalance(WETH),
    18
  );

  console.log(`Initial Capital: ${INITIAL_WETH_BALANCE} WETH\n`);

  /*** 
   * 
   * OPEN SHORT POSITION 
   * 
   * ***/

  const OPEN_PARAMS = {
    assetToSupply: USDC,
    assetToBorrow: WETH,
    assetToBorrowAmount: BORROW_AMOUNT,
    initialCapital: INITIAL_CAPITAL_AMOUNT,
    expectedSwapAmount: await quote(WETH, USDC, BORROW_AMOUNT, ethers.provider),
  }

  await (await position.connect(owner).openPosition(OPEN_PARAMS)).wait();

  const INITIAL_HEALTH_FACTOR = await position.getHealthFactor();

  /*** 
   * 
   * MANIPULATE PRICE 
   * 
   * ***/


  console.log(`Price before: ${await getPrice(ethers)}`);
  console.log(`Current Health Factor: ${ethers.formatUnits(INITIAL_HEALTH_FACTOR, 18)}\n`);

  console.log(`Swapping...\n`);

  await swap(
    WETH,
    USDC,
    ethers.parseUnits("1500", 18),
    impersonator,
  );

  const NEW_HEALTH_FACTOR = await position.getHealthFactor();

  console.log(`Price after: ${await getPrice(ethers)}`);
  console.log(`Current Health Factor: ${ethers.formatUnits(NEW_HEALTH_FACTOR, 18)}\n`);

  /*** 
   * 
   * CLOSE SHORT POSITION 
   * 
   * ***/

  const CLOSE_PARAMS = {
    assetToWithdraw: USDC,
    assetToRepay: WETH,
  }

  await (await position.connect(owner).closePosition(CLOSE_PARAMS)).wait();

  return { position, INITIAL_CAPITAL_AMOUNT, snapshot };
}