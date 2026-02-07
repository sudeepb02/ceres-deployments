import { writeFileSync } from "fs";
import path from "path";

/**
 * Writes swap data to debug output files
 * @param {string} outputDir - Directory where files should be written
 * @param {object} detailed - Detailed swap information object
 * @param {string} raw - Raw calldata string
 * @returns {object} Object with paths to created files
 */
export function writeSwapOutputFiles(outputDir, detailed, raw) {
  const detailedPath = path.join(outputDir, "swapOutputDetailed.txt");
  const rawPath = path.join(outputDir, "swapOutputRaw.txt");

  writeFileSync(detailedPath, `${JSON.stringify(detailed, null, 2)}\n`);
  writeFileSync(rawPath, `${raw}\n`);

  return { detailedPath, rawPath };
}
