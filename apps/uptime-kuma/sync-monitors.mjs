import { readFile } from "node:fs/promises";
import process from "node:process";
import { pathToFileURL } from "node:url";

const DEFAULT_MONITOR = {
  active: true,
  parent: null,
  method: "GET",
  interval: 60,
  retryInterval: 60,
  timeout: 48,
  resendInterval: 0,
  maxretries: 2,
  retryOnlyOnStatusCodeFailure: false,
  notificationIDList: {},
  ignoreTls: false,
  upsideDown: false,
  expiryNotification: false,
  domainExpiryNotification: false,
  maxredirects: 10,
  accepted_statuscodes: ["200-299"],
  saveResponse: false,
  saveErrorResponse: true,
  responseMaxLength: 1024,
  dns_resolve_type: "A",
  dns_resolve_server: "",
  ipFamily: null,
  proxyId: null,
  basic_auth_user: "",
  basic_auth_pass: "",
  bearer_token: "",
  authMethod: null,
  httpBodyEncoding: "json",
  kafkaProducerBrokers: [],
  kafkaProducerSaslOptions: { mechanism: "None" },
  kafkaProducerSsl: false,
  kafkaProducerAllowAutoTopicCreation: false,
  rabbitmqNodes: [],
  conditions: [],
};

const ALLOWED_TYPES = new Set(["http", "dns", "ping", "port"]);
const COMMON_MANAGED_FIELDS = [
  "active",
  "description",
  "interval",
  "maxretries",
  "retryInterval",
  "timeout",
  "resendInterval",
];
const TYPE_MANAGED_FIELDS = {
  http: ["url", "method", "accepted_statuscodes", "maxredirects"],
  dns: ["hostname", "dns_resolve_server", "dns_resolve_type"],
  ping: ["hostname"],
  port: ["hostname", "port"],
};

function fail(message) {
  throw new Error(message);
}

const DOMAIN_PLACEHOLDER = /\{\{\s*DOMAIN\s*\}\}/g;
const SERVER_IP_PLACEHOLDER = /\{\{\s*SERVER_IP\s*\}\}/g;

function expandDomain(value, domain) {
  if (typeof value !== "string" || !value.includes("{{DOMAIN}}")) {
    return value;
  }
  if (!domain) {
    fail("В monitors.json используется {{DOMAIN}}, но переменная DOMAIN не задана.");
  }
  return value.replace(DOMAIN_PLACEHOLDER, domain);
}

function expandServerIp(value, serverIp) {
  if (typeof value !== "string" || !value.includes("{{SERVER_IP}}")) {
    return value;
  }
  if (!serverIp) {
    fail("В monitors.json используется {{SERVER_IP}}, но переменная SERVER_IP не задана.");
  }
  return value.replace(SERVER_IP_PLACEHOLDER, serverIp);
}

export async function loadConfig(filePath, domain = process.env.DOMAIN, serverIp = process.env.SERVER_IP) {
  const source = await readFile(filePath, "utf8");
  let config;

  try {
    config = JSON.parse(source);
  } catch (error) {
    fail(`Не удалось прочитать ${filePath}: ${error.message}`);
  }

  if (config.version !== 1) {
    fail(`Неподдерживаемая версия конфигурации: ${config.version}`);
  }
  if (!Array.isArray(config.monitors)) {
    fail("Поле monitors должно быть массивом.");
  }

  const names = new Set();
  const monitors = config.monitors.map((monitor, index) => {
    if (!monitor || typeof monitor !== "object" || Array.isArray(monitor)) {
      fail(`Монитор №${index + 1} должен быть объектом.`);
    }
    if (!monitor.name || typeof monitor.name !== "string") {
      fail(`У монитора №${index + 1} отсутствует имя.`);
    }
    if (names.has(monitor.name)) {
      fail(`Имя монитора повторяется: ${monitor.name}`);
    }
    names.add(monitor.name);

    if (!ALLOWED_TYPES.has(monitor.type)) {
      fail(`Монитор ${monitor.name}: неподдерживаемый тип ${monitor.type}.`);
    }
    if (monitor.type === "http" && !monitor.url) {
      fail(`Монитор ${monitor.name}: для HTTP требуется url.`);
    }
    if (["dns", "ping", "port"].includes(monitor.type) && !monitor.hostname) {
      fail(`Монитор ${monitor.name}: для типа ${monitor.type} требуется hostname.`);
    }
    if (monitor.type === "port" && !Number.isInteger(monitor.port)) {
      fail(`Монитор ${monitor.name}: для TCP-порта требуется целочисленный port.`);
    }

    const merged = { ...DEFAULT_MONITOR, ...monitor };
    merged.url = expandServerIp(expandDomain(merged.url, domain), serverIp);
    merged.hostname = expandServerIp(expandDomain(merged.hostname, domain), serverIp);
    merged.dns_resolve_server = expandServerIp(expandDomain(merged.dns_resolve_server, domain), serverIp);
    return merged;
  });

  return { version: config.version, monitors };
}

function emitWithAck(socket, event, ...args) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      reject(new Error(`Uptime Kuma не ответила на событие ${event}.`));
    }, 15_000);

    socket.emit(event, ...args, (response) => {
      clearTimeout(timer);
      if (!response?.ok) {
        reject(new Error(response?.msg || `Событие ${event} завершилось ошибкой.`));
        return;
      }
      resolve(response);
    });
  });
}

function createMonitorListWaiter(socket) {
  let finish;
  const promise = new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      socket.off("monitorList", onMonitorList);
      reject(new Error("Uptime Kuma не прислала список мониторов."));
    }, 15_000);

    finish = () => {
      clearTimeout(timer);
      socket.off("monitorList", onMonitorList);
      resolve(null);
    };

    function onMonitorList(monitors) {
      clearTimeout(timer);
      resolve(monitors);
    }

    socket.once("monitorList", onMonitorList);
  });

  return { promise, cancel: () => finish() };
}

async function getMonitorList(socket) {
  const waiter = createMonitorListWaiter(socket);
  try {
    await emitWithAck(socket, "getMonitorList");
    return await waiter.promise;
  } catch (error) {
    waiter.cancel();
    throw error;
  }
}

function managedFields(monitor) {
  return ["name", "type", ...COMMON_MANAGED_FIELDS, ...TYPE_MANAGED_FIELDS[monitor.type]];
}

function comparableValue(value) {
  if (value === undefined) return null;
  if (typeof value === "number") return String(value);
  return JSON.stringify(value);
}

export function needsUpdate(current, desired) {
  return managedFields(desired).some(
    (field) => comparableValue(current[field]) !== comparableValue(desired[field]),
  );
}

function applyManagedFields(current, desired) {
  const updated = { ...current };
  for (const field of managedFields(desired)) {
    updated[field] = desired[field];
  }
  return updated;
}

async function synchronize(socket, desiredMonitors) {
  let monitorList = await getMonitorList(socket);

  for (const desired of desiredMonitors) {
    const matches = Object.values(monitorList).filter((monitor) => monitor.name === desired.name);
    if (matches.length > 1) {
      fail(`Найдено несколько мониторов с именем ${desired.name}. Удалите дубликаты вручную.`);
    }

    if (matches.length === 0) {
      const response = await emitWithAck(socket, "add", { ...desired });
      console.log(`Создан монитор: ${desired.name} (id=${response.monitorID})`);
      monitorList = await getMonitorList(socket);
      continue;
    }

    const summary = matches[0];
    const response = await emitWithAck(socket, "getMonitor", summary.id);
    const current = response.monitor;

    if (!needsUpdate(current, desired)) {
      console.log(`Без изменений: ${desired.name}`);
      continue;
    }

    await emitWithAck(socket, "editMonitor", applyManagedFields(current, desired));
    console.log(`Обновлён монитор: ${desired.name} (id=${summary.id})`);
    monitorList = await getMonitorList(socket);
  }
}

async function main() {
  const url = process.env.UPTIME_KUMA_URL || "http://uptime-kuma:3001";
  const username = process.env.UPTIME_KUMA_USERNAME;
  const password = process.env.UPTIME_KUMA_PASSWORD;
  const configPath = process.env.UPTIME_KUMA_MONITORS_FILE || "/app/monitors.json";

  if (!username || !password) {
    fail("Задайте UPTIME_KUMA_USERNAME и UPTIME_KUMA_PASSWORD в окружении (секреты сервиса).");
  }

  const { monitors } = await loadConfig(configPath);
  const { io } = await import("socket.io-client");
  const socket = io(url, {
    transports: ["websocket", "polling"],
    timeout: 15_000,
  });

  try {
    await new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error(`Не удалось подключиться к ${url}.`)), 15_000);
      socket.once("connect", () => {
        clearTimeout(timer);
        resolve();
      });
      socket.once("connect_error", (error) => {
        clearTimeout(timer);
        reject(error);
      });
    });

    const initialListWaiter = createMonitorListWaiter(socket);
    let login;
    try {
      login = await emitWithAck(socket, "login", { username, password });
    } catch (error) {
      initialListWaiter.cancel();
      throw error;
    }
    if (login.tokenRequired) {
      initialListWaiter.cancel();
      fail("Синхронизация пока не поддерживает учётную запись с двухфакторной аутентификацией.");
    }
    await initialListWaiter.promise;

    await synchronize(socket, monitors);
  } finally {
    socket.close();
  }
}

const isEntrypoint = process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href;
if (isEntrypoint) {
  main().catch((error) => {
    console.error(`Ошибка синхронизации: ${error.message}`);
    process.exitCode = 1;
  });
}
