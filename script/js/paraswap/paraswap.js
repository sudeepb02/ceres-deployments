import "dotenv/config";
import axios from "axios";
import { constructSimpleSDK, SwapSide } from "@paraswap/sdk";
import { ethers } from "ethers";
import { writeFileSync } from "fs";
import path from "path";
import { fileURLToPath } from "url";

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

function getProvider(chainId) {
  const envKeyPrimary = `RPC_CHAINID_${chainId}`;
  //   const rpcUrl = process.env.envKeyPrimary;
  const rpcUrl =
    "https://arb-mainnet.g.alchemy.com/v2/fsnUOifxtseIxdhw9Q5-OZk52F2hlSZY";
  if (!rpcUrl) {
    throw new Error(`Missing RPC url env var ${envKeyPrimary}`);
  }
  return new ethers.JsonRpcProvider(rpcUrl);
}

async function resolveDecimals(token, provider, provided) {
  if (provided !== undefined && provided !== null) {
    return Number(provided);
  }

  const erc20 = new ethers.Contract(
    token,
    ["function decimals() view returns (uint8)"],
    provider,
  );
  const decimalDigits = await erc20.decimals();
  console.log(`Resolved token decimals for ${token}: ${decimalDigits}`);

  return decimalDigits;
}

function buildSdk(chainId) {
  const axiosInstance = axios.create({
    headers: { "User-Agent": "ceres-paraswap-helper" },
  });
  axiosInstance.isAxiosError = axios.isAxiosError;

  return constructSimpleSDK({ chainId: Number(chainId), axios: axiosInstance });
}

function writeOutputs(detailed, rawData) {
  const detailedPath = path.join(__dirname, "swapOutputDetailed.txt");
  const rawPath = path.join(__dirname, "swapOutputRaw.txt");

  writeFileSync(detailedPath, `${JSON.stringify(detailed, null, 2)}\n`);
  writeFileSync(rawPath, `${rawData}\n`);

  return { detailedPath, rawPath };
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

  const slippageBps = params.slippageBps
    ? Number(params.slippageBps)
    : DEFAULT_SLIPPAGE_BPS;
  const provider = getProvider(chainId);

  const srcDecimals = await resolveDecimals(
    fromToken,
    provider,
    params.srcDecimals,
  );
  const destDecimals = await resolveDecimals(
    toToken,
    provider,
    params.destDecimals,
  );

  const sdk = buildSdk(chainId);
  const side = swapType === "exactOut" ? SwapSide.BUY : SwapSide.SELL;

  const rateInput = {
    srcToken: fromToken,
    destToken: toToken,
    amount,
    srcDecimals,
    destDecimals,
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

  writeFileSync("debug_buildInput.json", JSON.stringify(buildInput, null, 2));

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

  const detailed = {
    chainId,
    swapType,
    side: side === SwapSide.SELL ? "SELL" : "BUY",
    fromToken,
    toToken,
    amount,
    srcDecimals,
    destDecimals,
    slippageBps,
    augustus: txParams.to,
    value: txParams.value ?? "0",
    gas: txParams.gas,
    maxFeePerGas: txParams.maxFeePerGas,
    maxPriorityFeePerGas: txParams.maxPriorityFeePerGas,
    data: txParams.data,
  };

  return { detailed, raw: txParams.data };
}

// Convenience wrapper: builds and writes outputs like the Kyber helper
export async function getSwapData(params) {
  const { detailed, raw } = await getParaswapSwapData(params);
  return writeOutputs(detailed, raw);
}
