import 'package:material_ui/material_ui.dart';

import '../core/theme/app_theme.dart';
import '../services/database_key/database_key_service.dart';
import '../services/database_key/database_key_store.dart';

/// Full-screen gate shown on Web before any database access.
///
/// The browser session starts locked: the database key exists only as an
/// authenticated recovery envelope and the user must unlock it explicitly
/// with their recovery password. This screen also implements:
/// - first-use setup (create the recovery password);
/// - clean-profile restoration (import an exported envelope + password).
///
/// The gate never creates an empty database: when the key material cannot be
/// recovered, it shows the recovery flow and keeps the stored envelope
/// untouched.
class DatabaseUnlockGate extends StatefulWidget {
  const DatabaseUnlockGate({super.key, required this.onDatabaseReady});

  /// Called after the key is resolved for this session. The app bootstrap
  /// (providers, screens) only runs after this callback.
  final VoidCallback onDatabaseReady;

  @override
  State<DatabaseUnlockGate> createState() => _DatabaseUnlockGateState();
}

class _DatabaseUnlockGateState extends State<DatabaseUnlockGate> {
  DatabaseKeyState _state = DatabaseKeyState.locked;
  bool _busy = false;
  String? _error;
  bool _showRestore = false;

  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _envelopeController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _refreshState();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    _envelopeController.dispose();
    super.dispose();
  }

  void _refreshState() {
    setState(() {
      _state = DatabaseKeyService.instance.webState;
      _error = null;
    });
  }

  Future<void> _unlock() async {
    if (!_formKey.currentState!.validate() || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await DatabaseKeyService.instance.unlockWithPassword(
        _passwordController.text,
      );
      if (!mounted) return;
      widget.onDatabaseReady();
    } on DatabaseUnlockWrongPasswordException catch (error) {
      setState(() {
        _error = error.message;
        _busy = false;
      });
    } catch (error) {
      setState(() {
        _error = 'Falha ao desbloquear: $error';
        _busy = false;
      });
    }
  }

  Future<void> _setup() async {
    if (!_formKey.currentState!.validate() || _busy) return;
    if (_passwordController.text != _confirmController.text) {
      setState(() => _error = 'As senhas não conferem.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await DatabaseKeyService.instance.setupWithPassword(
        _passwordController.text,
      );
      if (!mounted) return;
      widget.onDatabaseReady();
    } catch (error) {
      setState(() {
        _error = 'Falha ao configurar o cofre: $error';
        _busy = false;
      });
    }
  }

  Future<void> _restore() async {
    if (!_formKey.currentState!.validate() || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await DatabaseKeyService.instance.restoreEnvelope(
        _envelopeController.text.trim(),
        _passwordController.text,
      );
      if (!mounted) return;
      widget.onDatabaseReady();
    } on DatabaseUnlockWrongPasswordException catch (error) {
      setState(() {
        _error = error.message;
        _busy = false;
      });
    } catch (error) {
      setState(() {
        _error = 'Falha ao restaurar: $error';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      // P2-1: segue theme em vez de hardcoded Color(0xFFF4F6F5).
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _buildBody(),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_state == DatabaseKeyState.recoveryRequired) {
      return _recoveryRequiredBody();
    }
    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // P2-1: AppSemanticColors.success em vez de hardcoded Color(0xFF2E7D32).
          Icon(
            Icons.lock_outline,
            size: 40,
            color: AppSemanticColors.of(context).success,
          ),
          const SizedBox(height: 12),
          Text(
            _title,
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            _subtitle,
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          if (_showRestore) ...[
            TextFormField(
              controller: _envelopeController,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Envelope de recuperação (JSON)',
                border: OutlineInputBorder(),
                hintText: 'Cole aqui o conteúdo exportado do envelope',
              ),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'Cole o envelope de recuperação.'
                  : null,
            ),
            const SizedBox(height: 12),
          ],
          TextFormField(
            controller: _passwordController,
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            decoration: InputDecoration(
              labelText: _showRestore
                  ? 'Senha do envelope'
                  : 'Senha de recuperação',
              border: const OutlineInputBorder(),
              helperText: 'Mínimo de 12 caracteres',
            ),
            validator: (value) {
              if (value == null || value.length < 12) {
                return 'A senha deve ter pelo menos 12 caracteres.';
              }
              return null;
            },
            onFieldSubmitted: (_) => _submit(),
          ),
          if (!_showRestore && _state == DatabaseKeyState.needsSetup) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _confirmController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Confirmar senha',
                border: OutlineInputBorder(),
              ),
              validator: (value) => (value == null || value.length < 12)
                  ? 'A senha deve ter pelo menos 12 caracteres.'
                  : null,
            ),
          ],
          const SizedBox(height: 16),
          if (_error != null) ...[
            Text(
              _error!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
          ],
          FilledButton.icon(
            onPressed: _busy ? null : _submit,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    _showRestore
                        ? Icons.restore
                        : _state == DatabaseKeyState.needsSetup
                        ? Icons.key
                        : Icons.lock_open,
                  ),
            label: Text(_busy ? _busyLabel : _buttonLabel),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() => _showRestore = !_showRestore),
            child: Text(
              _showRestore
                  ? 'Voltar ao desbloqueio'
                  : 'Restaurar com envelope de recuperação',
            ),
          ),
        ],
      ),
    );
  }

  Widget _recoveryRequiredBody() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          Icons.warning_amber_rounded,
          size: 40,
          color: Theme.of(context).colorScheme.error,
        ),
        const SizedBox(height: 12),
        Text(
          'Cofre de chaves indisponível',
          style: Theme.of(context).textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        const Text(
          'O material de chaves deste navegador está ausente, incompleto ou '
          'não passou na verificação de integridade. Nenhum dado foi alterado '
          'ou apagado.\n\n'
          'Para manter o acesso ao banco, restaure um envelope de recuperação '
          'válido. Sem ele, o banco criptografado não pode ser aberto — '
          'nenhum banco vazio será criado no lugar.',
          style: TextStyle(height: 1.4),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () => setState(() => _showRestore = true),
          icon: const Icon(Icons.restore),
          label: const Text('Restaurar envelope'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _refreshState,
          child: const Text('Verificar novamente'),
        ),
        if (_showRestore) ...[
          const SizedBox(height: 12),
          TextFormField(
            controller: _envelopeController,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Envelope de recuperação (JSON)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _passwordController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Senha do envelope',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _restore,
            child: Text(_busy ? 'Restaurando…' : 'Restaurar e abrir'),
          ),
        ],
      ],
    );
  }

  String get _title {
    if (_showRestore) return 'Restaurar acesso';
    switch (_state) {
      case DatabaseKeyState.needsSetup:
        return 'Proteger seu banco de dados';
      case DatabaseKeyState.locked:
      case DatabaseKeyState.recoveryRequired:
        return 'Banco bloqueado';
      case DatabaseKeyState.unlocked:
        return 'Banco desbloqueado';
    }
  }

  String get _subtitle {
    if (_showRestore) {
      return 'Cole o envelope exportado e informe a senha usada quando ele '
          'foi criado. A verificação é autenticada: senha incorreta não '
          'altera nenhum dado.';
    }
    switch (_state) {
      case DatabaseKeyState.needsSetup:
        return 'Crie uma senha de recuperação (mínimo 12 caracteres). Ela '
            'protege a chave de criptografia do banco local e será pedida '
            'ao abrir o app neste navegador. Guarde-a: sem ela o banco não '
            'pode ser desbloqueado.';
      case DatabaseKeyState.locked:
        return 'Digite sua senha de recuperação para desbloquear o banco '
            'criptografado nesta sessão. O banco original permanece '
            'intacto em caso de erro.';
      default:
        return '';
    }
  }

  String get _busyLabel {
    if (_showRestore) return 'Restaurando…';
    return _state == DatabaseKeyState.needsSetup
        ? 'Criando cofre…'
        : 'Desbloqueando…';
  }

  String get _buttonLabel {
    if (_showRestore) return 'Restaurar e abrir';
    return _state == DatabaseKeyState.needsSetup
        ? 'Criar cofre e abrir o app'
        : 'Desbloquear';
  }

  void _submit() {
    if (_showRestore) {
      _restore();
      return;
    }
    if (_state == DatabaseKeyState.needsSetup) {
      _setup();
      return;
    }
    _unlock();
  }
}
