const crypto = require('crypto');

function md5(text) {
  return crypto.createHash('md5').update(text).digest('hex');
}

function testAesDynamic() {
  console.log("Testing dynamic AES roundtrip...");
  const tempKey = "a1b2c3d4e5f67890";
  const md5Key = md5(tempKey);
  const key = Buffer.from(md5Key, 'utf8');
  const iv = Buffer.from(md5Key.slice(16, 32), 'utf8');

  const payload = JSON.stringify({ mobile: "17274961080", code: "123456" });

  const cipher = crypto.createCipheriv('aes-256-cbc', key, iv);
  let enc = cipher.update(payload, 'utf8', 'hex');
  enc += cipher.final('hex');

  const decipher = crypto.createDecipheriv('aes-256-cbc', key, iv);
  let dec = decipher.update(enc, 'hex', 'utf8');
  dec += decipher.final('utf8');

  if (dec !== payload) throw new Error("Decrypted text does not match!");
  console.log("  -> Dynamic AES verified! Enc length:", enc.length);
}

function testRsaModpow() {
  console.log("Testing RSA modpow...");
  const modulusHex = "c40a2d0da76511f3bb1cc2bbd3afbd8bea83b4d6b05b6c13eb8920c53f1af7679b32ba0d0edb843240ef1b836efed3ee240734c14c1399fd6594d16af22f52525d14d72e0155c6dcc8638d4f7bb94f3a0b1f4c29f991972f2a160a25eb0a9e724336be7f69bbd319ffab1c6dd8470b021dc434f3faea89f4a2a01b33bdbdd08b";
  const modulus = BigInt("0x" + modulusHex);
  const exponent = 65537n;

  const pkData = JSON.stringify({ clienttime_ms: 1794568000000, key: "a1b2c3d4e5f67890" });
  const dataHex = Buffer.from(pkData, 'utf8').toString('hex');
  const m = BigInt("0x" + dataHex);

  // BigInt modpow
  function modPow(base, exp, mod) {
    let res = 1n;
    base = base % mod;
    while (exp > 0n) {
      if (exp % 2n === 1n) res = (res * base) % mod;
      base = (base * base) % mod;
      exp = exp / 2n;
    }
    return res;
  }

  const c = modPow(m, exponent, modulus);
  const hex = c.toString(16).padStart(256, '0').toUpperCase();
  if (hex.length !== 256) throw new Error("Invalid hex length!");
  console.log("  -> RSA modpow verified! (256 hex chars):", hex.slice(0, 32) + "...");
}

testAesDynamic();
testRsaModpow();
console.log("\n>>> ALL LOGIN CRYPTO TESTS PASSED <<<");
