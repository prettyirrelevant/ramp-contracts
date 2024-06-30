#!/usr/bin/env node

const { promisify } = require("util");
const { exec: execCallback } = require("child_process");
const exec = promisify(execCallback);

const RAMP_CURVE_FRAXTAL_CONTRACT_ADDRESS =
  "0xD62BfbF2050e8fEAD90e32558329D43A6efce4C8";
const RAMP_CURVE_BASE_CONTRACT_ADDRESS =
  "0xFA598e9Bd1970E0cB42b1e23549A6d5436680b51";
const RAMP_TOKEN_SUPPLY = 1000000000000000000000000000n;
const INDEXER_URL = "https://ramp-indexer.up.railway.app";

const log = {
  info: (message) => console.log(`info: ${message.toLowerCase()}`),
  error: (message) => console.error(`error: ${message.toLowerCase()}`),
  warn: (message) => console.warn(`warn: ${message.toLowerCase()}`),
};

/**
 * Retrieves all tokens launched by the Ramp.fun contract from the indexer.
 * @returns {Promise<{id: string, name: string, symbol: string, address: string, creator: string, chainId: string}[]>} The fetched token information.
 * @throws {Error} If there is a network error or a GraphQL query error.
 */
const fetchTokens = async () => {
  const query = `
  {
    tokens {
      items {
        name
        symbol
        address
        creator
        chainId
      }
    }
  }
  `;

  try {
    log.info("fetching tokens from the graphql endpoint...");
    const response = await fetch(INDEXER_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ query }),
    });

    if (!response.ok) {
      throw new Error(`network response was not ok: ${response.statusText}`);
    }

    const json = await response.json();
    if (json.errors) {
      throw new Error(
        `graphql query error: ${json.errors.map((error) => error.message).join(", ")}`,
      );
    }

    log.info("tokens fetched successfully");
    return json.data.tokens.items;
  } catch (error) {
    log.error(`error fetching tokens: ${error.message}`);
    throw error;
  }
};

/**
 * Verifies a single token.
 * @param {Object} token - The token to verify.
 * @returns {Promise<void>} Resolves when the verification is complete.
 * @throws {Error} If there is an error during verification.
 */
const verifyToken = async (token) => {
  const command = `forge verify-contract ${token.address} RampToken --watch --chain-id ${token.chainId} --constructor-args $(cast abi-encode "constructor(string,string,address,address,uint256)" "${token.name}" "${token.symbol}" "${token.chainId === 84532 ? RAMP_CURVE_BASE_CONTRACT_ADDRESS : RAMP_CURVE_FRAXTAL_CONTRACT_ADDRESS}" "${token.creator}" "${RAMP_TOKEN_SUPPLY}")`;

  log.info(
    `verifying token: ${token.name} (${token.symbol}) chainId=${token.chainId}`,
  );
  log.info(`executing command: ${command}`);

  try {
    const { stdout, stderr } = await exec(command);
    log.info(`command output: ${stdout.trim()}`);
    if (stderr) {
      log.warn(`command stderr: ${stderr.trim()}`);
    }
  } catch (error) {
    log.error(`error verifying token ${token.name}: ${error.message}`);
    throw error;
  }
};

/**
 * Verifies tokens by encoding their constructor arguments according to the Ethereum ABI specification.
 * @returns {Promise<void>} Resolves when the verification is complete.
 * @throws {Error} If there is an error fetching or encoding tokens.
 */
const verifyTokens = async () => {
  try {
    log.info("starting token verification process...");
    const tokensToVerify = await fetchTokens();

    for (const token of tokensToVerify) {
      await verifyToken(token);
    }
  } catch (error) {
    log.error(`error during token verification process: ${error.message}`);
    process.exit(1);
  }
};

// Run the script
if (require.main === module) {
  verifyTokens();
}
