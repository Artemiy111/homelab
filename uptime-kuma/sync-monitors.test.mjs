import assert from "node:assert/strict";
import { mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import { loadConfig, needsUpdate } from "./sync-monitors.mjs";

test("конфигурация дополняется безопасными значениями по умолчанию", async () => {
  const directory = await mkdtemp(join(tmpdir(), "uptime-kuma-test-"));
  const configPath = join(directory, "monitors.json");
  await writeFile(
    configPath,
    JSON.stringify({
      version: 1,
      monitors: [{ name: "Traefik", type: "http", url: "http://traefik:8080/ping" }],
    }),
  );

  const config = await loadConfig(configPath);

  assert.equal(config.monitors[0].interval, 60);
  assert.equal(config.monitors[0].maxretries, 2);
  assert.equal(config.monitors[0].timeout, 48);
  assert.deepEqual(config.monitors[0].accepted_statuscodes, ["200-299"]);
});

test("повторяющиеся имена отклоняются", async () => {
  const directory = await mkdtemp(join(tmpdir(), "uptime-kuma-test-"));
  const configPath = join(directory, "monitors.json");
  await writeFile(
    configPath,
    JSON.stringify({
      version: 1,
      monitors: [
        { name: "DNS", type: "dns", hostname: "one.example" },
        { name: "DNS", type: "dns", hostname: "two.example" },
      ],
    }),
  );

  await assert.rejects(() => loadConfig(configPath), /Имя монитора повторяется/);
});

test("плейсхолдер {{DOMAIN}} подставляется из переменной DOMAIN", async () => {
  const directory = await mkdtemp(join(tmpdir(), "uptime-kuma-test-"));
  const configPath = join(directory, "monitors.json");
  await writeFile(
    configPath,
    JSON.stringify({
      version: 1,
      monitors: [
        { name: "Web", type: "http", url: "https://app.{{DOMAIN}}/" },
        { name: "DNS", type: "dns", hostname: "app.{{DOMAIN}}" },
      ],
    }),
  );

  const config = await loadConfig(configPath, "example.org");

  assert.equal(config.monitors[0].url, "https://app.example.org/");
  assert.equal(config.monitors[1].hostname, "app.example.org");
});

test("{{DOMAIN}} без переменной DOMAIN вызывает ошибку", async () => {
  const directory = await mkdtemp(join(tmpdir(), "uptime-kuma-test-"));
  const configPath = join(directory, "monitors.json");
  await writeFile(
    configPath,
    JSON.stringify({
      version: 1,
      monitors: [{ name: "Web", type: "http", url: "https://app.{{DOMAIN}}/" }],
    }),
  );

  await assert.rejects(
    () => loadConfig(configPath, ""),
    /переменная DOMAIN не задана/,
  );
});

test("сравнение учитывает только управляемые поля", () => {
  const desired = {
    name: "Traefik",
    type: "http",
    description: "Проверка Traefik",
    active: true,
    interval: 60,
    maxretries: 2,
    retryInterval: 60,
    resendInterval: 0,
    url: "http://traefik:8080/ping",
    method: "GET",
    accepted_statuscodes: ["200-299"],
    maxredirects: 10,
  };

  assert.equal(needsUpdate({ ...desired, id: 7, created_date: "ignored" }, desired), false);
  assert.equal(needsUpdate({ ...desired, interval: 30 }, desired), true);
});
