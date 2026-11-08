import 'package:flutter_test/flutter_test.dart';

/// Render the real soft shadows in visual references instead of the test
/// binding's default hard shadow approximation. Keep its invariant in sync.
void initializeVisualTests() => _VisualBinding();

class _VisualBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get disableShadows => false;
}
