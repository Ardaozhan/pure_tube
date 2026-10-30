import 'package:flutter_test/flutter_test.dart';
import 'package:pure_tube/main.dart';

void main() {
  test('PureTubeApp instantiation test', () {
    const app = PureTubeApp(ytJsCode: '', ytCssCode: '');
    expect(app.ytJsCode, '');
    expect(app.ytCssCode, '');
  });
}
