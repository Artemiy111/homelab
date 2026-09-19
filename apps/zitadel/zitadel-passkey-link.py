#!/usr/bin/env python3
#
# Получить одноразовую ссылку для регистрации passkey (WebAuthn) у пользователя
# ZITADEL. Портирование zitadel/zitadel-passkey-link.sh на Python (только
# стандартная библиотека, без зависимостей).
#
# Требует PAT администратора: переменная окружения ZITADEL_PAT или интерактивный ввод.
#
# Пример:
#   ZITADEL_PAT=... ./zitadel/zitadel-passkey-link.py

from __future__ import annotations

import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent


def info(msg: str) -> None:
    print(f"\033[1;36m{msg}\033[0m", file=sys.stderr)


def ok(msg: str) -> None:
    print(f"\033[1;32m{msg}\033[0m", file=sys.stderr)


def warn(msg: str) -> None:
    print(f"\033[1;33m{msg}\033[0m", file=sys.stderr)


def die(msg: str) -> "NoReturn":  # type: ignore[name-defined]
    print(f"\033[1;31mОшибка: {msg}\033[0m", file=sys.stderr)
    sys.exit(1)


def read_env_key(env_file: Path, key: str) -> str:
    if not env_file.is_file():
        return ""
    m = re.search(rf"^{key}=(.*)$", env_file.read_text(encoding="utf-8"), re.MULTILINE)
    return m.group(1).strip() if m else ""


def api(method: str, path: str, pat: str, api_base: str, body: dict | None = None) -> dict:
    req = urllib.request.Request(
        f"{api_base}{path}",
        method=method,
        headers={"Authorization": f"Bearer {pat}"},
        data=json.dumps(body).encode() if body is not None else None,
    )
    if body is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req) as resp:
            data = json.load(resp)
    except urllib.error.HTTPError as e:
        die(str(json.load(e).get("message") or f"HTTP {e.code}"))
    # grpc-gateway отдаёт ошибку и с кодом 200 — общий фильтр по .message.
    if message := data.get("message"):
        die(message)
    return data


def main() -> None:
    domain = os.environ.get("DOMAIN") or "example.com"
    host = os.environ.get("ZITADEL_HOST") or f"id.{domain}"

    api_base = f"https://{host}/v2"
    login_base = f"https://{host}/ui/v2/login"

    pat = os.environ.get("ZITADEL_PAT") or ""
    if not pat:
        import getpass

        try:
            pat = getpass.getpass("PAT (Console → Users → <admin> → Personal Access Tokens): ")
        except EOFError:
            pass
    if not pat:
        die("PAT не задан (переменная ZITADEL_PAT или интерактивный ввод).")

    info(f"ZITADEL: https://{host}")

    target = input("Логин или user ID (например user или 386564404046479363): ").strip()
    if not target:
        die("пустой ввод.")

    # Один вызов ListUsers на оба случая: число — точный поиск по ID,
    # иначе — подстрока логина без учёта регистра.
    if re.fullmatch(r"\d{5,}", target):
        query: dict = {"inUserIdsQuery": {"userIds": [target]}}
    else:
        query = {
            "loginNameQuery": {
                "loginName": target,
                "method": "TEXT_QUERY_METHOD_CONTAINS_IGNORE_CASE",
            }
        }
    users = [
        (
            r["userId"],
            r.get("username", ""),
            r.get("preferredLoginName", ""),
            r.get("details", {}).get("resourceOwner", ""),
        )
        for r in api("POST", "/users", pat, api_base, {"queries": [query]}).get("result", [])
    ]

    if not users:
        die(f'пользователь по "{target}" не найден.')

    if len(users) == 1:
        user_id, username, login, org_id = users[0]
    else:
        info("Найдено несколько пользователей:")
        for i, (uid, uname, ulogin, _) in enumerate(users, start=1):
            print(f"  {i}) {uname} ({ulogin})  id={uid}", file=sys.stderr)
        choice = input("Номер: ").strip()
        if not choice.isdigit() or not 1 <= int(choice) <= len(users):
            die("неверный номер.")
        user_id, username, login, org_id = users[int(choice) - 1]

    if not user_id or not org_id:
        die("не удалось определить user ID / organization ID.")

    info(f"Пользователь: {username or '<без username>'} ({login or '<без логина>'})")
    info(f"user_id={user_id}  organization={org_id}")

    code = api(
        "POST",
        f"/users/{user_id}/passkeys/registration_link",
        pat,
        api_base,
        {"returnCode": {}},
    ).get("code", {})
    code_id, code_value = code.get("id", ""), code.get("code", "")
    if not code_id or not code_value:
        die("в ответе API нет кода.")

    url = (
        f"{login_base}/passkey/set?"
        + urllib.parse.urlencode(
            {"codeId": code_id, "code": code_value, "userId": user_id, "organization": org_id}
        )
    )

    ok("Ссылка для регистрации passkey:")
    print(f"\033[1m{url}\033[0m")
    print()
    warn(
        "Код одноразовый: ссылку надо открыть на том устройстве, где будет храниться "
        "passkey, и пройти регистрацию до конца с первого раза (ZITADEL #12499)."
    )


if __name__ == "__main__":
    main()
