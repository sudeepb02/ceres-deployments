import { getKyberSwapData } from "./kyberApiHelper.js";
import { writeSwapOutputFiles } from "../common/fileUtils.js";
import path from "path";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

async function main() {
  const args = process.argv.slice(2);
  if (args.length < 5) {
    console.error(
      "Usage: node printAggregatorSwapData.js <chainId> <fromToken> <toToken> <amount> <swapper> [swapType=exactIn]",
    );
    process.exit(1);
  }

  const [chainId, fromToken, toToken, amount, swapper, swapTypeArg] = args;
  const swapType = swapTypeArg ?? "exactIn";

  if (BigInt(amount) === 0n) {
    console.error("Invalid amount: must be greater than 0", amount);
    process.exit(1);
  }

  try {
    const { detailed, raw } = await getKyberSwapData({
      chainId,
      fromToken,
      toToken,
      amount,
      swapper,
      swapType,
    });
    
    // Write debug output files
    writeSwapOutputFiles(__dirname, detailed, raw);
    
    console.log(raw);
  } catch (err) {
    console.error("Error fetching swap data:", err.message ?? err);
    process.exit(1);
  }
}

main();
