#!/bin/bash

set -euo pipefail

echo "=========================================="
echo "Verifying Soda API Key Configuration"
echo "=========================================="
echo ""

echo "--- Environment Variables Set ---"
echo "SODA_API_KEY_ID: ${SODA_API_KEY_ID:+SET (${#SODA_API_KEY_ID} chars)}${SODA_API_KEY_ID:-NOT SET}"
echo "SODA_API_KEY_SECRET: ${SODA_API_KEY_SECRET:+SET (${#SODA_API_KEY_SECRET} chars)}${SODA_API_KEY_SECRET:-NOT SET}"
echo ""
echo "SODA_IMAGE_APIKEY_ID: ${SODA_IMAGE_APIKEY_ID:+SET (${#SODA_IMAGE_APIKEY_ID} chars)}${SODA_IMAGE_APIKEY_ID:-NOT SET (will use SODA_API_KEY_ID)}"
echo "SODA_IMAGE_APIKEY_SECRET: ${SODA_IMAGE_APIKEY_SECRET:+SET (${#SODA_IMAGE_APIKEY_SECRET} chars)}${SODA_IMAGE_APIKEY_SECRET:-NOT SET (will use SODA_API_KEY_SECRET)}"
echo ""

echo "--- Key usage (per Soda docs) ---"
echo "SODA_API_KEY_ID / SODA_API_KEY_SECRET"
echo "  → Agent registration + Soda Cloud connection"
echo "  → MUST be from: Data Sources → Agents → New Soda Agent (copy from dialog)"
echo "  → NOT from: Profile → API Keys (human user keys → 403 Invalid user type)"
echo ""
echo "SODA_IMAGE_APIKEY_ID / SODA_IMAGE_APIKEY_SECRET (optional)"
echo "  → Pull images from registry.cloud.soda.io"
echo "  → If unset, agent keys above are used. Set only if Soda gave separate registry credentials."
echo ""

if [[ -z "${SODA_API_KEY_ID:-}" ]] || [[ -z "${SODA_API_KEY_SECRET:-}" ]]; then
    echo "❌ ERROR: SODA_API_KEY_ID or SODA_API_KEY_SECRET is not set!"
    echo "   Please set these environment variables with Service Account API keys"
    exit 1
else
    echo "✅ Both SODA_API_KEY_ID and SODA_API_KEY_SECRET are set"
fi

echo ""
echo "=========================================="
echo "Verification Complete"
echo "=========================================="
