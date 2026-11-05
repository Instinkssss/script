# Growblox Auto Farm

Auto farm block untuk Growblox (Roblox) — jalan di **Delta Executor**.

Alur: cari block terdekat → pindah ke block → break → tunggu item masuk inventory → ulang → berhenti otomatis kalau block habis.

UI bergaya JunnzxyHub (hitam + cyan), ter-embed di satu file. Tersedia mode sapuan: Break Kiri/Kanan, Break 3 Arah, Plant, Auto Trash.

## BACA DULU — Ini Bagian Pentingnya

Script ini **tidak** menyimpan nama RemoteEvent Growblox di dalamnya. Nama remote bisa berubah tiap update game, dan struktur internal Growblox tidak diketahui saat script ini ditulis.

Cara kerjanya:

1. **Auto-detect** — script menebak nama remote dari kata kunci (`break`, `destroy`, `dig`, `mine`, `hitblock`, dll) dan menebak block dari nama, ClassName, material, serta atribut.
2. **Fallback** — kalau RemoteEvent tidak ketemu, script mencoba mengaktifkan tool yang sedang dipegang, lalu terakhir mencoba klik pada posisi block.
3. **Manual** — kalau ketiganya gagal, isi `CONFIG.REMOTES` pakai hasil dari `Discovery.lua`.

**Kalau auto-detect meleset dan `CONFIG.REMOTES` masih kosong, script kemungkinan tidak bisa break apa pun.** Jalankan `Scout.lua` dulu.

## Cara Pakai

### Cara Tercepat (1 baris)

`AutoFarm.lua` sudah **single-file** — UI ter-embed di dalamnya. Cukup satu loadstring, tidak perlu file lain:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/USERNAME/REPO/main/AutoFarm.lua"))()
```

Ganti `USERNAME/REPO` sesuai repo Anda. Selesai.

### Kalau auto-detect meleset

**Langkah 1 — Scout**

1. Buka Growblox di Roblox.
2. Buka executor, tempel isi `Scout.lua`, execute.
3. Buka tab **Console / Output**, copy hasilnya.

Scout menampilkan 10 bagian:

| Bagian | Isi |
|---|---|
| 0 | PlaceId, GameId, nama game, waktu |
| 1 | Semua RemoteEvent/RemoteFunction + kandidat kuat (nama mengandung break/place/collect) |
| 2 | Struktur workspace dua level |
| 3 | Analisa block: ClassName, Material, pola nama, atribut |
| 4 | Detail 8 block (Size, Position, Material, Atribut, Children) |
| 5 | Deteksi grid — jarak antar Part yang paling sering muncul |
| 6 | Inventory: Backpack, leaderstats, atribut Player |
| 7 | Tool di tangan + isinya |
| 8 | Daftar pemain |
| 9 | ScreenGui di PlayerGui |

Kalau executor punya `writefile()`, hasilnya juga disimpan ke `growblox_scout.txt`.

**Langkah 2 — Konfigurasi**

Kalau perlu, edit bagian atas `AutoFarm.lua` lalu upload ulang:

```lua
REMOTES = {
    ["break"] = "NamaRemoteBreak",   -- dari hasil Scout
    collect   = nil,                  -- isi kalau ada remote collect terpisah
    hit       = nil,                  -- isi kalau break butuh multi-hit
    place     = nil,                  -- untuk mode Plant
    trash     = nil,                  -- untuk mode Auto Trash
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

UI muncul di sisi kiri layar: hitam dengan aksen cyan, judul `JunnzxyHub`, subjudul `Farm Auto DF-Tools`.

| Baris | Kontrol | Fungsi |
|---|---|---|
| Farm | START / STOP | Jalankan atau hentikan loop utama |
| AutoDF | toggle | Auto ambil item yang jatuh |
| Break Kiri | toggle | Sapu block ke arah kiri (sumbu -X) |
| Break Kanan | toggle | Sapu block ke arah kanan (sumbu +X) |
| Break 3 Arah | toggle | Hancurkan cluster dalam radius 8 stud sekaligus |
| Plant | toggle | Tanam ulang setelah break |
| Auto Trash | toggle | Buang item sampah saat inventory ≥ 25 |

Di bawah daftar ada baris statistik `Block / Item / Target`, lalu status `Auto DF: Berhenti.` atau `Auto DF: Berjalan...`.

Tombol `×` menutup dan menghentikan semuanya. Klik kanan di header untuk sembunyikan UI, tombol `DF` di kiri layar untuk memunculkan lagi. Panel bisa digeser dengan drag.

Kontrol manual dari console Delta:

```lua
local G = getgenv().GrowbloxAutoFarm
G.start()
G.stop()
G.toggle()
G.reset()
G.status()                  -- lihat counter + lastError
G.setMode("threeWay", true) -- nyalakan mode dari script
G.getMode("threeWay")
G.setAutoCollect(false)
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
| `MAX_BLOCK_FAILS` | 3 | Lewati block yang gagal dihancurkan N kali |
| `ACCEPT_ANY_PART_IN_CONTAINER` | true | Anggap semua Part di container sebagai block |
| `THREE_WAY_RADIUS` | 8 | Radius cluster mode Break 3 Arah (stud) |
| `THREE_WAY_LIMIT` | 12 | Maksimum block per cluster |
| `SWEEP_LENGTH` | 6 | Berapa block disapu per arah |
| `TRASH_THRESHOLD` | 25 | Buang sampah kalau inventory ≥ nilai ini |
| `JUNK_KEYWORDS` | dirt, soil, rock, ... | Nama item yang dianggap sampah |

Kalau sering kena kick: naikkan `ACTION_DELAY` ke `0.6`–`1.0`, dan set `TELEPORT_TO_BLOCK = false` (teleport cepat itu paling mudah dideteksi).

## Troubleshooting

**Block tidak terdeteksi**
Isi `BLOCK_KEYWORDS` dan `BLOCK_CONTAINERS` pakai nama asli dari hasil Scout bagian `[3]` dan `[4]`. Kalau nama block generik (`Part`, `1`, `2`), pastikan `ACCEPT_ANY_PART_IN_CONTAINER = true`.

**Break tidak ngefek (block tetap ada)**
Nama remote salah atau tidak ada sama sekali. Cek hasil Scout bagian `[1]`, lalu isi `CONFIG.REMOTES["break"]` manual. Tanpa remote, script otomatis mencoba tool dan klik sebagai fallback.

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
├── Scout.lua           -- tool recon, jalankan sekali untuk cari nama remote
├── Discovery.lua       -- versi ringkas recon (opsional)
├── FarmUI.lua          -- sumber UI terpisah (referensi; AutoFarm.lua tidak butuh ini)
├── UI.lua              -- UI versi lama (referensi)
├── README.md
├── LICENSE
└── tests/              -- verifikasi otomatis (node, tidak dipakai di Roblox)
    ├── run_all.sh
    ├── check.js            -- syntax check (luaparse)
    ├── harness.js          -- jalankan AutoFarm di Lua asli dengan mock Roblox
    ├── harness_fallback.js -- tes tanpa RemoteEvent
    ├── harness_ui.js
    ├── run_integration.js  -- UI ter-embed + API + setMode/getMode
    ├── run_modes.js        -- 6 kombinasi mode sapuan
    └── run_ui_test.js      -- FarmUI standalone
```

## Verifikasi

`AutoFarm.lua` diuji dengan menjalankannya di Lua asli (fengari) terhadap mock Roblox API, bukan sekadar dicek sintaksnya.

```bash
npm install --no-save luaparse fengari
bash tests/run_all.sh
```

6 suite, semuanya PASS:

| Suite | Isi | Hasil |
|---|---|---|
| 1. Syntax | 4 file (AutoFarm, FarmUI, UI, Scout) | PASS |
| 2. Fungsi utama | 10 block terdeteksi + terhancurkan | PASS (`broken=10`, `breakCalls=10`) |
| | Item terkumpul dan terhitung | PASS (`collected=10`) |
| | Berhenti sendiri saat block habis | PASS (`runningAtEnd=false`) |
| | Tidak infinite loop | PASS (`guard=45`) |
| 3. Fallback | Jalan tanpa RemoteEvent, via tool | PASS (`broken=10`) |
| 4. UI FarmUI | Bangun UI standalone | PASS (107 Instance) |
| 5. Integrasi | UI ter-embed di AutoFarm + API | PASS (107 Instance) |
| | `setMode` ↔ `getMode` konsisten | PASS |
| 6. Mode sapuan | 6 kombinasi mode, tidak crash/hang | PASS |

Catatan penting: semua ini dijalankan di **mock Roblox**, bukan di game Growblox asli. Yang terbukti adalah loop, UI, dan logika mode bekerja. Yang belum terbukti adalah nama RemoteEvent dan struktur block Growblox yang sebenarnya — itu tugas `Scout.lua`.

### Tiga bug nyata yang ditemukan lewat tes ini

1. **`findClusterAround` selalu berhenti di iterasi pertama.** Ekspresi `#result >= LIMIT or 12` di-parse Lua sebagai `(...) or 12`, dan `12` selalu truthy. Akibatnya cluster hanya berisi 1 block, bukan maksimal 12.
2. **`breakBlock` mengembalikan `true` tanpa bukti.** Loop menganggap block mati padahal masih hidup, lalu memilih target yang sama terus-menerus — macet permanen. Sekarang `breakBlock` memverifikasi: `true` hanya kalau `isDead(block) or not block.Parent`.
3. **Mode Break 3 Arah melewatkan target itu sendiri.** `findClusterAround` mengecualikan `center`, jadi block terdekat tidak pernah dihancurkan.

Ditambah `MAX_BLOCK_FAILS = 3` supaya block yang tidak bisa dihancurkan dilewati, bukan diulang tanpa henti.

## Catatan

- Script dibuat generik karena struktur internal Growblox tidak diketahui saat penulisan. Kalau auto-detect meleset, perbaiki via config — bukan dengan mengubah logika loop.
- Jangan pakai `ACTION_DELAY` di bawah 0.2. Kick anti-cheat biasanya datang dari burst request, bukan dari jumlah block yang di-break.
- `waitForCollect()` dibatasi waktu **dan** jumlah iterasi, supaya tidak hang kalau executor men-stub `os.clock()`.
- Key `["break"]` di `CONFIG.REMOTES` wajib pakai bracket karena `break` reserved word di Lua.
