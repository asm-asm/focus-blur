// App Store Connect API で Bundle ID を登録し、アプリが作成済みかを確認する。
// 使い方:
//   ASC_KEY_PATH=... ASC_KEY_ID=... ASC_ISSUER_ID=... node scripts/asc-register-bundle-id.mjs
import { createSign } from "node:crypto";
import { readFileSync } from "node:fs";

const BUNDLE_ID = "com.sammy.focusblur";
const NAME = "FocusBlur";

const { ASC_KEY_PATH, ASC_KEY_ID, ASC_ISSUER_ID } = process.env;
if (!ASC_KEY_PATH || !ASC_KEY_ID || !ASC_ISSUER_ID) {
  console.error("ASC_KEY_PATH / ASC_KEY_ID / ASC_ISSUER_ID を指定してください");
  process.exit(1);
}
const privateKey = readFileSync(ASC_KEY_PATH, "utf8");
function token() {
  const b64 = (obj) => Buffer.from(JSON.stringify(obj)).toString("base64url");
  const now = Math.floor(Date.now() / 1000);
  const header = b64({ alg: "ES256", kid: ASC_KEY_ID, typ: "JWT" });
  const payload = b64({ iss: ASC_ISSUER_ID, iat: now, exp: now + 15 * 60, aud: "appstoreconnect-v1" });
  const signer = createSign("SHA256");
  signer.update(`${header}.${payload}`);
  return `${header}.${payload}.${signer.sign({ key: privateKey, dsaEncoding: "ieee-p1363" }).toString("base64url")}`;
}
async function api(method, path, body) {
  const res = await fetch(`https://api.appstoreconnect.apple.com${path}`, {
    method,
    headers: { Authorization: `Bearer ${token()}`, "Content-Type": "application/json" },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  const json = text ? JSON.parse(text) : {};
  if (!res.ok) {
    const detail = (json.errors || []).map((e) => `${e.title}: ${e.detail}`).join(" / ");
    throw new Error(`${method} ${path} → ${res.status} ${detail}`);
  }
  return json;
}

const existing = await api("GET", `/v1/bundleIds?filter[identifier]=${BUNDLE_ID}`);
if (existing.data.some((b) => b.attributes.identifier === BUNDLE_ID)) {
  console.log(`Bundle ID: ${BUNDLE_ID} は登録済み`);
} else {
  await api("POST", "/v1/bundleIds", {
    data: { type: "bundleIds", attributes: { identifier: BUNDLE_ID, name: NAME, platform: "IOS" } },
  });
  console.log(`Bundle ID: ${BUNDLE_ID} を登録しました`);
}

const apps = await api("GET", `/v1/apps?filter[bundleId]=${BUNDLE_ID}`);
console.log(apps.data.length > 0
  ? `アプリ: 作成済み（${apps.data[0].attributes.name}）`
  : "アプリ: まだ作成されていません（App Store Connect の「新規App」で作成してください）");
