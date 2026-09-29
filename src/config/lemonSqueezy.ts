export const config = {
  apiKey: process.env.LEMON_SQUEEZY_API_KEY,
  storeId: process.env.LEMON_SQUEEZY_STORE_ID,
  isRevoked: false, // Marked true after revocation
};

// Environment variables should be removed post-revocation
// LEMON_SQUEEZY_API_KEY=""
// LEMON_SQUEEZY_STORE_ID=""