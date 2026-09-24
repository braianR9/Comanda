import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../models/caja.dart';
import '../../providers/auth_provider.dart';
import '../../providers/caja_provider.dart';

const _kRolesAutorizados = {'ADMIN', 'ENCARGADO'};

class CajaScreen extends StatefulWidget {
  final bool embedded;
  const CajaScreen({super.key, this.embedded = false});

  @override
  State<CajaScreen> createState() => _CajaScreenState();
}

class _CajaScreenState extends State<CajaScreen> {
  bool _initialLoading = true;

  bool get _puedeGestionar => _kRolesAutorizados
      .contains(context.read<AuthProvider>().session!.rol.nombre);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final token = context.read<AuthProvider>().session!.token;
    final provider = context.read<CajaProvider>();
    await Future.wait([provider.load(token), provider.loadHistory()]);
    if (mounted) setState(() => _initialLoading = false);
  }

  Future<void> _abrir() async {
    final result = await showDialog<_AbrirCajaResult>(
      context: context,
      builder: (_) => const _AbrirCajaDialog(),
    );
    if (result == null || !mounted) return;
    try {
      await context.read<CajaProvider>().abrir(
          montoInicial: result.montoInicial,
          observaciones: result.observaciones);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Caja abierta correctamente.')));
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _cerrar() async {
    final caja = context.read<CajaProvider>().current;
    if (caja == null) return;
    final confirmed = await showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CerrarCajaDialog(caja: caja),
    );
    if (confirmed == null || !mounted) return;
    try {
      final closed = await context.read<CajaProvider>().cerrar(
          observaciones: confirmed.trim().isEmpty ? null : confirmed.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Caja cerrada. Se guardó en el historial.')));
      await showDialog(
          context: context, builder: (_) => _CajaDetailDialog(caja: closed));
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _movimiento() async {
    final result = await showDialog<_MovimientoResult>(
      context: context,
      builder: (_) => const _MovimientoDialog(),
    );
    if (result == null || !mounted) return;
    try {
      await context.read<CajaProvider>().agregarMovimiento(
          tipo: result.tipo, monto: result.monto, motivo: result.motivo);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Movimiento registrado.')));
    } catch (error) {
      _showError(error);
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error.toString().replaceFirst('Exception: ', ''))));
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CajaProvider>();
    final content = SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: _initialLoading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 100),
                    children: [
                      Text('Caja',
                          style: GoogleFonts.poppins(
                              color: const Color(0xFF2D2260),
                              fontSize: 26,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 20),
                      _CajaStatusCard(
                        caja: provider.current,
                        canManage: _puedeGestionar,
                        onAbrir: _abrir,
                        onCerrar: _cerrar,
                        onMovimiento: _movimiento,
                      ),
                      const SizedBox(height: 28),
                      Text('Historial de cajas',
                          style: GoogleFonts.poppins(
                              color: const Color(0xFF2D2260),
                              fontSize: 18,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 12),
                      if (provider.history.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Text('Todavía no hay cajas cerradas.',
                              style: GoogleFonts.poppins(
                                  color: const Color(0xFF9E8FCC))),
                        )
                      else
                        ...provider.history.map((caja) => _CajaHistoryTile(
                              caja: caja,
                              onTap: () => showDialog(
                                  context: context,
                                  builder: (_) =>
                                      _CajaDetailDialog(caja: caja)),
                            )),
                    ],
                  ),
                ),
        ),
      ),
    );
    return widget.embedded
        ? ColoredBox(color: const Color(0xFFF5F5F8), child: content)
        : Scaffold(backgroundColor: const Color(0xFFF5F5F8), body: content);
  }
}

class _CajaStatusCard extends StatelessWidget {
  final Caja? caja;
  final bool canManage;
  final VoidCallback onAbrir;
  final VoidCallback onCerrar;
  final VoidCallback onMovimiento;
  const _CajaStatusCard({
    required this.caja,
    required this.canManage,
    required this.onAbrir,
    required this.onCerrar,
    required this.onMovimiento,
  });

  @override
  Widget build(BuildContext context) {
    final abierta = caja?.abierta ?? false;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(
            abierta ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
            color: abierta ? const Color(0xFF6DA544) : Colors.grey,
          ),
          const SizedBox(width: 8),
          Text(abierta ? 'Caja abierta' : 'Caja cerrada',
              style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: abierta
                      ? const Color(0xFF6DA544)
                      : Colors.grey.shade700)),
        ]),
        const SizedBox(height: 16),
        if (caja == null)
          Text('No hay ninguna caja abierta en esta sucursal.',
              style: GoogleFonts.poppins(color: const Color(0xFF6B6280)))
        else ...[
          _row('Abierta por',
              '${caja!.usuarioApertura} · ${_fmt(caja!.fechaApertura)}'),
          _row('Monto inicial', '\$${caja!.montoInicial.toStringAsFixed(2)}'),
          if (abierta) ...[
            _row('Total vendido (a la fecha)',
                '\$${(caja!.totalVentas ?? 0).toStringAsFixed(2)}'),
            _row('Efectivo esperado en caja',
                '\$${(caja!.totalEfectivoEsperado ?? 0).toStringAsFixed(2)}'),
          ],
          if (caja!.detalle.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Por medio de pago',
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF2D2260))),
            for (final item in caja!.detalle)
              _row(item.medioPago, '\$${item.total.toStringAsFixed(2)}'),
          ],
        ],
        const SizedBox(height: 16),
        if (!canManage)
          Text(
              abierta
                  ? 'No podés cerrar la caja: pedile a un encargado o admin.'
                  : 'No podés abrir la caja: pedile a un encargado o admin.',
              style: GoogleFonts.poppins(
                  color: Colors.orange.shade800, fontSize: 13))
        else
          Wrap(spacing: 12, runSpacing: 8, children: [
            if (abierta) ...[
              OutlinedButton.icon(
                  onPressed: onMovimiento,
                  icon: const Icon(Icons.swap_vert_rounded),
                  label: const Text('Ingreso / egreso')),
              FilledButton.icon(
                  onPressed: onCerrar,
                  icon: const Icon(Icons.lock_outline_rounded),
                  label: const Text('Cerrar caja')),
            ] else
              FilledButton.icon(
                  onPressed: onAbrir,
                  icon: const Icon(Icons.lock_open_rounded),
                  label: const Text('Abrir caja')),
          ]),
      ]),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(
              child: Text(label,
                  style: GoogleFonts.poppins(color: const Color(0xFF6B6280)))),
          Text(value,
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700, color: const Color(0xFF2D2260))),
        ]),
      );
}

class _CajaHistoryTile extends StatelessWidget {
  final Caja caja;
  final VoidCallback onTap;
  const _CajaHistoryTile({required this.caja, required this.onTap});

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.shade200)),
        child: ListTile(
          onTap: onTap,
          leading: Icon(
              caja.abierta
                  ? Icons.lock_open_rounded
                  : Icons.lock_outline_rounded,
              color: caja.abierta ? const Color(0xFF6DA544) : Colors.grey),
          title: Text(
              '${_fmt(caja.fechaApertura)}'
              '${caja.fechaCierre != null ? ' — ${_fmt(caja.fechaCierre!)}' : ''}',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          subtitle: Text(
              'Abrió: ${caja.usuarioApertura}'
              '${caja.usuarioCierre != null ? ' · Cerró: ${caja.usuarioCierre}' : ''}',
              style: GoogleFonts.poppins(
                  fontSize: 12, color: const Color(0xFF9E8FCC))),
          trailing: Text(
              caja.abierta
                  ? 'Abierta'
                  : '\$${(caja.totalEfectivoEsperado ?? 0).toStringAsFixed(2)}',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        ),
      );
}

class _CajaDetailDialog extends StatefulWidget {
  final Caja caja;
  const _CajaDetailDialog({required this.caja});

  @override
  State<_CajaDetailDialog> createState() => _CajaDetailDialogState();
}

class _CajaDetailDialogState extends State<_CajaDetailDialog> {
  bool _printing = false;

  Future<void> _imprimir() async {
    setState(() => _printing = true);
    try {
      await context.read<CajaProvider>().enqueuePrint(widget.caja.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enviado a la impresora.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final caja = widget.caja;
    return AlertDialog(
      title: Text(caja.abierta ? 'Caja abierta' : 'Caja cerrada'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _detailRow('Abierta por',
                    '${caja.usuarioApertura} · ${_fmt(caja.fechaApertura)}'),
                if (caja.fechaCierre != null)
                  _detailRow('Cerrada por',
                      '${caja.usuarioCierre ?? '—'} · ${_fmt(caja.fechaCierre!)}'),
                _detailRow('Monto inicial',
                    '\$${caja.montoInicial.toStringAsFixed(2)}'),
                _detailRow('Total vendido',
                    '\$${(caja.totalVentas ?? 0).toStringAsFixed(2)}'),
                _detailRow('Ingresos manuales',
                    '\$${(caja.totalIngresos ?? 0).toStringAsFixed(2)}'),
                _detailRow('Egresos manuales',
                    '\$${(caja.totalEgresos ?? 0).toStringAsFixed(2)}'),
                _detailRow('Efectivo esperado',
                    '\$${(caja.totalEfectivoEsperado ?? 0).toStringAsFixed(2)}'),
                if (caja.observaciones?.isNotEmpty ?? false)
                  _detailRow('Observaciones', caja.observaciones!),
                if (caja.detalle.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('Por medio de pago',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
                  for (final item in caja.detalle)
                    _detailRow(
                        item.medioPago, '\$${item.total.toStringAsFixed(2)}'),
                ],
                if (caja.movimientos.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('Movimientos manuales',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
                  for (final movimiento in caja.movimientos)
                    _detailRow(
                        '${movimiento.isIngreso ? '+' : '-'} ${movimiento.motivo}',
                        '\$${movimiento.monto.toStringAsFixed(2)}'),
                ],
              ]),
        ),
      ),
      actions: [
        if (!caja.abierta)
          OutlinedButton.icon(
              onPressed: _printing ? null : _imprimir,
              icon: _printing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.print_outlined),
              label: const Text('Imprimir')),
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar')),
      ],
    );
  }
}

Widget _detailRow(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
            child: Text(label,
                style: GoogleFonts.poppins(color: const Color(0xFF6B6280)))),
        Flexible(
            child: Text(value,
                textAlign: TextAlign.right,
                style: GoogleFonts.poppins(fontWeight: FontWeight.w700))),
      ]),
    );

class _AbrirCajaResult {
  final double montoInicial;
  final String? observaciones;
  const _AbrirCajaResult(this.montoInicial, this.observaciones);
}

class _AbrirCajaDialog extends StatefulWidget {
  const _AbrirCajaDialog();
  @override
  State<_AbrirCajaDialog> createState() => _AbrirCajaDialogState();
}

class _AbrirCajaDialogState extends State<_AbrirCajaDialog> {
  final _formKey = GlobalKey<FormState>();
  final _monto = TextEditingController(text: '0');
  final _observaciones = TextEditingController();

  @override
  void dispose() {
    _monto.dispose();
    _observaciones.dispose();
    super.dispose();
  }

  void _confirm() {
    if (!_formKey.currentState!.validate()) return;
    final monto = double.tryParse(_monto.text.replaceAll(',', '.')) ?? 0;
    Navigator.pop(
        context,
        _AbrirCajaResult(
            monto,
            _observaciones.text.trim().isEmpty
                ? null
                : _observaciones.text.trim()));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Abrir caja'),
        content: Form(
          key: _formKey,
          child: SizedBox(
            width: 380,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                controller: _monto,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Monto inicial en caja', prefixText: '\$ '),
                validator: (value) {
                  final parsed =
                      double.tryParse((value ?? '').replaceAll(',', '.'));
                  if (parsed == null || parsed < 0)
                    return 'Ingresá un monto válido.';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _observaciones,
                maxLines: 2,
                decoration: const InputDecoration(
                    labelText: 'Observaciones (opcional)',
                    border: OutlineInputBorder()),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(onPressed: _confirm, child: const Text('Abrir caja')),
        ],
      );
}

class _CerrarCajaDialog extends StatefulWidget {
  final Caja caja;
  const _CerrarCajaDialog({required this.caja});
  @override
  State<_CerrarCajaDialog> createState() => _CerrarCajaDialogState();
}

class _CerrarCajaDialogState extends State<_CerrarCajaDialog> {
  final _observaciones = TextEditingController();

  @override
  void dispose() {
    _observaciones.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final caja = context.watch<CajaProvider>().current ?? widget.caja;
    return AlertDialog(
      title: const Text('Cerrar caja'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    'Se va a cerrar la caja abierta por ${caja.usuarioApertura} el '
                    '${_fmt(caja.fechaApertura)}.',
                    style: GoogleFonts.poppins()),
                const SizedBox(height: 12),
                _row('Monto inicial',
                    '\$${caja.montoInicial.toStringAsFixed(2)}'),
                _row('Total vendido',
                    '\$${(caja.totalVentas ?? 0).toStringAsFixed(2)}'),
                for (final item in caja.detalle)
                  _row(item.medioPago, '\$${item.total.toStringAsFixed(2)}'),
                const Divider(),
                _row('Efectivo esperado en caja',
                    '\$${(caja.totalEfectivoEsperado ?? 0).toStringAsFixed(2)}',
                    highlight: true),
                const SizedBox(height: 12),
                TextField(
                  controller: _observaciones,
                  maxLines: 2,
                  decoration: const InputDecoration(
                      labelText: 'Observaciones (opcional)',
                      border: OutlineInputBorder()),
                ),
              ]),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
            onPressed: () => Navigator.pop(context, _observaciones.text),
            child: const Text('Confirmar cierre')),
      ],
    );
  }

  Widget _row(String label, String value, {bool highlight = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(
              child: Text(label,
                  style: GoogleFonts.poppins(
                      color: highlight
                          ? const Color(0xFF2D2260)
                          : const Color(0xFF6B6280),
                      fontWeight:
                          highlight ? FontWeight.w700 : FontWeight.w400))),
          Text(value,
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700,
                  fontSize: highlight ? 16 : 14,
                  color: const Color(0xFF2D2260))),
        ]),
      );
}

class _MovimientoResult {
  final String tipo;
  final double monto;
  final String motivo;
  const _MovimientoResult(this.tipo, this.monto, this.motivo);
}

class _MovimientoDialog extends StatefulWidget {
  const _MovimientoDialog();
  @override
  State<_MovimientoDialog> createState() => _MovimientoDialogState();
}

class _MovimientoDialogState extends State<_MovimientoDialog> {
  final _formKey = GlobalKey<FormState>();
  final _monto = TextEditingController();
  final _motivo = TextEditingController();
  String _tipo = 'Ingreso';

  @override
  void dispose() {
    _monto.dispose();
    _motivo.dispose();
    super.dispose();
  }

  void _confirm() {
    if (!_formKey.currentState!.validate()) return;
    final monto = double.tryParse(_monto.text.replaceAll(',', '.')) ?? 0;
    Navigator.pop(
        context, _MovimientoResult(_tipo, monto, _motivo.text.trim()));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Registrar movimiento de caja'),
        content: Form(
          key: _formKey,
          child: SizedBox(
            width: 380,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'Ingreso', label: Text('Ingreso')),
                  ButtonSegment(value: 'Egreso', label: Text('Egreso')),
                ],
                selected: {_tipo},
                onSelectionChanged: (value) =>
                    setState(() => _tipo = value.first),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _monto,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Monto', prefixText: '\$ '),
                validator: (value) {
                  final parsed =
                      double.tryParse((value ?? '').replaceAll(',', '.'));
                  if (parsed == null || parsed <= 0)
                    return 'Ingresá un monto válido.';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _motivo,
                decoration: const InputDecoration(
                    labelText: 'Motivo', border: OutlineInputBorder()),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Indicá un motivo.'
                    : null,
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(onPressed: _confirm, child: const Text('Registrar')),
        ],
      );
}

String _fmt(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year} '
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
