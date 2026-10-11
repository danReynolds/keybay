# CLI 0.2.0 candidate qualification, October 11, 2026

Source: Keybay `e15583fec66316463e139ca1682b51bd771c1403`; RK `8e1b480d5dc1019fc1dadecedf2a079a7b02991b`.

Stage `ed00045ef003d485b87d99834be415ac819556d382d5e718d141db86e9a5ddff` contains the candidate archives and generated Homebrew formula. All three targets built; Apple notarization was accepted. The stage remains private; nothing was published.

Local receipts named below are retained under
`build/qualification/cli-production-20261010/` in the maintainer checkout.
They are not public download links. This record precedes final documentation
cleanup and publication; a later stage must retain equivalent runtime inputs
and repeat artifact checks if bytes change.

## Completed

- Archive hashes, modes and exact notices; native ABI/worker loading with development paths unavailable. Linux native load checks pass on Ubuntu 22.04, Debian 12 and Ubuntu 24.04, both architectures.
- Real Homebrew install of 0.1.1, then upgrade to the exact staged 0.2.0 macOS archive. A separate formula name, local archive URLs and keg-only declaration avoid modifying the ordinary keybay command. Formula install logic is unchanged. All installed managed files match the stage byte-for-byte. Seven code signatures and notarization checks pass. A quarantine-marked copy launches on this Mac. This does not claim a fresh-machine or public-download test.
- Real Linux installed-product operations over a private Secret Service on ARM64 and emulated x64: hidden secret input, child-process injection, list/delete, TUI enrollment of a passphrase, reinstall, correct/wrong-passphrase checks, encrypted-value continuity, masked TUI browsing and terminal restoration. No Dart or development libraries are in those runtime images.
- Actual 0.1.1 V1 data remains accessible with the old binary after installing 0.2.0. The current CLI deliberately does not migrate V1 data; new-format initialization does not prove old data has migrated. The upgrade notice remains required.

## Attended verification

The product on macOS resolves the real account home via getpwuid_r and pins its login Keychain. HOME overrides do not isolate its vault. A disposable-account run requires administrator access, which is unavailable unattended. The user was offered a read-only existing-vault check or a temporary account; no personal vault was opened during preparation.

The user authorized the existing-vault option. `Verify installed YubiKey.command` verified the installed candidate hashes and completed two fresh-process read-only list requests while suppressing key names. Both exited successfully (PIDs 77845 and 77892); see `hardware-result.json`, recorded at 2026-10-10T18:15:28Z. PIN entry was handled by the product and was not captured. No credentials were enrolled or removed.

On October 11, 2026, the user explicitly confirmed that both requests used the YubiKey. Combined with the successful fresh-process receipts, this completes read-only hardware unlock verification and existing-vault continuity for the exact installed macOS candidate. The machine receipt intentionally does not record the selected authentication method; this classification includes the user's attended confirmation. This check does not cover new hardware enrollment or physical Linux hardware access.

## CI and limits

Final-main CI initially failed only on an Intel macOS Argon2 worker's ten-second segment timeout; the failed lane was rerun, without changing source or weakening tests. The second attempt passed every required lane on the exact merged source. See `final-main-ci.json` and https://github.com/danReynolds/keybay/actions/runs/38058083738.

An initial local protected-vault harness matched a stale screen and sent Escape plus Quit before the screen transition; its corrected version waits for the newly rendered screen. The product was unchanged, and both final runs pass.

The standalone CLI is not an app bundle: spctl's execute assessment reported that distinction; install assessment and codesign notarization validation accepted it. No Gatekeeper exception or quarantine removal was used for the successful quarantine-marked launch.

Publication, actual public-download/Homebrew channel verification and cleanup of the isolated candidate formula remain later actions. The production keybay command and vault have not been modified.
