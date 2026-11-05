# Growblox Auto Farm

Auto farm block untuk Growblox (Roblox) — jalan di **Delta Executor**.

Alur: cari block terdekat → pindah ke block → break → tunggu item masuk inventory → ulang → berhenti otomatis kalau block habis.

## BACA DULU — Ini Bagian Pentingnya

Script ini **tidak** menyimpan nama RemoteEvent Growblox di dalamnya. Nama remote bisa berubah tiap update game, dan struktur internal Growblox tidak diketahui saat script ini ditulis.

Cara kerjanya:

1. **Auto-detect** — script menebak nama remote dari kata kunci (`break`, `destroy`, `dig`, `mine`, `hitblock`, dll) dan menebak block dari nama, ClassName, material, serta atribut.
2. **Fallback** — kalau RemoteEvent tidak ketemu, script mencoba mengaktifkan tool yang sedang dipegang, lalu terakhir mencoba klik pada posisi block.
3. **Manual** — kalau ketiganya gagal, isi `CONFIG.REMOTES` pakai hasil dari `Discovery.lua`.

**Kalau auto-detect meleset dan `CONFIG.REMOTES` masih kosong, script kemungkinan tidak bisa break apa pun.** Jalankan `Discovery.lua` dulu.

## Cara Pakai

### Cara Tercepat (1 baris)

`AutoFarm.lua` sudah **single-file** — UI ter-embed di dalamnya. Cukup satu loadstring, tidak perlu file lain:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/USERNAME/REPO/main/AutoFarm.lua"))()
```

Ganti `USERNAME/REPO` sesuai repo Anda. Selesai.

### Kalau auto-detect meleset

**Langkah 1 — Discovery**

1. Buka Growblox di Roblox.
2. Buka executor, tempel isi `Discovery.lua`, execute.
3. Buka tab **Console / Output**, copy hasilnya.
4. Cari baris `[RemoteEvent] ReplicatedStorage.XXX` — kandidat nama remote break-nya.

Discovery juga menampilkan struktur `workspace` (bagian `[3]`), kandidat block beserta material dan atributnya (bagian `[4]`), dan daftar tool di Backpack (bagian `[5]`).

**Langkah 2 — Konfigurasi**

Kalau perlu, edit bagian atas `AutoFarm.lua` lalu upload ulang:

```lua
REMOTES = {
    ["break"] = "NamaRemoteBreak",   -- dari hasil Discovery
    collect   = nil,                  -- isi kalau ada remote collect terpisah
    hit       = nil,                  -- isi kalau break butuh multi-hit
},
```

Kalau kamu sudah tahu container block-nya (misal `workspace.Blocks`), sesuaikan juga:

```lua
BLOCK_CONTAINERS = { "Blocks", "World" },
```

### Langkah 3 — Upload ke GitHub

`AutoFarm.lua` single-file, tapi `Discovery.lua` juga berguna di-upload.

```bash
cd growblox-autofarm
git init
git add .
git commit -m "Growblox auto farm"
git branch -M main
git remote add origin https://github.com/USERNAME/REPO.git
git push -u origin main
```

Ganti `USERNAME/REPO`, lalu di Roblox pakai:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/USERNAME/REPO/main/AutoFarm.lua"))()
```

## Kontrol

Setelah script jalan, ada UI dengan tombol:

- **MULAI / STOP AUTO FARM** — toggle loop
- **RESET STAT** — nolkan counter
- **SEMBUNYIKAN** — minimize UI, klik tombol `GB` untuk buka lagi
- **×** — tutup dan hentikan semua

Kontrol manual dari console Delta:

```lua
getgenv().GrowbloxAutoFarm.start()
getgenv().GrowbloxAutoFarm.stop()
getgenv().GrowbloxAutoFarm.reset()
getgenv().GrowbloxAutoFarm.status()   -- lihat counter
```

## Tuning

| Konfigurasi | Default | Keterangan |
|---|---|---|
| `MAX_DISTANCE` | 60 | Jarak maks block yang difarm (stud) |
| `ACTION_DELAY` | 0.35 | Jeda antar aksi. **Naikkan kalau kena kick anti-cheat** |
| `COLLECT_TIMEOUT` | 3 | Detik tunggu item masuk inventory |
| `TELEPORT_TO_BLOCK` | true | Teleport ke block sebelum break |
| `ANTI_AFK` | true | Cegah kick idle 20 menit |
| `IDLE_STRIKES_MAX` | 5 | Berhenti setelah N kali berturut-turut tidak ada block |
| `ACCEPT_ANY_PART_IN_CONTAINER` | true | Anggap semua Part di container sebagai block |

Kalau sering kena kick: naikkan `ACTION_DELAY` ke `0.6`–`1.0`, dan set `TELEPORT_TO_BLOCK = false` (teleport cepat itu paling mudah dideteksi).

## Troubleshooting

**Block tidak terdeteksi**
Isi `BLOCK_KEYWORDS` dan `BLOCK_CONTAINERS` pakai nama asli dari hasil Discovery bagian `[3]` dan `[4]`. Kalau nama block generik (`Part`, `1`, `2`), pastikan `ACCEPT_ANY_PART_IN_CONTAINER = true`.

**Break tidak ngefek (block tetap ada)**
Nama remote salah atau tidak ada sama sekali. Cek hasil Discovery bagian `[1]`, lalu isi `CONFIG.REMOTES["break"]` manual. Tanpa remote, script otomatis mencoba tool dan klik sebagai fallback.

**Item tidak terhitung**
`countInventory()` menghitung jumlah anak di Backpack + PlayerGui. Kalau Growblox pakai sistem inventory custom (item berupa nilai angka, bukan objek Instance), fungsi ini perlu diubah menyesuaikan game.

**UI tidak muncul**
Cek Console. Kalau ada `[WARN] [Growblox AutoFarm] UI gagal dibangun`, berarti ada error saat membangun UI — laporkan pesannya. Script tetap jalan tanpa UI.

**Script jalan tapi tidak ada yang terjadi**
Cek `getgenv().GrowbloxAutoFarm.status().lastError` untuk pesan terakhir.

## Struktur Repo

```
growblox-autofarm/
├── AutoFarm.lua        -- script utama, SINGLE-FILE (UI ter-embed)
├── UI.lua              -- sumber UI terpisah (referensi; AutoFarm.lua tidak butuh ini)
├── Discovery.lua       -- tool recon, jalankan sekali untuk cari nama remote
├── README.md
├── LICENSE
└── tests/              -- verifikasi otomatis (node, tidak dipakai di Roblox)
    ├── run_all.sh
    ├── check.js        -- syntax check (luaparse)
    ├── harness.js      -- jalankan AutoFarm di Lua asli dengan mock Roblox
    ├── harness_fallback.js
    └── harness_ui.js
```

## Verifikasi

`AutoFarm.lua` diuji dengan menjalankannya di Lua asli (fengari) terhadap mock Roblox API, bukan sekadar dicek sintaksnya:

```bash
npm install --no-save luaparse fengari
./tests/run_all.sh
```

Hasil pengujian:

| Tes | Hasil |
|---|---|
| Syntax valid (3 file) | PASS |
| 10 block terdeteksi dan terhancurkan | PASS (`broken=10`) |
| Remote break terpanggil | PASS (`breakCalls=10`) |
| Item terkumpul dan terhitung | PASS (`collected=10`) |
| Loop berhenti sendiri saat block habis | PASS (`runningAtEnd=false`) |
| Tidak infinite loop | PASS (`guard=35`) |
| Tetap jalan tanpa RemoteEvent (fallback) | PASS |
| UI terbangun tanpa error | PASS (51 Instance) |

## Catatan

- Script dibuat generik karena struktur internal Growblox tidak diketahui saat penulisan. Kalau auto-detect meleset, perbaiki via config — bukan dengan mengubah logika loop.
- Jangan pakai `ACTION_DELAY` di bawah 0.2. Kick anti-cheat biasanya datang dari burst request, bukan dari jumlah block yang di-break.
- `waitForCollect()` dibatasi waktu **dan** jumlah iterasi, supaya tidak hang kalau executor men-stub `os.clock()`.
- Key `["break"]` di `CONFIG.REMOTES` wajib pakai bracket karena `break` reserved word di Lua.
