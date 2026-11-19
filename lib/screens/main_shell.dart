import 'package:material_ui/material_ui.dart';

import '../core/design/app_shell.dart';
import '../core/design/app_tokens.dart';
import '../widgets/create_choice_sheet.dart';
import 'consultations_screen.dart';
import 'create_flows.dart';
import 'profile_screen.dart';
import 'today_screen.dart';
import 'treatments_screen.dart';

/// Shell principal V4: 4 abas (Hoje, Tratamentos, Consultas, Perfil) com o
/// FAB central que abre o menu de cadastro com TODAS as funcionalidades —
/// Medicamento, Consulta, Exame, Laudo, Plano de saúde e Médico —, cada uma
/// perguntando manual × foto quando existe leitura por IA. Em telas largas
/// (>= 900px) a navegação vira um rail lateral.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

/// Como o usuário quer cadastrar um domínio que tem leitura de foto:
/// preencher no dedo ou deixar a IA ler a imagem para conferência.
enum _CreationMode { manual, photo }

class _MainShellState extends State<MainShell>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;

  static const _breakpoint = 900.0;

  /// Crossfade calmo entre abas (fim do corte seco do IndexedStack).
  late final AnimationController _tabFade = AnimationController(
    vsync: this,
    duration: AppDurations.medium,
    value: 1,
  );

  void _switchTab(int index) {
    if (index == _selectedIndex) return;
    setState(() => _selectedIndex = index);
    _tabFade.forward(from: 0);
  }

  static const _destinations = [
    (icon: Icons.today_outlined, selectedIcon: Icons.today, label: 'Hoje'),
    (
      icon: Icons.medication_outlined,
      selectedIcon: Icons.medication,
      label: 'Tratamentos',
    ),
    (
      icon: Icons.calendar_month_outlined,
      selectedIcon: Icons.calendar_month,
      label: 'Consultas',
    ),
    (icon: Icons.person_outline, selectedIcon: Icons.person, label: 'Perfil'),
  ];

  static const _pages = <Widget>[
    TodayScreen(),
    TreatmentsScreen(),
    ConsultationsScreen(),
    ProfileScreen(),
  ];

  // ── Cadastros pelo menu central ─────────────────────────────────────
  //
  // Todo domínio com leitura de foto PERGUNTA antes (manual × foto) —
  // escolhido o caminho, o fluxo compartilhado de create_flows.dart roda
  // igual ao da tela correspondente.

  /// Respira entre fechar uma folha e abrir o próximo diálogo (o scrim
  /// precisa terminar de baixar antes de a próxima rota subir).
  Future<void> _settleSheet() async {
    await Future<void>.delayed(AppDurations.fast);
  }

  Future<void> _createTreatment() async {
    final mode = await showCreateChoiceSheet<_CreationMode>(
      context,
      title: 'Novo medicamento',
      options: [
        const CreateChoiceOption(
          value: _CreationMode.manual,
          icon: Icons.edit_outlined,
          title: 'Digitar manualmente',
          subtitle: 'Preencha nome, dosagem e horários no formulário.',
        ),
        const CreateChoiceOption(
          value: _CreationMode.photo,
          icon: Icons.photo_camera_outlined,
          title: 'Usar foto da receita',
          subtitle:
              'A IA lê a receita e você confere cada medicamento antes de '
              'salvar.',
        ),
      ],
    );
    if (mode == null || !mounted) return;
    await _settleSheet();
    if (!mounted) return;
    if (mode == _CreationMode.manual) {
      await createTreatmentManually(context);
    } else {
      await createTreatmentFromPrescription(context);
    }
  }

  Future<void> _createConsultation() async {
    await createConsultation(context);
  }

  Future<void> _createExam() async {
    await createExam(context);
  }

  Future<void> _createLabResult() async {
    final mode = await showCreateChoiceSheet<_CreationMode>(
      context,
      title: 'Novo laudo',
      options: [
        const CreateChoiceOption(
          value: _CreationMode.manual,
          icon: Icons.edit_outlined,
          title: 'Digitar manualmente',
          subtitle: 'Informe laboratório, data e os valores dos marcadores.',
        ),
        const CreateChoiceOption(
          value: _CreationMode.photo,
          icon: Icons.photo_camera_outlined,
          title: 'Ler foto com IA',
          subtitle:
              'A IA transcreve os valores impressos para você conferir e '
              'salvar.',
        ),
      ],
    );
    if (mode == null || !mounted) return;
    await _settleSheet();
    if (!mounted) return;
    if (mode == _CreationMode.manual) {
      await createLabResultManually(context);
    } else {
      await createLabResultFromPhoto(context);
    }
  }

  Future<void> _createHealthPlan() async {
    // O módulo de planos já tem a folha própria (foto do cartão × manual) —
    // é ela a entrada canônica.
    await addHealthPlan(context);
  }

  Future<void> _createDoctor() async {
    final mode = await showCreateChoiceSheet<_CreationMode>(
      context,
      title: 'Novo médico',
      options: [
        const CreateChoiceOption(
          value: _CreationMode.manual,
          icon: Icons.edit_outlined,
          title: 'Digitar manualmente',
          subtitle: 'Nome, especialidade, contato e endereço.',
        ),
        const CreateChoiceOption(
          value: _CreationMode.photo,
          icon: Icons.photo_camera_outlined,
          title: 'Foto da receita',
          subtitle:
              'A IA identifica quem assinou (nome e CRM) para você conferir.',
        ),
      ],
    );
    if (mode == null || !mounted) return;
    await _settleSheet();
    if (!mounted) return;
    if (mode == _CreationMode.manual) {
      await createDoctorManually(context);
    } else {
      await createDoctorFromPrescription(context);
    }
  }

  Future<void> _openCreateMenu() async {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Fechar menu de cadastro',
      barrierColor: Colors.black38,
      transitionDuration: AppDurations.medium,
      pageBuilder: (dialogContext, _, __) => _RadialCreateMenu(
        onTreatment: _createTreatment,
        onConsultation: _createConsultation,
        onExam: _createExam,
        onLabResult: _createLabResult,
        onHealthPlan: _createHealthPlan,
        onDoctor: _createDoctor,
      ),
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= _breakpoint;

    final content = IndexedStack(index: _selectedIndex, children: _pages);

    return Scaffold(
      // AppShell pinta o brilho radial teal do PWA atrás de todas as abas.
      body: isWide
          ? Row(
              children: [
                _buildRail(),
                const VerticalDivider(width: 1, thickness: 1),
                Expanded(child: AppShell(child: content)),
              ],
            )
          : AppShell(child: content),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Cadastrar',
        shape: const CircleBorder(),
        onPressed: _openCreateMenu,
        child: const Icon(Icons.add),
      ),
      floatingActionButtonLocation: isWide
          ? FloatingActionButtonLocation.endFloat
          : FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: isWide ? null : _buildBottomBar(),
    );
  }

  Widget _buildRail() {
    return NavigationRail(
      selectedIndex: _selectedIndex,
      onDestinationSelected: (index) => setState(() => _selectedIndex = index),
      labelType: NavigationRailLabelType.all,
      leading: Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 16),
        child: FloatingActionButton.small(
          heroTag: 'rail-create-fab',
          tooltip: 'Cadastrar',
          shape: const CircleBorder(),
          onPressed: _openCreateMenu,
          child: const Icon(Icons.add),
        ),
      ),
      destinations: [
        for (final destination in _destinations)
          NavigationRailDestination(
            icon: Icon(destination.icon),
            selectedIcon: Icon(destination.selectedIcon),
            label: Text(destination.label),
          ),
      ],
    );
  }

  Widget _buildBottomBar() {
    return BottomAppBar(
      shape: const CircularNotchedRectangle(),
      notchMargin: 8,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (var i = 0; i < _destinations.length; i++)
            _NavItem(
              icon: _destinations[i].icon,
              selectedIcon: _destinations[i].selectedIcon,
              label: _destinations[i].label,
              selected: _selectedIndex == i,
              onTap: () => _switchTab(i),
            ),
        ],
      ),
    );
  }
}

/// Item da barra inferior com alvo de toque folgado e rótulo em linha única.
class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: 32,
                width: 56,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AnimatedContainer(
                      duration: AppDurations.medium,
                      curve: AppCurves.emphasized,
                      width: selected ? 56 : 0,
                      height: 30,
                      decoration: BoxDecoration(
                        color: selected
                            ? theme.colorScheme.primaryContainer
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    Icon(
                      selected ? selectedIcon : icon,
                      color: color,
                      size: 22,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 11.5,
                  height: 1.15,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Menu de cadastro do FAB central: as seis pétalas brotam do botão com
/// stagger — o gesto memorável de criar algo novo no app, agora com todos
/// os domínios e com os caminhos de foto lida por IA no mesmo lugar.
class _RadialCreateMenu extends StatelessWidget {
  const _RadialCreateMenu({
    required this.onTreatment,
    required this.onConsultation,
    required this.onExam,
    required this.onLabResult,
    required this.onHealthPlan,
    required this.onDoctor,
  });

  final VoidCallback onTreatment;
  final VoidCallback onConsultation;
  final VoidCallback onExam;
  final VoidCallback onLabResult;
  final VoidCallback onHealthPlan;
  final VoidCallback onDoctor;

  Future<void> _pick(BuildContext context, VoidCallback action) async {
    Navigator.of(context).pop();
    // Pequeno atraso para o scrim fechar antes do próximo diálogo subir.
    await Future<void>.delayed(AppDurations.fast);
    action();
  }

  @override
  Widget build(BuildContext context) {
    final options = [
      (
        icon: Icons.medication_rounded,
        label: 'Medicamento',
        action: onTreatment,
        stagger: 0.0,
      ),
      (
        icon: Icons.calendar_month_rounded,
        label: 'Consulta',
        action: onConsultation,
        stagger: 0.1,
      ),
      (
        icon: Icons.science_rounded,
        label: 'Exame',
        action: onExam,
        stagger: 0.2,
      ),
      (
        icon: Icons.description_rounded,
        label: 'Laudo',
        action: onLabResult,
        stagger: 0.3,
      ),
      (
        icon: Icons.health_and_safety_rounded,
        label: 'Plano de saúde',
        action: onHealthPlan,
        stagger: 0.4,
      ),
      (
        icon: Icons.medical_services_rounded,
        label: 'Médico',
        action: onDoctor,
        stagger: 0.5,
      ),
    ];

    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 96),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in options)
              _RadialOption(
                icon: option.icon,
                label: option.label,
                onTap: () => _pick(context, option.action),
                stagger: option.stagger,
              ),
          ],
        ),
      ),
    );
  }
}

class _RadialOption extends StatelessWidget {
  const _RadialOption({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.stagger,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Fração da animação (0..1) em que esta pétala começa a aparecer.
  final double stagger;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: AppDurations.medium,
        curve: Interval(stagger, 1, curve: AppCurves.emphasized),
        builder: (context, value, child) => Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 24 * (1 - value)),
            child: Transform.scale(scale: 0.6 + 0.4 * value, child: child),
          ),
        ),
        child: FilledButton.tonalIcon(
          onPressed: onTap,
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.surface,
            foregroundColor: Theme.of(context).colorScheme.primary,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.xl),
            ),
            elevation: 4,
          ),
          icon: Icon(icon),
          label: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );
  }
}
