/*
  This is a helper to get quotes on Uniswap
*/

import { Contract } from "ethers";

import IQuoter from "@uniswap/v3-periphery/artifacts/contracts/interfaces/IQuoterV2.sol/IQuoterV2.json";

import { UNISWAP_QUOTER } from "./constants.js";

export async function quote(tokenIn: string, tokenOut: string, amount: bigint, provider: any) {
  const FEE = 500;
  const quoter = new Contract(UNISWAP_QUOTER, IQuoter.abi, provider);

  const quoteExactInputSingleParams = {
    tokenIn: tokenIn,
    tokenOut: tokenOut,
    fee: FEE,
    amountIn: amount,
    sqrtPriceLimitX96: 0
  };

  const [amountOut] = await quoter.quoteExactInputSingle.staticCall(
    quoteExactInputSingleParams
  );

  return amountOut;
}