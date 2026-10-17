import 'package:flutter_test/flutter_test.dart';
import 'package:walkable/power_settings.dart';

void main() {
  group('dontKillMyAppPage', () {
    test('links an aggressive manufacturer to its own page', () {
      expect(dontKillMyAppPage('samsung'),
          Uri.parse('https://dontkillmyapp.com/samsung'));
      expect(dontKillMyAppPage('Xiaomi'),
          Uri.parse('https://dontkillmyapp.com/xiaomi'));
      expect(dontKillMyAppPage('OnePlus'),
          Uri.parse('https://dontkillmyapp.com/oneplus'));
      expect(dontKillMyAppPage('HUAWEI'),
          Uri.parse('https://dontkillmyapp.com/huawei'));
    });

    test('files Honor under Huawei, as dontkillmyapp.com does', () {
      expect(dontKillMyAppPage('HONOR'),
          Uri.parse('https://dontkillmyapp.com/huawei'));
    });

    test('has nothing for manufacturers that do not kill apps', () {
      expect(dontKillMyAppPage('Google'), isNull);
      expect(dontKillMyAppPage('HMD Global'), isNull);
      expect(dontKillMyAppPage('unknown'), isNull);
      expect(dontKillMyAppPage(''), isNull);
    });
  });
}
