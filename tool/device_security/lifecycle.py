"""Shared receipt checks for the two small native lifecycle runners."""


def require(value, reason):
    if not value:
        raise ValueError(reason)


def verify_receipt(receipt, nonce, subject, phase, mode, build):
    pid = receipt.get("pid")
    require(type(pid) is int and pid > 0, "missing_process_identity")
    interrupted = mode == 'crash' and phase in ('seed', 'mutate')
    require(receipt == {
        "kind": "keybay-mobile-lifecycle", "nonce": nonce, "subject": subject,
        "phase": phase, "mode": mode, "build": str(build), "pid": pid,
        "status": "ready" if interrupted else "pass",
        "reason": "awaiting_termination" if interrupted else "completed",
    }, "missing_or_mismatched_app_receipt")
    return pid


def verify_upgrade(seed, reopen, identity_fields):
    require(seed["build_number"] == "101" and reopen["build_number"] == "102",
            "wrong_upgrade_versions")
    require(seed["aot_sha256"] != reopen["aot_sha256"], "same_upgrade_binary")
    require(all(seed[key] == reopen[key] for key in identity_fields), "upgrade_identity_changed")
