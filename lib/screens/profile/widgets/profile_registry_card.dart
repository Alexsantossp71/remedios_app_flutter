import 'package:material_ui/material_ui.dart';

import '../../../core/design/record_card.dart';
import '../../doctors_screen.dart';
import '../../exams_screen.dart';
import '../../health_plans_screen.dart';
import '../../lab_results_screen.dart';
import '../../progress_screen.dart';
import 'cadastro_icon_box.dart';

/// Card "Meus cadastros": atalhos de navegação para as telas de
/// médicos, exames, resultados de laboratório, planos e progresso.
class ProfileRegistryCard extends StatelessWidget {
  const ProfileRegistryCard({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return RecordCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          ListTile(
            leading: CadastroIconBox(
              icon: Icons.medical_services_outlined,
              isDark: isDark,
            ),
            title: const Text('Médicos'),
            subtitle: const Text('Seu catálogo de médicos e contatos'),
            trailing: Icon(
              Icons.chevron_right,
              color: Theme.of(context).colorScheme.outline,
            ),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const DoctorsScreen()),
              );
            },
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            leading: CadastroIconBox(
              icon: Icons.science_outlined,
              isDark: isDark,
            ),
            title: const Text('Exames'),
            subtitle: const Text(
              'Do pedido do médico ao laudo, com leitura por IA',
            ),
            trailing: Icon(
              Icons.chevron_right,
              color: Theme.of(context).colorScheme.outline,
            ),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const ExamsScreen()),
              );
            },
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            leading: CadastroIconBox(
              icon: Icons.biotech_outlined,
              isDark: isDark,
            ),
            title: const Text('Resultados de laboratório'),
            subtitle: const Text('Laudos, valores e evolução dos exames'),
            trailing: Icon(
              Icons.chevron_right,
              color: Theme.of(context).colorScheme.outline,
            ),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const LabResultsScreen(),
                ),
              );
            },
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            leading: CadastroIconBox(
              icon: Icons.health_and_safety,
              isDark: isDark,
            ),
            title: const Text('Planos e convênios'),
            subtitle: const Text('Gerencie seus planos de saúde'),
            trailing: Icon(
              Icons.chevron_right,
              color: Theme.of(context).colorScheme.outline,
            ),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const HealthPlansScreen(),
                ),
              );
            },
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            leading: CadastroIconBox(
              icon: Icons.insights_outlined,
              isDark: isDark,
            ),
            title: const Text('Progresso'),
            subtitle: const Text('Constância e histórico de doses'),
            trailing: Icon(
              Icons.chevron_right,
              color: Theme.of(context).colorScheme.outline,
            ),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const ProgressScreen()),
              );
            },
          ),
        ],
      ),
    );
  }
}
