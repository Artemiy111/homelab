#!/usr/bin/env npx tsx
// Получить одноразовую ссылку для регистрации passkey (WebAuthn) у пользователя
// ZITADEL. Портирование zitadel/zitadel-passkey-link.sh на TypeScript.
//
// Зависимости — только Node.js >= 18 (встроенный fetch) + tsx для запуска TS:
//   npx tsx zitadel/zitadel-passkey-link.ts
//
// Требует PAT администратора: переменная окружения ZITADEL_PAT или интерактивный ввод.

import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import * as readline from "node:readline/promises";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const repoRoot = join(scriptDir, "..");

function info(msg: string) {
  console.error(`\x1b[1;36m${msg}\x1b[0m`);
}
function ok(msg: string) {
  console.error(`\x1b[1;32m${msg}\x1b[0m`);
}
function warn(msg: string) {
  console.error(`\x1b[1;33m${msg}\x1b[0m`);
}
function die(msg: string): never {
  console.error(`\x1b[1;31mОшибка: ${msg}\x1b[0m`);
  process.exit(1);
}

const readEnvFile = (path: string): Record<string, string> => {
  try {
    const entries: Record<string, string> = {};
    for (const line of readFileSync(path, "utf8").split("\n")) {
      const m = line.match(/^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/);
      if (m) entries[m[1]] = m[2].trim();
    }
    return entries;
  } catch {
    return {};
  }
};

// grpc-gateway отдаёт ошибку и с кодом 200 — общий фильтр по .message.
async function api(method: string, path: string, pat: string, apiBase: string, body?: unknown): Promise<any> {
  const resp = await fetch(`${apiBase}${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${pat}`,
      ...(body !== undefined && { "Content-Type": "application/json" }),
    },
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  const data: any = await resp.json();
  if (typeof data?.message === "string" && data.message !== "") die(data.message);
  return data;
}

async function ask(rl: readline.Interface, question: string): Promise<string> {
  process.stderr.write(question);
  return (await rl.question("")).trim();
}

async function main() {
  const rootEnv = readEnvFile(join(repoRoot, ".env"));
  const serviceEnv = readEnvFile(join(scriptDir, ".env"));
  const domain = process.env.DOMAIN ?? rootEnv.DOMAIN ?? "example.com";
  const host = process.env.ZITADEL_HOST ?? serviceEnv.ZITADEL_HOST ?? `id.${domain}`;

  const apiBase = `https://${host}/v2`;
  const loginBase = `https://${host}/ui/v2/login`;

  let pat = process.env.ZITADEL_PAT ?? "";
  if (!pat) {
    const rl = readline.createInterface({ input: process.stdin, output: process.stderr, terminal: false });
    pat = await ask(rl, "PAT (Console → Users → <admin> → Personal Access Tokens): ");
    rl.close();
  }
  if (!pat) die("PAT не задан (переменная ZITADEL_PAT или интерактивный ввод).");

  info(`ZITADEL: https://${host}`);

  const rl = readline.createInterface({ input: process.stdin, output: process.stderr });
  const target = await ask(rl, "Логин или user ID (например user или 386564404046479363): ");
  if (!target) die("пустой ввод.");

  // Один вызов ListUsers на оба случая: число — точный поиск по ID,
  // иначе — подстрока логина без учёта регистра.
  const query = /^\d{5,}$/.test(target)
    ? { inUserIdsQuery: { userIds: [target] } }
    : { loginNameQuery: { loginName: target, method: "TEXT_QUERY_METHOD_CONTAINS_IGNORE_CASE" } };
  const users: Array<[string, string, string, string]> = (await api("POST", "/users", pat, apiBase, { queries: [query] }))
    .result?.map((r: any) => [r.userId, r.username ?? "", r.preferredLoginName ?? "", r.details?.resourceOwner ?? ""])
    ?? [];

  if (users.length === 0) die(`пользователь по "${target}" не найден.`);

  let user: [string, string, string, string];
  if (users.length === 1) {
    user = users[0];
  } else {
    info("Найдено несколько пользователей:");
    users.forEach(([uid, uname, ulogin], i) => console.error(`  ${i + 1}) ${uname} (${ulogin})  id=${uid}`));
    const choice = await ask(rl, "Номер: ");
    const idx = Number(choice);
    if (!Number.isInteger(idx) || idx < 1 || idx > users.length) die("неверный номер.");
    user = users[idx - 1];
  }
  const [userId, username, loginName, orgId] = user;

  if (!userId || !orgId) die("не удалось определить user ID / organization ID.");

  info(`Пользователь: ${username || "<без username>"} (${loginName || "<без логина>"})`);
  info(`user_id=${userId}  organization=${orgId}`);

  const code = (await api("POST", `/users/${userId}/passkeys/registration_link`, pat, apiBase, { returnCode: {} })).code ?? {};
  if (!code.id || !code.code) die("в ответе API нет кода.");

  const url = `${loginBase}/passkey/set?` + new URLSearchParams({ codeId: code.id, code: code.code, userId, organization: orgId });

  ok("Ссылка для регистрации passkey:");
  console.log(`\x1b[1m${url}\x1b[0m`);
  console.log();
  warn(
    "Код одноразовый: ссылку надо открыть на том устройстве, где будет храниться passkey, " +
      "и пройти регистрацию до конца с первого раза (ZITADEL #12499).",
  );

  rl.close();
}

await main();
