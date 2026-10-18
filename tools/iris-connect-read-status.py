#!/usr/bin/env python3
"""Read only the bounded, fixed-field native read receipt. Never read auth stores."""
import json
from pathlib import Path

path = Path.home() / "Library/Application Support/Iris Connect/read-verification.json"
operations = {"calendar.list", "tasks.listActive", "tasks.listFinal"}
reasons = {"policyDenied", "loginRequired", "bindingRequired", "pairingRequired", "forbidden", "transport",
           "httpFailure", "responseTooLarge", "deadline", "rateLimited", "schemaMismatch", "unstablePages",
           "recordLimit", "contractPending", "cancelled"}

try:
    with path.open("rb") as source:
        data = source.read(16385)
    assert len(data) <= 16384
    value = json.loads(data)
    assert type(value) is dict and set(value) == {"ok", "policy", "paired", "loginRequired", "checks"}
    assert value["policy"] == "iris-connect-read-v1"
    assert all(type(value[key]) is bool for key in ["ok", "paired", "loginRequired"])
    assert type(value["checks"]) is list and len(value["checks"]) <= 3
    seen = set()
    for check in value["checks"]:
        assert type(check) is dict
        assert set(check).issubset({"operation", "readSucceeded", "records", "pages", "complete", "contractVerified", "reason"})
        assert check["operation"] in operations and check["operation"] not in seen
        seen.add(check["operation"])
        assert all(type(check[key]) is bool for key in ["readSucceeded", "complete", "contractVerified"])
        assert type(check["records"]) is int and 0 <= check["records"] <= 10000
        assert type(check["pages"]) is int and 0 <= check["pages"] <= 50
        assert check.get("reason") is None or check["reason"] in reasons
    print(json.dumps(value, ensure_ascii=False, indent=2))
except FileNotFoundError:
    print('{"status":"not_started"}')
except (AssertionError, KeyError, TypeError, ValueError, OSError):
    raise SystemExit("Sanitizovaný stav čtení neodpovídá očekávanému kontraktu.")
