#import <objc/message.h>
#import <XCTest/XCTest.h>

@interface RunnerTests : XCTestCase
@end

@implementation RunnerTests

- (void)testDartIntegrationSuite {
  // The Flutter-generated app links and registers IntegrationTestPlugin. Look
  // up that exact in-process singleton without linking a second copy of the
  // plugin into this test bundle (Swift packages are static by default).
  Class pluginClass = NSClassFromString(@"IntegrationTestPlugin");
  XCTAssertNotNil(pluginClass, @"IntegrationTestPlugin is not registered in the app");
  if (pluginClass == Nil) return;

  id (*sendInstance)(id, SEL) = (void *)objc_msgSend;
  id plugin = sendInstance(pluginClass, NSSelectorFromString(@"instance"));
  XCTAssertNotNil(plugin, @"IntegrationTestPlugin did not expose its singleton");
  if (plugin == nil) return;

  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:120];
  NSDictionary<NSString *, NSString *> *results = nil;
  while (results == nil && deadline.timeIntervalSinceNow > 0) {
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    results = [plugin valueForKey:@"testResults"];
  }

  XCTAssertNotNil(results, @"Dart integration tests did not report results within 120 seconds");
  if (results == nil) return;
  NSLog(@"Keybay Dart integration results: %@", results);
  XCTAssertGreaterThan(results.count, 0UL, @"Dart integration suite reported no tests");
  for (NSString *name in [results.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
    NSString *result = results[name];
    XCTAssertEqualObjects(result, @"success", @"Dart test '%@' failed: %@", name, result);
  }
}

@end
