import type { Socket } from "socket.io-client";

type MonitorType = "http" | "dns" | "ping" | "port";

interface Monitor {
  name: string;
  type: MonitorType;
  description?: string;
  url?: string;
  hostname?: string;
  port?: number;
  [key: string]: unknown;
}

interface LoadedConfig {
  version: number;
  monitors: Monitor[];
}

const DEFAULT_MONITOR: Record<string, unknown> = {
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

const ALLOWED_TYPES = new Set<MonitorType>(["http", "dns", "ping", "port"]);
const COMMON_MANAGED_FIELDS = [
  "active",
  "description",
  "interval",
  "maxretries",
  "retryInterval",
  "timeout",
  "resendInterval",
];
const TYPE_MANAGED_FIELDS: Record<MonitorType, string[]> = {
  http: ["url", "method", "accepted_statuscodes", "maxredirects"],
  dns: ["hostname", "dns_resolve_server", "dns_resolve_type"],
  ping: ["hostname"],
  port: ["hostname", "port"],
};

function fail(message: string): never {
  throw new Error(message);
}

const DOMAIN_PLACEHOLDER = /\{\{\s*DOMAIN\s*\}\}/g;
const HOST_IP_PLACEHOLDER = /\{\{\s*HOST_IP\s*\}\}/g;

function expandDomain(value: unknown, domain?: string): unknown {
  if (typeof value !== "string" || !value.includes("{{DOMAIN}}")) {
    return value;
  }
  if (!domain) {
    fail("В monitors.yaml используется {{DOMAIN}}, но переменная DOMAIN не задана.");
  }
  return value.replace(DOMAIN_PLACEHOLDER, domain);
}

function expandHostIp(value: unknown, hostIp?: string): unknown {
  if (typeof value !== "string" || !value.includes("{{HOST_IP}}")) {
    return value;
  }
  if (!hostIp) {
    fail("В monitors.yaml используется {{HOST_IP}}, но переменная HOST_IP не задана.");
  }
  return value.replace(HOST_IP_PLACEHOLDER, hostIp);
}

export async function loadConfig(
  filePath: string,
  domain: string | undefined = Bun.env.DOMAIN,
  hostIp: string | undefined = Bun.env.HOST_IP,
): Promise<LoadedConfig> {
  const source = await Bun.file(filePath)
    .text()
    .catch((error: Error) => fail(`Не удалось прочитать ${filePath}: ${error.message}`));

  let config: { version?: number; monitors?: unknown };
  try {
    config = Bun.YAML.parse(source);
  } catch (error) {
    fail(`Не удалось разобрать ${filePath} как YAML: ${(error as Error).message}`);
  }

  if (config.version !== 1) {
    fail(`Неподдерживаемая версия конфигурации: ${config.version}`);
  }
  if (!Array.isArray(config.monitors)) {
    fail("Поле monitors должно быть массивом.");
  }

  const names = new Set<string>();
  const monitors = (config.monitors as Monitor[]).map((monitor, index) => {
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
    if (monitor.type !== "http" && !monitor.hostname) {
      fail(`Монитор ${monitor.name}: для типа ${monitor.type} требуется hostname.`);
    }
    if (monitor.type === "port" && !Number.isInteger(monitor.port)) {
      fail(`Монитор ${monitor.name}: для TCP-порта требуется целочисленный port.`);
    }

    const merged: Monitor = { ...(DEFAULT_MONITOR as Monitor), ...monitor };
    merged.url = expandHostIp(expandDomain(merged.url, domain), hostIp) as string | undefined;
    merged.hostname = expandHostIp(expandDomain(merged.hostname, domain), hostIp) as string | undefined;
    merged.dns_resolve_server = expandHostIp(
      expandDomain(merged.dns_resolve_server, domain),
      hostIp,
    ) as string | undefined;
    return merged;
  });

  return { version: config.version as number, monitors };
}

function emitWithAck(socket: Socket, event: string, ...args: unknown[]): Promise<any> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      reject(new Error(`Uptime Kuma не ответила на событие ${event}.`));
    }, 15_000);

    socket.emit(event, ...args, (response: any) => {
      clearTimeout(timer);
      if (!response?.ok) {
        reject(new Error(response?.msg || `Событие ${event} завершилось ошибкой.`));
        return;
      }
      resolve(response);
    });
  });
}

function createMonitorListWaiter(socket: Socket): { promise: Promise<any>; cancel: () => void } {
  let finish: () => void;
  const promise = new Promise<any>((resolve, reject) => {
    const timer = setTimeout(() => {
      socket.off("monitorList", onMonitorList);
      reject(new Error("Uptime Kuma не прислала список мониторов."));
    }, 15_000);

    finish = () => {
      clearTimeout(timer);
      socket.off("monitorList", onMonitorList);
      resolve(null);
    };

    function onMonitorList(monitors: any) {
      clearTimeout(timer);
      resolve(monitors);
    }

    socket.once("monitorList", onMonitorList);
  });

  return { promise, cancel: () => finish() };
}

async function getMonitorList(socket: Socket): Promise<any> {
  const waiter = createMonitorListWaiter(socket);
  try {
    await emitWithAck(socket, "getMonitorList");
    return await waiter.promise;
  } catch (error) {
    waiter.cancel();
    throw error;
  }
}

function managedFields(monitor: Monitor): string[] {
  return ["name", "type", ...COMMON_MANAGED_FIELDS, ...TYPE_MANAGED_FIELDS[monitor.type]];
}

function comparableValue(value: unknown): string | null {
  if (value === undefined) return null;
  if (typeof value === "number") return String(value);
  return JSON.stringify(value);
}

export function needsUpdate(current: Record<string, unknown>, desired: Monitor): boolean {
  return managedFields(desired).some(
    (field) => comparableValue(current[field]) !== comparableValue(desired[field]),
  );
}

function applyManagedFields(current: Record<string, unknown>, desired: Monitor): Record<string, unknown> {
  const updated = { ...current };
  for (const field of managedFields(desired)) {
    updated[field] = desired[field] as unknown;
  }
  return updated;
}

async function synchronize(socket: Socket, desiredMonitors: Monitor[]): Promise<void> {
  let monitorList: Record<string, any> = await getMonitorList(socket);

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

async function main(): Promise<void> {
  const url = Bun.env.UPTIME_KUMA_URL || "http://uptime-kuma:3001";
  const username = Bun.env.UPTIME_KUMA_USERNAME;
  const password = Bun.env.UPTIME_KUMA_PASSWORD;
  const configPath = Bun.env.UPTIME_KUMA_MONITORS_FILE || "/app/monitors.yaml";

  if (!username || !password) {
    fail("Задайте UPTIME_KUMA_USERNAME и UPTIME_KUMA_PASSWORD в окружении (секреты сервиса).");
  }

  const { monitors } = await loadConfig(configPath);
  const { io } = await import("socket.io-client");
  const socket: Socket = io(url, {
    transports: ["websocket", "polling"],
    timeout: 15_000,
  });

  try {
    await new Promise<void>((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error(`Не удалось подключиться к ${url}.`)), 15_000);
      socket.once("connect", () => {
        clearTimeout(timer);
        resolve();
      });
      socket.once("connect_error", (error: Error) => {
        clearTimeout(timer);
        reject(error);
      });
    });

    const initialListWaiter = createMonitorListWaiter(socket);
    let login: any;
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

if (import.meta.path === Bun.main) {
  main().catch((error: Error) => {
    console.error(`Ошибка синхронизации: ${error.message}`);
    process.exitCode = 1;
  });
}
