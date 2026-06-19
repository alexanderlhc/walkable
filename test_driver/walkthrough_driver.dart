// Driver for integration_test/walkthrough_test.dart.
//
// The walkthrough takes no screenshots — it just plays the recording session
// out in real time while tool/walkthrough_video.sh screen-records the device.
// This is the stock integration driver; its only job is to let `flutter drive`
// run the on-device test to completion.

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
