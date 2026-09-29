## Lemon Squeezy Migration Notes

**Post-migration cleanup:**
Run the revocation script to remove the unused API key:
```bash
npm run cleanup:lemon-squeezy
```

**Environment variables:**
Remove these from `.env` after revocation:
```env
LEMON_SQUEEZY_API_KEY=""
LEMON_SQUEEZY_STORE_ID=""
```