/*
  This is a helper to move price on Uniswap
*/

import { Contract } from "ethers";

import IERC20 from "@openzeppelin/contracts/build/contracts/ERC20.json";
import ISwapRouter from "@uniswap/v3-periphery/artifacts/contracts/interfaces/ISwapRouter.sol/ISwapRouter.json";

import { WETH, UNISWAP_ROUTER } from "./constants.js";

export async function swap(tokenIn: string, tokenOut: string, amount: bigint, impersonator: any) {
  const FEE = 500;
  const DEADLINE = Math.floor(Date.now() / 1000) + 60 * 20; // 20 minutes
  const router = new Contract(UNISWAP_ROUTER, ISwapRouter.abi);
  const token0 = new Contract(tokenIn, IERC20.abi);

  // Approve
  await (await token0.connect(impersonator).approve(
    UNISWAP_ROUTER,
    amount,
    { gasLimit: 125000 }
  )).wait();

  // Setup swap parameters
  const ExactInputSingleParams = {
    tokenIn: tokenIn,
    tokenOut: tokenOut,
    fee: FEE,
    recipient: impersonator.address,
    deadline: DEADLINE,
    amountIn: amount,
    amountOutMinimum: 0,
    sqrtPriceLimitX96: 0
  };

  if (tokenIn === WETH) {
    await (await router.connect(impersonator).exactInputSingle(
      ExactInputSingleParams,
      { value: amount },
    )).wait();
  } else {
    await (await router.connect(impersonator).exactInputSingle(
      ExactInputSingleParams,
    )).wait();
  }
}