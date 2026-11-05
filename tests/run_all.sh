#!/usr/bin/env bash
# Jalankan semua verifikasi. Butuh: node + npm install --no-save luaparse fengari
set -e
cd "$(dirname "$0")"
echo "=== 1. SYNTAX CHECK ==="
node check.js ../AutoFarm.lua ../UI.lua ../Discovery.lua
echo
echo "=== 2. FUNGSI UTAMA (10 block, ada remote) ==="
node harness.js 2>&1 | tail -12
echo
echo "=== 3. FALLBACK (tanpa remote) ==="
node harness_fallback.js 2>&1 | tail -10
echo
echo "=== 4. UI BUILD ==="
node harness_ui.js 2>&1 | tail -5
