import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/design/app_tokens.dart';
import '../models/consultation.dart';
import '../models/doctor.dart';
import '../models/treatment.dart';
import '../providers/consultation_provider.dart';
import '../providers/doctor_provider.dart';
import '../providers/therapy_provider.dart';
import '../widgets/app_snack_bar.dart';
import '../widgets/consultation_form_dialog.dart';
import '../widgets/doctor_form_dialog.dart';
import '../widgets/stepped_form_sheet.dart';
import '../widgets/treatment_form_dialog.dart';
import 'consultations_screen.dart';
import 'profile_screen.dart';
import 'today_screen.dart';
import 'treatments_screen.dart';

/// Shell principal V4: 4 abas (Hoje, Tratamentos, Consultas, Perfil) com o
/// FAB central que abre o menu radial de cadastro — Medicamento, Consulta
/// e Médico. Em telas largas (>= 900px) a navegação vira um rail lateral.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0;

  static const _breakpoint = 900.0;

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

  // ── Cadastros pelo menu radial ──────────────────────────────────────────

  Future<void> _createTreatment() async {
    final result = await showSteppedFormSheet<Treatment>(
      context: context,
      builder: (_) => const TreatmentFormDialog(),
    );
    if (result == null || !mounted) return;
    await context.read<TherapyProvider>().addTreatment(result);
    if (mounted) {
      showAppSnackBar(
        context,
        'Tratamento salvo. Bom começo!',
        type: AppSnackType.success,
      );
    }
  }

  Future<void> _createConsultation() async {
    final result = await showSteppedFormSheet<Consultation>(
      context: context,
      builder: (_) => const ConsultationFormDialog(),
    );
    if (result == null || !mounted) return;
    await context.read<ConsultationProvider>().saveConsultation(result);
    if (mounted) {
      showAppSnackBar(
        context,
        'Consulta agendada.',
        type: AppSnackType.success,
      );
    }
  }

  Future<void> _createDoctor() async {
    final knownSpecialties =
        context
            .read<DoctorProvider>()
            .doctors
            .map((doctor) => doctor.specialty)
            .where((specialty) => specialty.trim().isNotEmpty)
            .toList();
    final result = await showSteppedFormSheet<Doctor>(
      context: context,
      builder: (_) => DoctorFormDialog(knownSpecialties: knownSpecialties),
    );
    if (result == null || !mounted) return;
    await context.read<DoctorProvider>().saveDoctor(result);
    if (mounted) {
      showAppSnackBar(
        context,
        'Médico salvo no seu catálogo.',
        type: AppSnackType.success,
      );
    }
  }

  Future<void> _openCreateMenu() async {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Fechar menu de cadastro',
      barrierColor: Colors.black38,
      transitionDuration: AppDurations.medium,
      pageBuilder:
          (dialogContext, _, __) => _RadialCreateMenu(
            onTreatment: _createTreatment,
            onConsultation: _createConsultation,
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
      body:
          isWide
              ? Row(
                children: [
                  _buildRail(),
                  const VerticalDivider(width: 1, thickness: 1),
                  Expanded(child: content),
                ],
              )
              : content,
      floatingActionButton: FloatingActionButton(
        tooltip: 'Cadastrar',
        shape: const CircleBorder(),
        onPressed: _openCreateMenu,
        child: const Icon(Icons.add),
      ),
      floatingActionButtonLocation:
          isWide
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
              onTap: () => setState(() => _selectedIndex = i),
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
    final color =
        selected
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
                        color:
                            selected
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

/// Menu radial de cadastro: três "pétalas" que brotam do FAB central com
/// stagger — o gesto memorável de criar algo novo no app.
class _RadialCreateMenu extends StatelessWidget {
  const _RadialCreateMenu({
    required this.onTreatment,
    required this.onConsultation,
    required this.onDoctor,
  });

  final VoidCallback onTreatment;
  final VoidCallback onConsultation;
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
        stagger: 0.18,
      ),
      (
        icon: Icons.medical_services_rounded,
        label: 'Médico',
        action: onDoctor,
        stagger: 0.36,
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
        builder:
            (context, value, child) => Opacity(
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
