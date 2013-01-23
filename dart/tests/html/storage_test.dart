library StorageTest;
import '../../pkg/unittest/lib/unittest.dart';
import '../../pkg/unittest/lib/html_config.dart';
import 'dart:html';

main() {
  useHtmlConfiguration();
  test('GetItem', () {
    final value = window.localStorage['does not exist'];
    expect(value, isNull);
  });
  test('SetItem', () {
    final key = 'foo';
    final value = 'bar';
    window.localStorage[key] = value;
    final stored = window.localStorage[key];
    expect(stored, value);
  });

  test('event', () {
    // Bug 8076 that not all optional params are optional in Dartium.
    var event = new StorageEvent('something', oldValue: 'old', newValue: 'new',
        url: 'url');
    expect(event is StorageEvent, isTrue);
    expect(event.oldValue, 'old');
    expect(event.newValue, 'new');
  });
}
