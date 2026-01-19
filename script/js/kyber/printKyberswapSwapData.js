import { getKyberSwapData } from "./kyberApiHelper.js";

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
    const { raw } = await getKyberSwapData({
      chainId,
      fromToken,
      toToken,
      amount,
      swapper,
      swapType,
    });
    console.log(raw);
  } catch (err) {
    console.error("Error fetching swap data:", err.message ?? err);
    process.exit(1);
  }
}

main();
