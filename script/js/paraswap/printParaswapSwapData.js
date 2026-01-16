import { getParaswapSwapData } from "./paraswap.js";

async function main() {
  const args = process.argv.slice(2);
  if (args.length < 5) {
    console.error(
      "Usage: node printParaswapSwapData.js <chainId> <fromToken> <toToken> <amount> <swapper> [swapType=exactIn]",
    );
    process.exit(1);
  }

  const [chainId, fromToken, toToken, amount, swapper, swapTypeArg] = args;
  const swapType = swapTypeArg ?? "exactIn"; // use "exactOut" to build BUY

  try {
    const { raw } = await getParaswapSwapData({
      chainId,
      fromToken,
      toToken,
      amount,
      swapper,
      swapType,
    });

    // Print raw data for Foundry ffi consumption
    console.log(raw);
  } catch (err) {
    console.error("Failed to build Paraswap swap data:", err.message ?? err);
    process.exit(1);
  }
}

main();
