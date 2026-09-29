import axios from 'axios';
import { config } from '../config/lemonSqueezy';

const API_URL = 'https://api.lemonsqueezy.com/v1';

/**
 * Revokes the unused Lemon Squeezy API key.
 * @throws {Error} If revocation fails
 */
export async function revokeApiKey(): Promise<void> {
  if (!config.apiKey || config.isRevoked) return;

  try {
    await axios.delete(`${API_URL}/api-keys/${config.apiKey}`, {
      headers: {
        Authorization: `Bearer ${config.apiKey}`,
        'Content-Type': 'application/json',
      },
    });
    config.isRevoked = true;
  } catch (error) {
    throw new Error('Failed to revoke Lemon Squeezy API key');
  }
}

/**
 * Validates if the key is still active (for cleanup verification).
 */
export async function isKeyActive(): Promise<boolean> {
  if (config.isRevoked) return false;

  try {
    await axios.get(`${API_URL}/me`, {
      headers: {
        Authorization: `Bearer ${config.apiKey}`,
      },
    });
    return true;
  } catch {
    return false;
  }
}