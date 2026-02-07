import "dotenv/config";
import axios from "axios";
import { constructSimpleSDK, SwapSide } from "@paraswap/sdk";
import { writeFileSync } from "fs";
import path from "path";
import { fileURLToPath } from "url";
import { writeSwapOutputFiles } from "../common/fileUtils.js";

const DEFAULT_SLIPPAGE_BPS = 50; // 0.5%

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

function requiredParam(params, key) {
  const value = params[key];
  if (value === undefined || value === null || value === "") {
    throw new Error(`Missing required param: ${key}`);
  }
  return value;
}

function buildSdk(chainId) {
  const axiosInstance = axios.create({
    headers: { "User-Agent": "ceres-paraswap-helper" },
  });
  axiosInstance.isAxiosError = axios.isAxiosError;

  return constructSimpleSDK({ chainId: Number(chainId), axios: axiosInstance });
}

function writeOutputs(detailed, rawData) {
  return writeSwapOutputFiles(__dirname, detailed, rawData);
}

function isRateLimit(err) {
  const resp = err && err.response;
  return resp && resp.status === 429;
}

export async function getParaswapSwapData(params) {
  const chainId = Number(requiredParam(params, "chainId"));
  const fromToken = requiredParam(params, "fromToken");
  const toToken = requiredParam(params, "toToken");
  const amount = requiredParam(params, "amount");
  const swapType = requiredParam(params, "swapType"); // exactIn or exactOut
  const swapper = requiredParam(params, "swapper");
  const fromTokenDecimals = Number(requiredParam(params, "fromTokenDecimals"));
  const toTokenDecimals = Number(requiredParam(params, "toTokenDecimals"));

  const slippageBps = params.slippageBps
    ? Number(params.slippageBps)
    : DEFAULT_SLIPPAGE_BPS;

  const sdk = buildSdk(chainId);
  const side = swapType === "exactOut" ? SwapSide.BUY : SwapSide.SELL;

  const rateInput = {
    srcToken: fromToken,
    destToken: toToken,
    amount,
    srcDecimals: fromTokenDecimals,
    destDecimals: toTokenDecimals,
    side,
    options: {
      slippage: slippageBps,
      partner: "ceres",
      receiver: swapper,
      userAddress: swapper,
    },
  };

  let priceRoute;
  try {
    priceRoute = await sdk.swap.getRate(rateInput);
  } catch (err) {
    if (isRateLimit(err)) {
      throw new Error("Rate limited by Paraswap (HTTP 429)");
    }
    throw err;
  }

  const buildInput = {
    srcToken: fromToken,
    destToken: toToken,
    srcDecimals,
    destDecimals,
    priceRoute,
    userAddress: swapper,
    receiver: swapper,
    partner: "ceres",
    slippage: slippageBps,
    deadline: Math.floor(Date.now() / 1000) + 1800,
  };

  if (side === SwapSide.SELL) {
    buildInput.srcAmount = amount;
  } else {
    buildInput.destAmount = amount;
  }

  // Write debug build input to paraswap directory
  const debugPath = path.join(__dirname, "debug_buildInput.json");
  writeFileSync(debugPath, JSON.stringify(buildInput, null, 2));

  let txParams;
  try {
    txParams = await sdk.swap.buildTx(buildInput);
  } catch (err) {
    if (isRateLimit(err)) {
      throw new Error("Rate limited by Paraswap (HTTP 429)");
    }
    throw err;
  }

  if (!txParams?.data) {
    throw new Error("Paraswap buildTx returned empty data");
  }

  // Dump full API responses for debugging
  const detailed = {
    inputParams: {
      chainId,
      swapType,
      side: side === SwapSide.SELL ? "SELL" : "BUY",
      fromToken,
      toToken,
      amount,
      fromTokenDecimals,
      toTokenDecimals,
      swapper,
      slippageBps,
    },
    priceRouteResponse: priceRoute,
    buildTxResponse: txParams,
  };

  return { detailed, raw: txParams.data };
}

// Convenience wrapper: builds and writes outputs like the Kyber helper
export async function getSwapData(params) {
  const { detailed, raw } = await getParaswapSwapData(params);
  return writeOutputs(detailed, raw);
}
