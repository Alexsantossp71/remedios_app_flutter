import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'package:remedios_app_flutter/providers/user_profile_provider.dart';
import 'package:remedios_app_flutter/screens/profile_screen.dart';
import 'package:remedios_app_flutter/services/app_data_reset_service.dart';
import 'package:remedios_app_flutter/services/database_encryption/database_encryption_service.dart'
    show kEncryptedDatabaseName, kLegacyDatabaseName;
import 'package:remedios_app_flutter/services/database_key/database_key_service.dart';
import 'package:remedios_app_flutter/services/database_key/in_memory_database_key_store.dart';
import 'package:remedios_app_flutter/services/database_service.dart';

import '../database_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late UserProfileProvider provider;
  late InMemoryDatabaseKeyStore keyStore;
  late List<String> deletedDatabases;
  bool restarted = false;

  Future<void> pumpScreen(WidgetTester tester) async {
    // Viewport alto: o formulário tem ~2000px e o card de privacidade fica
    // abaixo da dobra (lista lazy).
    tester.view.physicalSize = const Size(800, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ChangeNotifierProvider<UserProfileProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(
            body: ProfileScreen(onCompleteReset: () => restarted = true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() async {
    await initializeDateFormatting('pt_BR');
    await setupTestDatabase();
    provider = UserProfileProvider();
    await provider.initialize();

    // Cofre já existente (como um aparelho em uso).
    keyStore = InMemoryDatabaseKeyStore();
    await keyStore.createKeyIfAbsent(List<int>.generate(32, (i) => i));
    DatabaseKeyService.resetInstanceForTesting(store: keyStore);

    // Deleção de bancos registrada (não roda deleção real no teste).
    deletedDatabases = <String>[];
    AppDataResetService.resetInstanceForTesting(
      databaseDeleter: (name) async => deletedDatabases.add(name),
    );
    restarted = false;
  });

  tearDown(() async {
    await DatabaseService.instance.close();
  });

  testWidgets(
    '"Apagar meus dados" apaga bancos e cofre e reinicia como novo no '
    'aparelho',
    (tester) async {
      await pumpScreen(tester);

      // Rola até o card de privacidade (lista lazy) e abre o diálogo.
      await tester.scrollUntilVisible(
        find.text('Apagar meus dados'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('Apagar meus dados'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apagar meus dados'));
      await tester.pumpAndSettle();

      // O diálogo deixa claro o novo escopo: TUDO + o cofre (PIN).
      expect(find.text('Apagar meus dados'), findsNWidgets(2));
      expect(find.textContaining('cofre criptográfico'), findsOneWidget);
      expect(find.textContaining('novo PIN'), findsOneWidget);

      await tester.tap(find.text('Apagar tudo'));
      await tester.pump();
      // runAsync: o close() do SQLite FFI precisa de zona real para
      // completar (mesma técnica de profile_autosave_test.dart).
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();

      // Reinício disparado (produção: BootLoader — usuário como novo).
      expect(restarted, isTrue);
      // Bancos criptografado + legado removidos.
      expect(
        deletedDatabases,
        containsAll([kEncryptedDatabaseName, kLegacyDatabaseName]),
      );
      // Cofre zerado: nenhum material de chave restante — o próximo boot
      // cai no fluxo de criação de PIN (needsSetup).
      expect(await keyStore.readKey(), isNull);
      // Diálogo fechado; nada de snackbar pendente (o reinício é o
      // feedback).
      expect(find.text('Apagar tudo'), findsNothing);
    },
  );

  testWidgets('Cancelar não apaga nada', (tester) async {
    await pumpScreen(tester);

    await tester.scrollUntilVisible(
      find.text('Apagar meus dados'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Apagar meus dados'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apagar meus dados'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(restarted, isFalse);
    expect(deletedDatabases, isEmpty);
    expect(await keyStore.readKey(), isNotNull);
    expect(find.text('Apagar tudo'), findsNothing);
  });
}
