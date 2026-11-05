const fs=require('fs'), luaparse=require('luaparse');
let fail=0;
for (const f of process.argv.slice(2)) {
  let src = fs.readFileSync(f,'utf8');
  // Luau: luaparse belum kenal compound assignment & beberapa sintaks Luau.
  // Strip komentar dulu supaya penanda Luau di komentar tidak ikut diuji.
  try {
    luaparse.parse(src, { luaVersion:'5.3' });
    console.log('OK   ' + f);
  } catch(e) {
    console.log('FAIL ' + f + ' :: ' + e.message.split('\n')[0]);
    fail=1;
  }
}
process.exit(fail);
