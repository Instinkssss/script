#!/usr/bin/env bash
# Jalankan semua verifikasi. Butuh: node + npm install --no-save luaparse fengari
set -e
cd "$(dirname "$0")"
echo "=== 1. SYNTAX CHECK ==="
node check.js ../AutoFarm.lua ../FarmUI.lua ../UI.lua ../Scout.lua ../GrowbloxAllInOne.lua
echo
echo "=== 2. FUNGSI UTAMA (10 block, ada remote) ==="
node harness.js 2>&1 | tail -12
echo
echo "=== 3. FALLBACK (tanpa remote) ==="
node harness_fallback.js 2>&1 | tail -10
echo
echo "=== 4. UI BUILD ==="
node harness_ui.js 2>&1 | tail -5
echo
echo "=== 5. UI TER-EMBED DI AUTOFARM ==="
node run_integration.js 2>&1 | grep -E "^(PASS|FAIL|ALL)"
echo
echo "=== 6. MODE SAPUAN (threeWay/sweep/plant/trash) ==="
node run_modes.js 2>&1 | grep -E "^(PASS|FAIL|ALL)"
echo
echo "=== 7. ALL-IN-ONE (Scout + Farm + UI jadi satu file) ==="
node run_allinone.js 2>&1 | grep -E "^(PASS|FAIL|ALL)"
echo
echo "=== 8. TOMBOL START (diagnostik + loop jalan) ==="
node run_start.js 2>&1 | grep -E "^(PASS|FAIL|ALL)"
