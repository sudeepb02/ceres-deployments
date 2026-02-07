import { getParaswapSwapData } from "./paraswap.js";
import { writeSwapOutputFiles } from "../common/fileUtils.js";
import path from "path";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

async function main() {
  const args = process.argv.slice(2);
  if (args.length < 7) {
    console.error(
      "Usage: node printParaswapSwapData.js <chainId> <fromToken> <toToken> <amount> <swapper> <fromTokenDecimals> <toTokenDecimals> [swapType=exactIn]",
    );
    process.exit(1);
  }

  const chainId = args[0];
  const fromToken = args[1];
  const toToken = args[2];
  const amount = args[3];
  const swapper = args[4];
  const fromTokenDecimals = args[args.length - 2];
  const toTokenDecimals = args[args.length - 1];
  const swapTypeArg = args.length > 7 ? args[5] : undefined;
  const swapType = swapTypeArg ?? "exactIn"; // use "exactOut" to build BUY

  try {
    const { detailed, raw } = await getParaswapSwapData({
      chainId,
      fromToken,
      toToken,
      amount,
      swapper,
      swapType,
      fromTokenDecimals,
      toTokenDecimals,
    });

    // Write debug output files
    writeSwapOutputFiles(__dirname, detailed, raw);

    // Print raw data for Foundry ffi consumption
    console.log(raw);
  } catch (err) {
    console.error("Failed to build Paraswap swap data:", err.message ?? err);
    process.exit(1);
  }
}

main();
