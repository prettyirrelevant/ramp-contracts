const { exec } = require("child_process");

const RAMP_CURVE_CONTRACT_ADDRESS =
  "0xf65330dc75e32b20be62f503a337cd1a072f898f";
const RAMP_TOKEN_SUPPLY = 1000000000000000000000000000n;

/**
 * Fetch tokens' information from the indexer.
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

  const url = "https://ramp-indexer.onrender.com";

  try {
    console.info("Fetching tokens from the GraphQL endpoint...");
    const response = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ query }),
    });

    if (!response.ok) {
      throw new Error(`Network response was not ok: ${response.statusText}`);
    }

    const json = await response.json();

    if (json.errors) {
      throw new Error(
        `GraphQL query error: ${json.errors.map((error) => error.message).join(", ")}`,
      );
    }

    console.info("Tokens fetched successfully.");
    return json.data.tokens.items;
  } catch (error) {
    console.error("Error fetching tokens:", error);
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
    console.info("Starting token verification process...");
    const tokensToVerify = await fetchTokens();

    for (const token of tokensToVerify) {
      const command = `forge verify-contract ${token.address} RampToken --watch --chain-id ${token.chainId} --constructor-args $(cast abi-encode "constructor(string,string,address,address,uint256)" "${token.name}" "${token.symbol}" "${RAMP_CURVE_CONTRACT_ADDRESS}" "${token.creator}" "${RAMP_TOKEN_SUPPLY}")`;
      exec(command, (error, stdout, stderr) => {
        if (error) {
          console.error("error --> ", error);
          return;
        }
        if (stderr) {
          console.error("error --> ", stderr);
          return;
        }

        console.info("info --> ", stdout);
      });
    }
  } catch (error) {
    console.error("Error during token verification process:", error);
    throw error;
  }
};

verifyTokens().then().catch();
