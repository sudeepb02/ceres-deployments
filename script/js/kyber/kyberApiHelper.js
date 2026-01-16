import axios from "axios";
import { writeFileSync } from "fs";
import path from "path";
import { fileURLToPath } from "url";

export const AGGREGATOR_DOMAIN = `https://aggregator-api.kyberswap.com`;
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

function requiredParam(params, key) {
  const value = params[key];
  if (value === undefined || value === null || value === "") {
    throw new Error(`Missing required param: ${key}`);
  }
  return value;
}

function writeOutputs(detailed, rawData) {
  const detailedPath = path.join(__dirname, "swapOutputDetailed.txt");
  const rawPath = path.join(__dirname, "swapOutputRaw.txt");

  writeFileSync(detailedPath, `${JSON.stringify(detailed, null, 2)}\n`);
  writeFileSync(rawPath, `${rawData}\n`);

  return { detailedPath, rawPath };
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

  const targetPathRoutes = `/${chainId}/api/v1/routes`;
  const targetPathBuild = `/${chainId}/api/v1/route/build`;

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

  const { data: routeResp } = await axios.get(
    AGGREGATOR_DOMAIN + targetPathRoutes,
    routeReq,
  );
  const routeSummary = routeResp.data.routeSummary;

  const buildBody = {
    routeSummary,
    sender: swapper,
    recipient: swapper,
    slippageTolerance: 100, // 1%
  };

  const { data: buildResp } = await axios.post(
    AGGREGATOR_DOMAIN + targetPathBuild,
    buildBody,
    {
      headers: { "x-client-id": "ceres" },
    },
  );

  const tx = buildResp.data;
  if (!tx?.data) {
    throw new Error("Kyber build returned empty data");
  }

  const detailed = {
    chainId,
    swapType,
    fromToken,
    toToken,
    amount,
    slippageBps: 100, // 1%
    router: tx.router,
    value: tx.value ?? "0",
    gas: tx.gas,
    data: tx.data,
  };

  return { detailed, raw: tx.data };
}

export async function getSwapData(params) {
  const { detailed, raw } = await getKyberSwapData(params);
  return writeOutputs(detailed, raw);
}

export async function writeKyberSwapData(params) {
  const { detailed, raw } = await getKyberSwapData(params);
  return writeOutputs(detailed, raw);
}
