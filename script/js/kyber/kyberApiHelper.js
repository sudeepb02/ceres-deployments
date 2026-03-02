import axios from "axios";
import path from "path";
import { fileURLToPath } from "url";
import { writeSwapOutputFiles } from "../common/fileUtils.js";

export const AGGREGATOR_DOMAIN = `https://aggregator-api.kyberswap.com`;
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const KYBER_CHAIN_SLUGS = {
  1: "ethereum",
  10: "optimism",
  56: "bsc",
  100: "xdai",
  137: "polygon",
  250: "fantom",
  42161: "arbitrum",
  43114: "avalanche",
  8453: "base",
};

function chainSlug(chainId) {
  const slug = KYBER_CHAIN_SLUGS[Number(chainId)];
  if (!slug) {
    throw new Error(`Unsupported Kyber chainId: ${chainId}`);
  }
  return slug;
}

function requiredParam(params, key) {
  const value = params[key];
  if (value === undefined || value === null || value === "") {
    throw new Error(`Missing required param: ${key}`);
  }
  return value;
}

function writeOutputs(detailed, rawData) {
  return writeSwapOutputFiles(__dirname, detailed, rawData);
}

// Recursive function to retry on 429 rate limiting errors
async function retryWithWait(fn, retries = 5, delay = 2000) {
  try {
    return await fn();
  } catch (error) {
    if (retries > 0 && error.response?.status === 429) {
      const jitter = Math.floor(Math.random() * 1000);
      await new Promise((resolve) => setTimeout(resolve, delay + jitter));
      return retryWithWait(fn, retries - 1, delay * 1.5);
    }
    throw error;
  }
}

export async function getKyberSwapData(params) {
  const chainId = requiredParam(params, "chainId");
  const fromToken = requiredParam(params, "fromToken");
  const toToken = requiredParam(params, "toToken");
  const amount = requiredParam(params, "amount");
  const swapper = requiredParam(params, "swapper");
  const swapType = params.swapType ?? "exactIn";

  if (swapType !== "exactIn") {
    throw new Error("Kyber helper currently supports exactIn only");
  }

  const chain = chainSlug(chainId);
  const targetPathRoutes = `/${chain}/api/v1/routes`;
  const targetPathBuild = `/${chain}/api/v1/route/build`;

  const routeReq = {
    params: {
      tokenIn: fromToken,
      tokenOut: toToken,
      amountIn: amount,
      onlyScalableSources: true,
    },
    headers: {
      "x-client-id": "ceres",
    },
  };

  try {
    const { data: routeResp } = await retryWithWait(() =>
      axios.get(AGGREGATOR_DOMAIN + targetPathRoutes, routeReq),
    );

    const routeSummary = routeResp.data.routeSummary;

    const buildBody = {
      routeSummary,
      sender: swapper,
      recipient: swapper,
      slippageTolerance: 100, // 1%
    };

    const { data: buildResp } = await retryWithWait(() =>
      axios.post(AGGREGATOR_DOMAIN + targetPathBuild, buildBody, {
        headers: { "x-client-id": "ceres" },
      }),
    );

    const tx = buildResp.data;
    if (!tx?.data) {
      throw new Error("Kyber build returned empty data");
    }

    // Dump full API responses for debugging
    const detailed = {
      inputParams: {
        chainId,
        swapType,
        fromToken,
        toToken,
        amount,
        swapper,
      },
      routeResponse: routeResp,
      buildResponse: buildResp,
    };

    return { detailed, raw: tx.data };
  } catch (error) {
    writeOutputs({}, error); // Write error details to file for debugging
    throw new Error(
      `Kyber API request failed: ${error.response?.data?.message ?? error.message}`,
    );
  }
}

export async function getSwapData(params) {
  const { detailed, raw } = await getKyberSwapData(params);
  return writeOutputs(detailed, raw);
}

export async function writeKyberSwapData(params) {
  const { detailed, raw } = await getKyberSwapData(params);
  return writeOutputs(detailed, raw);
}
