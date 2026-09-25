import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/therapy_provider.dart';
import '../widgets/section_header.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TherapyProvider>();
    final lowStock = provider.activeTreatments.where((treatment) => treatment.needsRefill).length;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
        children: [
          Text(
            'Perfil',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 5),
          Text(
            'Tudo para deixar sua rotina mais simples.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    child: Icon(
                      Icons.favorite_rounded,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Minha rotina de saúde',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Mantenha seus tratamentos organizados.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.outline),
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),
          const SectionHeader(title: 'Resumo do estoque'),
          const SizedBox(height: 10),
          Card(
            child: Column(
              children: [
                _SummaryTile(
                  icon: Icons.medication_outlined,
                  title: 'Tratamentos ativos',
                  value: '${provider.activeTreatments.length}',
                ),
                const Divider(height: 1, indent: 64, endIndent: 18),
                _SummaryTile(
                  icon: Icons.inventory_2_outlined,
                  title: 'Precisam de reposição',
                  value: '$lowStock',
                  valueColor: lowStock > 0 ? Colors.orange.shade800 : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          const SectionHeader(title: 'Preferências'),
          const SizedBox(height: 10),
          Card(
            child: Column(
              children: const [
                _PreferenceTile(
                  icon: Icons.notifications_none,
                  title: 'Notificações',
                  subtitle: 'Lembretes de horários',
                ),
                Divider(height: 1, indent: 64, endIndent: 18),
                _PreferenceTile(
                  icon: Icons.backup_outlined,
                  title: 'Dados e privacidade',
                  subtitle: 'Seus dados ficam neste dispositivo',
                ),
                Divider(height: 1, indent: 64, endIndent: 18),
                _PreferenceTile(
                  icon: Icons.help_outline,
                  title: 'Ajuda',
                  subtitle: 'Dúvidas e informações',
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              'Remédio na Hora',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.icon,
    required this.title,
    required this.value,
    this.valueColor,
  });

  final IconData icon;
  final String title;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(title),
      trailing: Text(
        value,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: valueColor,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

class _PreferenceTile extends StatelessWidget {
  const _PreferenceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {},
    );
  }
}
