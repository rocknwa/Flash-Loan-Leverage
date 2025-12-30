import Big from "big.js";
import IUniswapV3Pool from "@uniswap/v3-core/artifacts/contracts/interfaces/IUniswapV3Pool.sol/IUniswapV3Pool.json";

import { UNISWAP_WETH_USDC_POOL } from "./constants.js";

export async function getPrice(ethers: any) {
  // Understanding Uniswap V3 prices
  // --> https://blog.uniswap.org/uniswap-v3-math-primer

  const pool = new ethers.Contract(
    UNISWAP_WETH_USDC_POOL,
    IUniswapV3Pool.abi,
    ethers.provider
  );

  // Get sqrtPriceX96...
  const [sqrtPriceX96] = await pool.slot0();

  // Get decimalDifference if there is a difference...
  const decimalDifference = Number(Big(18 - 6).abs());
  const conversion = Big(10).pow(decimalDifference);

  // Calculate rate and price...
  const rate = (Big(sqrtPriceX96).div(2 ** 96)).pow(2);

  const price = Big(rate).div(Big(conversion));
  const priceInverted = Number(Big(1).div(price)).toFixed(2);

  return priceInverted;
}