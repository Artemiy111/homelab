#!/usr/bin/env bun
// Получить одноразовую ссылку для регистрации passkey (WebAuthn) у пользователя
// ZITADEL. Версия на Effect.ts v4.
//
// Зависимости: bun add effect@rc @effect/platform-bun@rc
//   bun apps/zitadel/zitadel-passkey-link-effect.ts
//
// Требует PAT администратора: переменная окружения ZITADEL_PAT или интерактивный ввод.

import { Data, Effect, FileSystem, Terminal } from "effect"
import { BunServices, BunRuntime } from "@effect/platform-bun"

// ─── Typed errors ────────────────────────────────────────────────────────────

class ScriptError extends Data.TaggedError("ScriptError")<{
  readonly message: string
}> { }

class ApiError extends Data.TaggedError("ApiError")<{
  readonly message: string
}> { }

class NoUsersFound extends Data.TaggedError("NoUsersFound")<{
  readonly target: string
}> { }

class InvalidInput extends Data.TaggedError("InvalidInput")<{
  readonly message: string
}> { }

type ScriptFailure = ScriptError | ApiError | NoUsersFound | InvalidInput

// ─── Terminal helpers ────────────────────────────────────────────────────────

const paint = (color: (s: string) => string, msg: string) =>
  Effect.gen(function* () {
    const terminal = yield* Terminal.Terminal
    yield* terminal.display(`\x1b[1m${color(msg)}\x1b[0m\n`)
  })

const info = (msg: string) => paint((s) => `\x1b[36m${s}`, msg)
const ok = (msg: string) => paint((s) => `\x1b[32m${s}`, msg)
const warn = (msg: string) => paint((s) => `\x1b[33m${s}`, msg)

const ask = (question: string) =>
  Effect.gen(function* () {
    const terminal = yield* Terminal.Terminal
    yield* terminal.display(question)
    const answer = yield* terminal.readLine
    return answer.trim()
  })

// ─── Config ──────────────────────────────────────────────────────────────────

interface ScriptConfig {
  readonly domain: string
  readonly host: string
  readonly apiBase: string
  readonly loginBase: string
  readonly pat: string
}

const readEnvFile = (path: string) =>
  Effect.gen(function* () {
    const fs = yield* FileSystem.FileSystem
    const exists = yield* fs.exists(path)
    if (!exists) return {}

    const content = yield* fs.readFileString(path)
    const entries: Record<string, string> = {}
    for (const line of content.split("\n")) {
      const match = line.match(/^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/)
      if (match?.[1] && match[2]) entries[match[1]!] = match[2].trim()
    }
    return entries
  })

const loadConfig = Effect.gen(function* () {
    const repoRoot = import.meta.dir + "/.."
    const domain = process.env.DOMAIN ?? "example.com"
    const host = process.env.ZITADEL_HOST ?? `id.${domain}`

    const apiBase = `https://${host}/v2`
    const loginBase = `https://${host}/ui/v2/login`

    let pat = process.env.ZITADEL_PAT ?? ""
    if (!pat) {
      const answer = yield* ask("PAT (Console → Users → <admin> → Personal Access Tokens): ")
      pat = answer
    }
    if (!pat) return yield* Effect.fail(new ScriptError({ message: "PAT не задан (переменная ZITADEL_PAT или интерактивный ввод)." }))

    return { domain, host, apiBase, loginBase, pat }
  })

// ─── API ─────────────────────────────────────────────────────────────────────

const api = (
  method: string,
  path: string,
  config: ScriptConfig,
  body?: unknown,
): Effect.Effect<Record<string, unknown>, ApiError> =>
  Effect.gen(function* () {
    const resp = yield* Effect.tryPromise({
      try: () =>
        fetch(`${config.apiBase}${path}`, {
          method,
          headers: {
            Authorization: `Bearer ${config.pat}`,
            ...(body !== undefined && { "Content-Type": "application/json" }),
          },
          body: body !== undefined ? JSON.stringify(body) : undefined,
        }),
      catch: () => new ApiError({ message: `HTTP-запрос к ${path} не удался` }),
    })

    const data = (yield* Effect.tryPromise({
      try: () => resp.json() as Promise<Record<string, unknown>>,
      catch: () => new ApiError({ message: `Не удалось разобрать ответ от ${path}` }),
    })) as Record<string, unknown>

    if (typeof data?.message === "string" && data.message !== "")
      return yield* Effect.fail(new ApiError({ message: data.message }))

    return data
  })

// ─── User search ─────────────────────────────────────────────────────────────

interface User {
  readonly userId: string
  readonly username: string
  readonly loginName: string
  readonly orgId: string
}

const buildUserQuery = (target: string) =>
  /^\d{5,}$/.test(target)
    ? { inUserIdsQuery: { userIds: [target] } }
    : { loginNameQuery: { loginName: target, method: "TEXT_QUERY_METHOD_CONTAINS_IGNORE_CASE" } }

const searchUsers = (target: string, config: ScriptConfig) =>
  Effect.gen(function* () {
    const data = yield* api("POST", "/users", config, { queries: [buildUserQuery(target)] })

    const result = data.result as Array<Record<string, unknown>> | undefined
    if (!result || result.length === 0)
      return yield* Effect.fail(new NoUsersFound({ target }))

    return result.map(
      (r): User => ({
        userId: r.userId as string,
        username: (r.username as string) ?? "",
        loginName: (r.preferredLoginName as string) ?? "",
        orgId: ((r.details as Record<string, unknown>)?.resourceOwner as string) ?? "",
      }),
    )
  })

const pickUser = (users: readonly User[]) =>
  Effect.gen(function* () {
    if (users.length === 1) {
      const u = users[0]!
      if (!u.userId || !u.orgId)
        return yield* Effect.fail(new ScriptError({ message: "не удалось определить user ID / organization ID." }))
      return u
    }

    yield* info("Найдено несколько пользователей:")
    users.forEach((u, i) =>
      Effect.runSync(Effect.log(`  ${i + 1}) ${u.username} (${u.loginName})  id=${u.userId}`)),
    )

    const answer = yield* ask("Номер: ")
    const idx = Number(answer)
    if (!Number.isInteger(idx) || idx < 1 || idx > users.length)
      return yield* Effect.fail(new InvalidInput({ message: "неверный номер." }))

    const u = users[idx - 1]!
    if (!u.userId || !u.orgId)
      return yield* Effect.fail(new ScriptError({ message: "не удалось определить user ID / organization ID." }))

    return u
  })

// ─── Passkey link ────────────────────────────────────────────────────────────

const generatePasskeyLink = (user: User, config: ScriptConfig) =>
  Effect.gen(function* () {
    const data = yield* api("POST", `/users/${user.userId}/passkeys/registration_link`, config, {
      returnCode: {},
    })

    const code = data.code as Record<string, string> | undefined
    if (!code?.id || !code?.code)
      return yield* Effect.fail(new ApiError({ message: "в ответе API нет кода." }))

    const url =
      `${config.loginBase}/passkey/set?` +
      new URLSearchParams({
        codeId: code.id,
        code: code.code,
        userId: user.userId,
        organization: user.orgId,
      })

    return url
  })

// ─── Main ────────────────────────────────────────────────────────────────────

const main = Effect.gen(
  function* () {
    const config = yield* loadConfig

    yield* info(`ZITADEL: https://${config.host}`)

    const target = yield* ask("Логин или user ID (например user или 386564404046479363): ")
    if (!target) return yield* Effect.fail(new InvalidInput({ message: "пустой ввод." }))

    const users = yield* searchUsers(target, config)
    const user = yield* pickUser(users)

    yield* info(`Пользователь: ${user.username || "<без username>"} (${user.loginName || "<без логина>"})`)
    yield* info(`user_id=${user.userId}  organization=${user.orgId}`)

    const url = yield* generatePasskeyLink(user, config)

    yield* ok("Ссылка для регистрации passkey:")
    yield* Effect.log(`\x1b[1m${url}\x1b[0m`)
    yield* Effect.log("")
    yield* warn(
      "Код одноразовый: ссылку надо открыть на том устройстве, где будет храниться passkey, " +
      "и пройти регистрацию до конца с первого раза (ZITADEL #12499).",
    )
  },
)

// ─── Run ─────────────────────────────────────────────────────────────────────

const handleError = (error: ScriptFailure) =>
  Effect.gen(function* () {
    const terminal = yield* Terminal.Terminal
    switch (error._tag) {
      case "ScriptError":
        yield* terminal.display(`\x1b[31mОшибка: ${error.message}\x1b[0m\n`)
        break
      case "ApiError":
        yield* terminal.display(`\x1b[31mОшибка API: ${error.message}\x1b[0m\n`)
        break
      case "NoUsersFound":
        yield* terminal.display(`\x1b[31mпользователь по "${error.target}" не найден.\x1b[0m\n`)
        break
      case "InvalidInput":
        yield* terminal.display(`\x1b[31mОшибка: ${error.message}\x1b[0m\n`)
        break
    }
    return Effect.sync(() => process.exit(1))
  })

BunRuntime.runMain(
  main.pipe(
    Effect.catchTag("ScriptError", handleError),
    Effect.catchTag("ApiError", handleError),
    Effect.catchTag("NoUsersFound", handleError),
    Effect.catchTag("InvalidInput", handleError),
    Effect.catch((error) =>
      Effect.gen(function* () {
        const terminal = yield* Terminal.Terminal
        yield* terminal.display(`\x1b[31mНеожиданная ошибка: ${String(error)}\x1b[0m\n`)
        return Effect.sync(() => process.exit(1))
      }),
    ),
    Effect.provide(BunServices.layer),
  ),
)
