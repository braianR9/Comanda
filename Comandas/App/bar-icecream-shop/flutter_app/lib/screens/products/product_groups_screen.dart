import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../models/product_group.dart';
import '../../providers/auth_provider.dart';
import '../../providers/product_provider.dart';
import 'product_editor_screen.dart';

class ProductGroupsScreen extends StatefulWidget {
  final bool embedded;

  const ProductGroupsScreen({super.key, this.embedded = false});

  @override
  State<ProductGroupsScreen> createState() => _ProductGroupsScreenState();
}

class _ProductGroupsScreenState extends State<ProductGroupsScreen> {
  String? selectedRubroId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final session = context.read<AuthProvider>().session!;
      context
          .read<ProductProvider>()
          .load(session.idEmpresa, token: session.token);
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProductProvider>();
    final rubros = provider.groups.where((item) => !item.isSubgroup).toList();
    final selected = rubros.where((item) => item.id == selectedRubroId);
    final currentRubro = selected.isEmpty ? null : selected.first;
    final subrubros = currentRubro == null
        ? const <ProductGroup>[]
        : provider.groups
            .where((item) => item.parentId == currentRubro.id)
            .toList();

    final body = SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Rubros y subrubros',
                    style: GoogleFonts.poppins(
                      color: const Color(0xFF2D2260),
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    )),
                const SizedBox(height: 6),
                const Text(
                  'Seleccioná un rubro para ver y administrar sus subrubros.',
                  style: TextStyle(color: Color(0xFF6B6589)),
                ),
                const SizedBox(height: 20),
                if (provider.loading && provider.groups.isEmpty)
                  const Expanded(
                      child: Center(child: CircularProgressIndicator()))
                else if (provider.errorMessage != null &&
                    provider.groups.isEmpty)
                  Expanded(
                    child: Center(child: Text(provider.errorMessage!)),
                  )
                else
                  Expanded(
                    child: LayoutBuilder(builder: (context, constraints) {
                      final panels = [
                        _GroupPanel(
                          title: 'Rubros',
                          addLabel: 'Nuevo rubro',
                          items: rubros,
                          selectedId: currentRubro?.id,
                          emptyText: 'Todavía no hay rubros.',
                          onSelected: (item) =>
                              setState(() => selectedRubroId = item.id),
                          onAdd: _addRubro,
                        ),
                        _GroupPanel(
                          title: currentRubro == null
                              ? 'Subrubros'
                              : 'Subrubros de ${currentRubro.name}',
                          addLabel: 'Nuevo subrubro',
                          items: subrubros,
                          emptyText: currentRubro == null
                              ? 'Elegí un rubro para continuar.'
                              : 'Este rubro todavía no tiene subrubros.',
                          onSelected: (_) {},
                          onAdd: currentRubro == null
                              ? null
                              : () => _addSubrubro(currentRubro),
                        ),
                      ];
                      if (constraints.maxWidth < 720) {
                        return ListView.separated(
                          itemCount: panels.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 16),
                          itemBuilder: (_, index) =>
                              SizedBox(height: 360, child: panels[index]),
                        );
                      }
                      return Row(children: [
                        Expanded(child: panels[0]),
                        const SizedBox(width: 16),
                        Expanded(child: panels[1]),
                      ]);
                    }),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    return widget.embedded
        ? ColoredBox(color: const Color(0xFFF5F5F8), child: body)
        : Scaffold(backgroundColor: const Color(0xFFF5F5F8), body: body);
  }

  Future<void> _addRubro() async {
    final value = await showProductGroupDialog(context,
        isSubgroup: false, parentName: '', parentId: null);
    if (value == null || !mounted) return;
    final saved = await context.read<ProductProvider>().saveGroup(value);
    if (mounted) setState(() => selectedRubroId = saved.id);
  }

  Future<void> _addSubrubro(ProductGroup rubro) async {
    final value = await showProductGroupDialog(context,
        isSubgroup: true, parentName: rubro.name, parentId: rubro.id);
    if (value == null || !mounted) return;
    await context.read<ProductProvider>().saveGroup(value);
  }
}

class _GroupPanel extends StatelessWidget {
  final String title;
  final String addLabel;
  final List<ProductGroup> items;
  final String? selectedId;
  final String emptyText;
  final ValueChanged<ProductGroup> onSelected;
  final VoidCallback? onAdd;

  const _GroupPanel({
    required this.title,
    required this.addLabel,
    required this.items,
    required this.emptyText,
    required this.onSelected,
    required this.onAdd,
    this.selectedId,
  });

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE1DDEF)),
        ),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Expanded(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                        color: const Color(0xFF2D2260),
                        fontSize: 17,
                        fontWeight: FontWeight.w700)),
              ),
              FilledButton.tonalIcon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(addLabel),
              ),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(emptyText,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFF817A9E))),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(8),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 4),
                    itemBuilder: (_, index) {
                      final item = items[index];
                      final active = item.id == selectedId;
                      return ListTile(
                        selected: active,
                        selectedTileColor: const Color(0xFFEDE9FF),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFFF0EEF8),
                          child: Icon(
                              item.isSubgroup
                                  ? Icons.subdirectory_arrow_right_rounded
                                  : Icons.category_rounded,
                              color: const Color(0xFF6C5CE7)),
                        ),
                        title: Text(item.name),
                        subtitle: item.description.isEmpty
                            ? null
                            : Text(item.description,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: active
                            ? const Icon(Icons.chevron_right_rounded)
                            : null,
                        onTap: () => onSelected(item),
                      );
                    },
                  ),
          ),
        ]),
      );
}
