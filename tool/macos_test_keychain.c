// Disposable native qualification only. Never links into Keybay.
// Every Keychain mutation targets the generated private fixture path.
#include <CoreFoundation/CoreFoundation.h>
#include <Security/Security.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <errno.h>

static const char *password = "keybay disposable native fixture";

int main(int argc, char **argv) {
  const char *prefix = "/private/tmp/keybay-native-";
  const char *suffix = "/account/Library/Keychains/login.keychain-db";
  if (argc != 3 || strncmp(argv[2], prefix, strlen(prefix)) != 0 ||
      strlen(argv[2]) < strlen(prefix) + strlen(suffix) ||
      strcmp(argv[2] + strlen(argv[2]) - strlen(suffix), suffix) != 0 ||
      strstr(argv[2], "/../") || strstr(argv[2], "/./")) return 64;
  OSStatus s = SecKeychainSetUserInteractionAllowed(false);
  if (s) return 1;
  SecKeychainRef kc = NULL;
  if (strcmp(argv[1], "create") == 0) {
    struct stat info;
    if (lstat(argv[2], &info) == 0 || errno != ENOENT) return 65;
    CFArrayRef before = NULL, after = NULL, current = NULL;
    SecKeychainRef beforeDefault = NULL, afterDefault = NULL;
    s = SecKeychainCopySearchList(&before);
    if (s) { printf("read-search-list=%d\n", (int)s); return 1; }
    // Refuse creation if it might establish a new default keychain.
    s = SecKeychainCopyDefault(&beforeDefault);
    if (s) { CFRelease(before); printf("read-default=%d\n", (int)s); return 1; }
    s = SecKeychainCreate(argv[2], (UInt32)strlen(password), password, false, NULL, &kc);
    if (s) { printf("create=%d\n", (int)s); CFRelease(before); CFRelease(beforeDefault); return 1; }
    s = SecKeychainCopySearchList(&current);
    if (!s) {
      CFMutableArrayRef filtered = CFArrayCreateMutableCopy(NULL, 0, current);
      for (CFIndex i = CFArrayGetCount(filtered); i > 0; i--) {
        if (CFEqual(CFArrayGetValueAtIndex(filtered, i - 1), kc)) CFArrayRemoveValueAtIndex(filtered, i - 1);
      }
      s = SecKeychainSetSearchList(filtered);
      CFRelease(filtered); CFRelease(current);
    }
    OSStatus listStatus = SecKeychainCopySearchList(&after);
    OSStatus defaultStatus = SecKeychainCopyDefault(&afterDefault);
    bool preserved = !listStatus && !defaultStatus && CFEqual(before, after) && CFEqual(beforeDefault, afterDefault);
    printf("create=%d user-search-list-and-default-preserved=%d\n", (int)s, preserved);
    if (s || !preserved) { SecKeychainDelete(kc); s = -1; }
    CFRelease(before); CFRelease(beforeDefault);
    if (after) CFRelease(after); if (afterDefault) CFRelease(afterDefault);
  } else {
    s = SecKeychainOpen(argv[2], &kc);
    if (!s) {
      if (strcmp(argv[1], "lock") == 0) {
        s = SecKeychainLock(kc);
        if (!s) {
          SecKeychainStatus status = 0;
          s = SecKeychainGetStatus(kc, &status);
          if (!s && (status & kSecUnlockStateStatus)) s = errSecNotAvailable;
        }
      }
      else if (strcmp(argv[1], "unlock") == 0) s = SecKeychainUnlock(kc, (UInt32)strlen(password), password, true);
      else if (strcmp(argv[1], "delete") == 0) s = SecKeychainDelete(kc);
      else s = -50;
    }
    printf("%s=%d\n", argv[1], (int)s);
  }
  if (kc) CFRelease(kc);
  return s ? 1 : 0;
}
