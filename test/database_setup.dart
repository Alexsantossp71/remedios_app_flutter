import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:remedios_app_flutter/services/database_service.dart';

Future<void> setupTestDatabase() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  await DatabaseService.instance.initInMemoryDatabase();
}
