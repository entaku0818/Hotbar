#!/usr/bin/env ts-node
import { revokeApiKey, isKeyActive } from '../src/services/lemonSqueezy';

(async () => {
  try {
    const isActive = await isKeyActive();
    if (isActive) {
      console.log('Revoking unused Lemon Squeezy API key...');
      await revokeApiKey();
      console.log('✓ API key revoked successfully.');
    } else {
      console.log('✓ No active Lemon Squeezy API key found.');
    }
  } catch (error) {
    console.error('Error during cleanup:', error.message);
    process.exit(1);
  }
})();