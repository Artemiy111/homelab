#!/usr/bin/env bun
import { createCipheriv, createDecipheriv } from "node:crypto"
import { parseArgs } from "node:util"

const MIIO_PORT = 54321
const MAGIC = 0x2131
const BROADCASTS = ["255.255.255.255", "192.0.2.10"]

type Packet = {
  ip: string
  deviceId: number
  stamp: number
  candidateToken: Buffer
}

function usage(): void {
  console.log(`Настройка штор Babai CMB5 (протокол miio, UDP ${MIIO_PORT}).

Команды:
  discover [--ip <адрес>] [--timeout <сек>]
      Опрос сети. В режиме сопряжения (после сброса) устройство отдаёт токен
      открыто — скрипт сразу проверяет его командой miIO.info.
  info --ip <адрес> --token <hex32>
      Проверка связи и токена: шлёт miIO.info и показывает ответ.
  assoc --ip <адрес> --token <hex32> --ssid <имя> --pass <пароль>
      Отдаёт устройству Wi-Fi-креды (miIO.config_router, при отказе пробует
      miIO.wifi_assoc). После успеха устройство покидает свой AP и подключается
      к домашней сети.
  -h | help
      Эта справка.

Примеры:
  bun curtain-setup.ts discover
  bun curtain-setup.ts discover --ip 192.0.2.10
  bun curtain-setup.ts assoc --ip 192.0.2.10 --token 8f3a... --ssid vlr24 --pass 'пароль'
`)
}

function helloPacket(): Buffer {
  const p = Buffer.alloc(32)
  p.writeUInt16BE(MAGIC, 0)
  p.writeUInt16BE(32, 2)
  return p
}

function parsePacket(buf: Buffer, ip: string): Packet | null {
  if (buf.length < 32 || buf.readUInt16BE(0) !== MAGIC) return null
  return {
    ip,
    deviceId: buf.readUInt32BE(8),
    stamp: buf.readUInt32BE(12),
    candidateToken: Buffer.from(buf.subarray(16, 32)),
  }
}

function encryptPayload(obj: unknown, token: Buffer): Buffer {
  const cipher = createCipheriv("aes-128-ecb", token, null)
  return Buffer.concat([cipher.update(JSON.stringify(obj), "utf8"), cipher.final()])
}

function decryptPayload(enc: Buffer, token: Buffer): any | null {
  try {
    const decipher = createDecipheriv("aes-128-ecb", token, null)
    return JSON.parse(Buffer.concat([decipher.update(enc), decipher.final()]).toString("utf8"))
  } catch {
    return null
  }
}

function buildCommand(method: string, params: unknown, deviceId: number, token: Buffer): Buffer {
  const data = encryptPayload({ id: Math.floor(Math.random() * 1e6), method, params }, token)
  const header = Buffer.alloc(16)
  header.writeUInt16BE(MAGIC, 0)
  header.writeUInt16BE(16 + data.length, 2)
  header.writeUInt32BE(deviceId, 8)
  header.writeUInt32BE(Math.floor(Date.now() / 1000), 12)
  const hasher = new Bun.CryptoHasher("md5")
  hasher.update(header)
  hasher.update(token)
  return Buffer.concat([header, hasher.digest(), data])
}

async function sendAndReceive(ip: string, packet: Buffer, timeoutMs: number): Promise<Buffer | null> {
  let resolve!: (data: Buffer | null) => void
  const done = new Promise<Buffer | null>((r) => (resolve = r))
  const sock = await Bun.udpSocket({
    socket: {
      data(_s, data, _port, address) {
        if (address === ip) resolve(data)
      },
      error() {
        resolve(null)
      },
    },
  })
  const timer = setTimeout(() => resolve(null), timeoutMs)
  sock.send(packet, MIIO_PORT, ip)
  const resp = await done
  clearTimeout(timer)
  sock.close()
  return resp
}

async function sendCommand(
  ip: string,
  token: Buffer,
  method: string,
  params: unknown,
  timeoutMs = 5000,
  knownDeviceId?: number,
): Promise<any | null> {
  let deviceId = knownDeviceId;
  if (!deviceId) {
    const hello = await sendAndReceive(ip, helloPacket(), timeoutMs);
    if (!hello) return null;
    deviceId = hello.readUInt32BE(8);
  }
  const resp = await sendAndReceive(ip, buildCommand(method, params, deviceId, token), timeoutMs);
  if (!resp || resp.length <= 32) return null;
  return decryptPayload(resp.subarray(32), token);
}

function parseToken(hex?: string): Buffer {
  if (!hex || !/^[0-9a-fA-F]{32}$/.test(hex)) {
    console.log("Токен должен быть 32 hex-символа (16 байт).")
    process.exit(1)
  }
  return Buffer.from(hex, "hex")
}

function tokenLooksUsable(t: Buffer): boolean {
  if (t.every((b) => b === 0) || t.every((b) => b === 0xff)) return false
  return true
}

async function discover(flags: Flags): Promise<void> {
  const timeoutSec = Number(flags.timeout ?? "10")
  const targets = flags.ip ? [flags.ip] : BROADCASTS
  const found = new Map<string, Packet>()
  const sock = await Bun.udpSocket({
    socket: {
      data(_s, data, _port, address) {
        const p = parsePacket(data, address)
        if (p && !found.has(address)) found.set(address, p)
      },
    },
  })
  sock.setBroadcast(true)
  const hello = helloPacket()
  for (const t of targets) sock.send(hello, MIIO_PORT, t)
  console.log(`Опрос ${targets.join(", ")} — жду ответов ${timeoutSec} с...`)
  await Bun.sleep(timeoutSec * 1000)
  sock.close()

  if (found.size === 0) {
    console.log("Никто не ответил. Если привод в режиме сопряжения — подключись к его Wi-Fi AP и повтори с --ip <адрес AP>.")
    return
  }

  for (const p of found.values()) {
    console.log(`\n${p.ip}  device_id=${p.deviceId}`)
    if (!tokenLooksUsable(p.candidateToken)) {
      console.log("  токен: не передан")
      continue
    }
    const probe = await sendCommand(p.ip, p.candidateToken, "miIO.info", [])
    if (probe?.result) {
      const r = probe.result
      console.log(`  токен: ${p.candidateToken.toString("hex")}  [подтверждён]`)
      console.log(`  модель: ${r.model ?? "?"}  прошивка: ${r.fw_ver ?? "?"}`)
    } else {
      console.log(`  ответ на байты 16–32: ${p.candidateToken.toString("hex")}`)
      console.log("  это НЕ токен (устройство уже привязано) либо токен не подтвердился")
    }
  }
}

async function deviceInfo(flags: Flags): Promise<void> {
  const token = parseToken(flags.token);
  if (!flags.ip) return usage();
  const did = flags.did ? Number(flags.did) : undefined;
  const resp = await sendCommand(flags.ip, token, "miIO.info", [], 5000, did);
  console.log(JSON.stringify(resp, null, 2));
}

async function assoc(flags: Flags): Promise<void> {
  if (!flags.ip || !flags.ssid || flags.pass === undefined) return usage()
  const token = parseToken(flags.token)
  const params = { ssid: flags.ssid, passwd: flags.pass, uid: 0 }
  console.log("Отправляю miIO.config_router...")
  let resp = await sendCommand(flags.ip, token, "miIO.config_router", params)
  if (!resp || JSON.stringify(resp).toLowerCase().includes("not found")) {
    console.log("Пробую miIO.wifi_assoc...")
    resp = await sendCommand(flags.ip, token, "miIO.wifi_assoc", params)
  }
  console.log(JSON.stringify(resp, null, 2))
  const ok = JSON.stringify(resp).includes("ok")
  console.log(
    ok
      ? "Устройство принялось настраивать Wi-Fi. Через 20–30 с проверь: discover --ip <домашний IP> или info."
      : "Устройство не подтвердило настройку — см. ответ выше.",
  )
}

const [cmd, ...rest] = process.argv.slice(2)
const { values } = parseArgs({
  args: rest,
  options: {
    ip: { type: "string" },
    token: { type: "string" },
    ssid: { type: "string" },
    pass: { type: "string" },
    timeout: { type: "string", default: "10" },
  },
  allowPositionals: true,
  strict: false,
})

type Flags = {
  ip?: string
  token?: string
  ssid?: string
  pass?: string
  timeout?: string
}

function asString(v: string | boolean | undefined): string | undefined {
  return typeof v === "string" ? v : undefined
}

const flags: Flags = {
  ip: asString(values.ip),
  token: asString(values.token),
  ssid: asString(values.ssid),
  pass: asString(values.pass),
  timeout: asString(values.timeout),
}

switch (cmd) {
  case "discover":
    await discover(flags)
    break
  case "info":
    await deviceInfo(flags)
    break
  case "assoc":
    await assoc(flags)
    break
  default:
    usage()
}
