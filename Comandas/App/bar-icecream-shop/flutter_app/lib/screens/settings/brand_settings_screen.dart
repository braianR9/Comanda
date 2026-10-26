import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../theme/brand_colors.dart';

/// Paleta de colores de la sucursal. El color se aplica al instante y se guarda
/// en este navegador o dispositivo.
class BrandSettingsScreen extends StatefulWidget {
  const BrandSettingsScreen({super.key});
  @override
  State<BrandSettingsScreen> createState() => _BrandSettingsScreenState();
}

class _BrandSettingsScreenState extends State<BrandSettingsScreen> {
  final _hex = TextEditingController();
  String? _hexError;

  @override
  void initState() {
    super.initState();
    _hex.text = toHex(Brand.base);
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  Future<void> _choose(Color color) async {
    await context.read<BrandProvider>().save(color);
    if (!mounted) return;
    setState(() {
      _hex.text = toHex(color);
      _hexError = null;
    });
  }

  void _applyHex() {
    final color = parseHexColor(_hex.text);
    if (color == null) {
      setState(
          () => _hexError = 'Usá el formato #RRGGBB, por ejemplo #2F6FDE.');
      return;
    }
    _choose(color);
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.watch<BrandProvider>();
    final branch = context.watch<AuthProvider>().session?.sucursal.nombre ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('Colores de la sucursal')),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        Text(
            'Elegí el color principal${branch.isEmpty ? '' : ' de $branch'}. Se aplica al instante en todo el sistema y se guarda en este navegador: cada computadora o tablet de la sucursal puede tener el suyo.',
            style: TextStyle(color: Brand.subtle)),
        const SizedBox(height: 24),
        Text('Paleta',
            style: TextStyle(
                fontWeight: FontWeight.w700, color: Brand.ink, fontSize: 16)),
        const SizedBox(height: 12),
        Wrap(spacing: 16, runSpacing: 16, children: [
          for (final (name, color) in brandPresets)
            _Swatch(
                name: name,
                color: color,
                selected: brand.color == color,
                onTap: () => _choose(color)),
        ]),
        const SizedBox(height: 28),
        Text('Color personalizado',
            style: TextStyle(
                fontWeight: FontWeight.w700, color: Brand.ink, fontSize: 16)),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 220,
            child: TextField(
              controller: _hex,
              maxLength: 7,
              decoration: InputDecoration(
                  labelText: 'Código (#RRGGBB)',
                  counterText: '',
                  errorText: _hexError,
                  prefixIcon: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                            color:
                                parseHexColor(_hex.text) ?? Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.black12))),
                  )),
              onChanged: (_) => setState(() => _hexError = null),
              onSubmitted: (_) => _applyHex(),
            ),
          ),
          const SizedBox(width: 12),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: FilledButton(
                onPressed: _applyHex, child: const Text('Aplicar')),
          ),
        ]),
        if (Brand.isTooLight(brand.color))
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
                'Es un color muy claro: el texto blanco de la barra lateral y los botones puede costar leerse. Probá con un tono más oscuro.',
                style: TextStyle(color: Colors.orange.shade900)),
          ),
        const SizedBox(height: 28),
        Text('Vista previa',
            style: TextStyle(
                fontWeight: FontWeight.w700, color: Brand.ink, fontSize: 16)),
        const SizedBox(height: 12),
        const _Preview(),
        const SizedBox(height: 28),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
              onPressed:
                  brand.isDefault ? null : () => _choose(Brand.defaultColor),
              icon: const Icon(Icons.restart_alt),
              label: const Text('Volver al lila original')),
        ),
      ]),
    );
  }
}

class _Swatch extends StatelessWidget {
  final String name;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _Swatch(
      {required this.name,
      required this.color,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: '$name · ${toHex(color)}',
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                    color: selected ? Brand.ink : Colors.white, width: 3),
                boxShadow: const [
                  BoxShadow(
                      color: Colors.black12,
                      blurRadius: 6,
                      offset: Offset(0, 2))
                ],
              ),
              child: selected
                  ? Icon(Icons.check_rounded,
                      color: ThemeData.estimateBrightnessForColor(color) ==
                              Brightness.dark
                          ? Colors.white
                          : Colors.black87)
                  : null,
            ),
            const SizedBox(height: 6),
            Text(name, style: TextStyle(fontSize: 12, color: Brand.subtle)),
          ]),
        ),
      );
}

/// Muestra cómo se ven la barra lateral, el menú y los botones con el color actual.
class _Preview extends StatelessWidget {
  const _Preview();
  @override
  Widget build(BuildContext context) => Container(
        height: 170,
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Brand.surface),
            color: Colors.white),
        clipBehavior: Clip.antiAlias,
        child: Row(children: [
          Container(
            width: 150,
            color: Brand.primary,
            padding: const EdgeInsets.all(14),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('ACCESOS',
                  style: TextStyle(
                      color: Brand.onPrimary.withValues(alpha: 0.7),
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              for (final (icon, label) in const [
                (Icons.point_of_sale_rounded, 'Salón'),
                (Icons.storefront_rounded, 'Mostrador'),
                (Icons.inventory_2_outlined, 'Caja'),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    Icon(icon, size: 18, color: Brand.onPrimary),
                    const SizedBox(width: 8),
                    Text(label, style: TextStyle(color: Brand.onPrimary)),
                  ]),
                ),
            ]),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                          color: Brand.tint,
                          borderRadius: BorderRadius.circular(8)),
                      child: Text('Ventas',
                          style: TextStyle(
                              color: Brand.strong,
                              fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(height: 10),
                    Text('Mesa 4 · 2 productos',
                        style: TextStyle(
                            color: Brand.ink, fontWeight: FontWeight.w600)),
                    Text('Pedido enviado a cocina',
                        style: TextStyle(color: Brand.subtle)),
                    const Spacer(),
                    Row(children: [
                      FilledButton(
                          onPressed: () {}, child: const Text('Cobrar')),
                      const SizedBox(width: 10),
                      OutlinedButton(
                          onPressed: () {}, child: const Text('Imprimir')),
                    ]),
                  ]),
            ),
          ),
        ]),
      );
}
