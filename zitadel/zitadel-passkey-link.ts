#!/usr/bin/env bun
// Получить одноразовую ссылку для регистрации passkey (WebAuthn) у пользователя
// ZITADEL. Портирование zitadel/zitadel-passkey-link.sh на TypeScript.
//
// Зависимости — только Bun (нативные Bun.file и prompt):
//   bun zitadel/zitadel-passkey-link.ts
//
// Требует PAT администратора: переменная окружения ZITADEL_PAT или интерактивный ввод.

const scriptDir = import.meta.dir;
const repoRoot = `${scriptDir}/..`;

// Bun.color отдаёт пустую строку вне TTY — цвета сами отключаются при пайпе.
const paint = (color: string, msg: string) => console.error(`\x1b[1m${Bun.color(color, "ansi-16")}${msg}\x1b[0m`);
function info(msg: string) {
  paint("cyan", msg);
}
function ok(msg: string) {
  paint("green", msg);
}
function warn(msg: string) {
  paint("yellow", msg);
}
function die(msg: string): never {
  paint("red", `Ошибка: ${msg}`);
  process.exit(1);
}

const readEnvFile = async (path: string): Promise<Record<string, string>> => {
  const file = Bun.file(path);
  if (!(await file.exists())) return {};
  const entries: Record<string, string> = {};
  for (const line of (await file.text()).split("\n")) {
    const [, key, value] = line.match(/^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/) ?? [];
    if (key && value) entries[key] = value.trim();
  }
  return entries;
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

function ask(question: string): string {
  const answer = prompt(question);
  return (answer ?? "").trim();
}

async function main() {
  const rootEnv = await readEnvFile(`${repoRoot}/.env`);
  const serviceEnv = await readEnvFile(`${scriptDir}/.env`);
  const domain = process.env.DOMAIN ?? rootEnv.DOMAIN ?? "example.com";
  const host = process.env.ZITADEL_HOST ?? serviceEnv.ZITADEL_HOST ?? `id.${domain}`;

  const apiBase = `https://${host}/v2`;
  const loginBase = `https://${host}/ui/v2/login`;

  let pat = process.env.ZITADEL_PAT ?? "";
  if (!pat) pat = ask("PAT (Console → Users → <admin> → Personal Access Tokens): ");
  if (!pat) die("PAT не задан (переменная ZITADEL_PAT или интерактивный ввод).");

  info(`ZITADEL: https://${host}`);

  const target = ask("Логин или user ID (например user или 386564404046479363): ");
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
    const u = users[0];
    if (!u) die("не удалось прочитать результат поиска.");
    user = u;
  } else {
    info("Найдено несколько пользователей:");
    users.forEach(([uid, uname, ulogin], i) => console.error(`  ${i + 1}) ${uname} (${ulogin})  id=${uid}`));
    const idx = Number(ask("Номер: "));
    if (!Number.isInteger(idx) || idx < 1 || idx > users.length) die("неверный номер.");
    const u = users[idx - 1];
    if (!u) die("неверный номер.");
    user = u;
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
}

await main();
