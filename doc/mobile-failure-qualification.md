# Remaining physical mobile procedures

These are the bounded procedures for the remaining device work. Physical
execution passed on iOS for upgrade and crash recovery on Sep 6; Android
crash execution and the other procedures below remain **pending**. The `--crash` selection is implemented for both
Android and iOS using the existing lifecycle fixture and runners. It has passed
host orchestration checks and compiled as Profile/AOT for both platforms. Existing
`--lifecycle` and `--upgrade` runners deliberately verify clean exits and must
not be relabelled as crash, lock or backup tests.

```sh
./tool/device_security.sh run android --device SERIAL --crash
KEYBAY_APPLE_TEAM_ID=TEAMID ./tool/device_security.sh run ios --device UDID --crash
```

The crash selection kills the acknowledged seed process, starts a second
process that verifies recovery and enters a bounded numbered-write workload,
kills that exact process, and checks recovery in a third process. Public
acknowledgments use atomic replacement. The final stored sequence must equal
the last acknowledgment or its immediate successor. It verifies a subsequent
write and reset cleanup. Native PID/identity and process absence are required;
stale receipts, failed signals and unrelated processes cannot pass. The write
workload does not prove the signal interrupted a particular filesystem syscall.

Use only `dev.keybay.securityharness` and public fixture records/passphrases.
Before each device session, identify the exact device, native OS and app build,
confirm that only the dedicated namespace is affected, and record a fresh
source/nonce-bound seed. Keep native logs private. Do not change the user's
screen credential, biometric enrollment, other apps or backup configuration.

| Procedure | Sequence | Required observations |
| --- | --- | --- |
| Abrupt termination after acknowledgment | Seed and acknowledge records; keep the fixture process alive; force-stop only that app; launch a fresh process and open the existing store. | Native PID/termination evidence; acknowledged records survive; no initialization; passphrase policy retained; next write succeeds. This is distinct from interruption inside a write. |
| Termination during mutation | Run a bounded loop of numbered record writes, recording public acknowledgments outside the encrypted store; terminate only the fixture; recover in a fresh process. | Every acknowledged write survives; the interrupted write yields one complete old or new generation; no plaintext fallback, provider replacement, silent reset or permanent lock. Deterministic file boundaries and interruption during auth changes are covered separately by the host crash tests; physical auth-change interruption remains unqualified. |
| Reboot / first unlock / relock | Seed; reboot the agreed test device; attempt only OS-permitted fixture execution before first unlock; unlock and reopen; close the session, relock, and probe fresh provider acquisition; unlock and recover again. | Correlate results with the actual platform policy and native lock state. Apple uses `WhenUnlockedThisDeviceOnly`. Android's current key is not configured to require user authentication: do not invent a user-presence guarantee. If the OS prevents app launch, record that boundary as unobserved. |
| Reference-app backup exclusion | Seed the signed reference app and use a documented platform backup/restore mechanism available for a dedicated test device/account. Inspect the resulting dedicated-app evidence and restore behavior. | Native no-backup/exclusion configuration is reflected in actual backup behavior. Preserve control markers that distinguish omitted app data from loss of only the provider root. No claim from a filesystem copy alone. |
| Lost-root restore / transfer | Retain only the fixture's complete encrypted store; restore it into an authorized dedicated app installation without its original platform root, or transfer through the platform's actual device procedure. | An existing encrypted store fails closed with the documented invalidation/authentication result; it never initializes over it or silently creates a replacement root. A fresh empty install is tested separately. |

Keep each phase's source, nonce, app identity, process identity, native event and
result together. A launcher success, log line, missing app container or newly
initialized empty store cannot stand in for recovery of acknowledged records.

Lock, reboot and real backup/transfer still need explicit retained-state phases
matched to the available device procedure. Do not interrupt the clean-exit
runner opportunistically. Add only the
specific phase needed for the next available device session and validate its
host orchestration before executing it. Reuse the current public receipt and
cleanup conventions rather than creating another qualification framework.

Afterward, reset the exact fixture store, verify provider/file cleanup where
the profile owns those resources, and remove the dedicated Android package.
Apple's device-only protection, backup exclusions and root-loss injection each
answer different questions; retain their results separately.
