#!/usr/bin/env python3
"""Read only the native app's sanitized receipt. Never read Keychain or legacy tokens."""
import json
from datetime import datetime
from pathlib import Path
import stat

STATES = {
    "ready", "checking_configuration", "authenticating", "credentials_submitted",
    "credentials_submission_unconfirmed", "verifying", "authenticated", "verified",
    "session_expired", "configuration", "transport", "response", "cancelled", "expired",
    "callback", "token", "signature", "policy", "keychain", "disconnected",
    "tokenAlgorithm", "tokenIssuer", "tokenAudience", "tokenNonce", "tokenSubject",
    "tokenTime", "tokenAuthorizedParty", "access_method_selected", "loginMethod",
}
REASONS = {"tokenAlgorithm", "tokenIssuer", "tokenAudience", "tokenNonce", "tokenSubject", "tokenTime", "tokenAuthorizedParty"}
FLAGS = ("tokenSignatureVerified", "readProbePassed", "credentialsSubmittedByApp", "mfaConfirmedByUser")


def read_status():
    directory = Path.home() / "Library/Application Support/Iris Connect"
    path = directory / "verification.json"
    if not path.exists():
        return {"state": "receipt_missing"}
    if directory.is_symlink() or path.is_symlink():
        return {"state": "invalid_receipt"}
    info = path.stat()
    if not stat.S_ISREG(info.st_mode) or info.st_size > 16384:
        return {"state": "invalid_receipt"}
    data = json.loads(path.read_text())
    if not isinstance(data, dict) or data.get("state") not in STATES:
        return {"state": "invalid_receipt"}
    result = {"state": data["state"]}
    for flag in FLAGS:
        if type(data.get(flag)) is not bool:
            return {"state": "invalid_receipt"}
        result[flag] = data[flag]
    for flag in ("accessMethodSelectionAttempted", "accessMethodSelectedByApp", "screenLocked", "backgroundLoginEnabled", "backgroundAttempt"):
        if flag in data:
            if type(data[flag]) is not bool:
                return {"state": "invalid_receipt"}
            result[flag] = data[flag]
    if "loginPageProbe" in data:
        if data["loginPageProbe"] not in {"notStarted", "formReady", "choiceReady", "waiting", "ambiguous", "denied", "unsupportedChoice"}:
            return {"state": "invalid_receipt"}
        result["loginPageProbe"] = data["loginPageProbe"]
    for field in ("timestamp", "validUntil"):
        value = data.get(field)
        if value is not None:
            if not isinstance(value, str) or len(value) > 40:
                return {"state": "invalid_receipt"}
            result[field] = datetime.fromisoformat(value.replace("Z", "+00:00")).isoformat()
    reasons = data.get("validationFailures", [])
    if not isinstance(reasons, list) or len(reasons) > len(REASONS) or any(not isinstance(x, str) or x not in REASONS for x in reasons):
        return {"state": "invalid_receipt"}
    result["validationFailures"] = reasons
    return result


if __name__ == "__main__":
    try:
        print(json.dumps(read_status(), ensure_ascii=False, indent=2))
    except (OSError, ValueError, TypeError):
        print('{"state":"receipt_unavailable"}')
