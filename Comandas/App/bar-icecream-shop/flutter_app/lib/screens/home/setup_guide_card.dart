import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/brand_colors.dart';
import '../purchases/purchase_api.dart';

/// Guía de puesta en marcha: lo que falta configurar antes de empezar a operar.
/// Cada paso lleva a la sección donde se completa.
class SetupGuideCard extends StatefulWidget {
  final String token;

  /// Secciones a las que puede entrar el usuario actual.
  final Set<int> allowedSections;
  final ValueChanged<int> onNavigate;

  /// En Configuración la guía se muestra siempre y abierta, aunque esté todo listo.
  final bool alwaysVisible;
  const SetupGuideCard(
      {super.key,
      required this.token,
      required this.allowedSections,
      required this.onNavigate,
      this.alwaysVisible = false});

  @override
  State<SetupGuideCard> createState() => _SetupGuideCardState();
}

class _SetupGuideCardState extends State<SetupGuideCard> {
  /// Sección del menú donde se configura cada paso.
  static const _sections = <String, int>{
    'empresa': 15,
    'mesas': 3,
    'rubros': 2,
    'productos': 1,
    'impresoras': 6,
    'pagos': 5,
    'usuarios': 9,
    'fiscal': 15,
    'arca': 15,
  };

  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await PurchaseApi(widget.token).call('puesta-en-marcha');
      if (mounted) setState(() => _data = Map<String, dynamic>.from(data));
    } catch (_) {
      // Si la API no responde, la guía simplemente no se muestra.
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (data == null) {
      return widget.alwaysVisible
          ? const Center(child: CircularProgressIndicator())
          : const SizedBox.shrink();
    }
    final steps = (data['steps'] as List)
        .map((s) => Map<String, dynamic>.from(s as Map))
        .toList();
    final pendingRequired = data['pendingRequired'] as int? ?? 0;
    final pendingOptional = data['pendingOptional'] as int? ?? 0;
    if (pendingRequired == 0 && pendingOptional == 0 && !widget.alwaysVisible) {
      return const SizedBox.shrink();
    }
    final done = steps.where((s) => s['done'] == true).length;
    final required = steps.where((s) => s['optional'] != true).toList();
    final optional = steps.where((s) => s['optional'] == true).toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: widget.alwaysVisible || pendingRequired > 0,
          tilePadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
          childrenPadding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
          shape: const RoundedRectangleBorder(),
          title: Text('Puesta en marcha',
              style: GoogleFonts.fraunces(
                  color: Brand.ink, fontSize: 22, fontWeight: FontWeight.w600)),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 8),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  pendingRequired > 0
                      ? 'Te ${pendingRequired == 1 ? 'falta 1 paso' : 'faltan $pendingRequired pasos'} para empezar a operar.'
                      : pendingOptional > 0
                          ? 'El local ya puede operar. Quedan pasos opcionales.'
                          : 'Todo configurado.',
                  style:
                      GoogleFonts.workSans(color: Brand.muted, fontSize: 13)),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: done / steps.length,
                  minHeight: 6,
                  backgroundColor: Brand.tint,
                  color: Brand.primary,
                ),
              ),
            ]),
          ),
          children: [
            for (final step in required) _step(step),
            if (optional.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('OPCIONALES',
                      style: GoogleFonts.workSans(
                          color: Brand.muted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.2)),
                ),
              ),
              for (final step in optional) _step(step),
            ],
          ],
        ),
      ),
    );
  }

  Widget _step(Map<String, dynamic> step) {
    final done = step['done'] == true;
    final section = _sections[step['key']];
    final canOpen = section != null && widget.allowedSections.contains(section);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Icon(
            done
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            color: done ? const Color(0xFF10B981) : Brand.muted,
            size: 22),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(step['title'] as String,
                style: GoogleFonts.workSans(
                    color: Brand.strong,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    decoration: done ? TextDecoration.lineThrough : null)),
            Text(step['detail'] as String,
                style:
                    GoogleFonts.workSans(color: Brand.muted, fontSize: 12.5)),
          ]),
        ),
        if (!done && canOpen)
          TextButton(
              onPressed: () => widget.onNavigate(section),
              child: const Text('Configurar')),
      ]),
    );
  }
}
