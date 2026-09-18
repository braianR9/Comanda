import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../models/product.dart';
import '../../models/payment_amounts.dart';
import '../../models/restaurant_table.dart';
import '../../models/sector.dart';
import '../../providers/auth_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/sales_provider.dart';
import '../../providers/sector_provider.dart';
import '../auth/login_screen.dart';

class SalesScreen extends StatefulWidget {
  final bool embedded;

  const SalesScreen({super.key, this.embedded = false});

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  final Map<int, _OrderDraft> _orders = {};
  int? _selectedSectorId;
  int? _selectedTableId;
  DateTime? _tableOpenedAt;
  String _productSearch = '';
  bool _productsAsGrid = true;
  Timer? _occupationTimer;
  bool _operationInProgress = false;

  @override
  void initState() {
    super.initState();
    _occupationTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && _orders.values.any((order) => order.openedAt != null)) {
        setState(() {});
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final session = context.read<AuthProvider>().session!;
      context
          .read<SalesProvider>()
          .configure(token: session.token, userId: session.id);
      await Future.wait([
        context.read<SectorProvider>().load(token: session.token),
        context.read<ProductProvider>().load(
              session.idEmpresa,
              token: session.token,
            ),
      ]);
      if (!mounted) return;
      await _restoreActiveSales();
    });
  }

  @override
  void dispose() {
    _occupationTimer?.cancel();
    super.dispose();
  }

  Future<void> _restoreActiveSales() async {
    try {
      final salesProvider = context.read<SalesProvider>();
      final productProvider = context.read<ProductProvider>();
      final sales = await salesProvider.getActiveSales();
      final products = productProvider.products;
      if (!mounted) return;
      setState(() {
        for (final sale in sales) {
          final draft = _OrderDraft(sale.tableId)..updateFromServer(sale);
          for (final item in sale.items) {
            final product = products
                    .where((value) => value.id == '${item.productId}')
                    .firstOrNull ??
                Product(
                    id: '${item.productId}',
                    name: item.name,
                    category: '',
                    price: item.unitPrice);
            draft.lines.add(_OrderLine(product.copyWith(price: item.unitPrice))
              ..quantity = item.quantity
              ..comment = item.comment);
          }
          draft.joinedTableIds.addAll(sale.joinedTableIds);
          draft.markAsSent();
          draft.metadataDirty = sale.status == 'ConCambios';
          _orders[draft.tableId] = draft;
        }
      });
    } catch (error) {
      _showApiError(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = _selectedTableId == null
        ? _buildTableSelection()
        : _buildOrderWorkspace(_selectedTableId!);
    final guardedBody = Stack(children: [
      AbsorbPointer(absorbing: _operationInProgress, child: body),
      if (_operationInProgress)
        const Positioned.fill(
          child: ColoredBox(
            color: Color(0x33000000),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
    ]);
    return PopScope(
      canPop: !_operationInProgress,
      child: widget.embedded
          ? ColoredBox(color: const Color(0xFFF5F5F8), child: guardedBody)
          : Scaffold(
              backgroundColor: const Color(0xFFF5F5F8), body: guardedBody),
    );
  }

  /// Un empleado con sector asignado solo ve ese sector; sin asignación, ve todos.
  List<Sector> _visibleSectors(SectorProvider provider) {
    final sectors = provider.sectors.where((item) => item.active).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    final assignedSectorId =
        context.read<AuthProvider>().session?.idSectorAsignado;
    if (assignedSectorId == null) return sectors;
    return sectors.where((sector) => sector.id == assignedSectorId).toList();
  }

  bool _isTableVisible(RestaurantTable table) {
    final session = context.read<AuthProvider>().session;
    if (session == null) return true;
    if (session.idSectorAsignado != null &&
        table.sectorId != session.idSectorAsignado) {
      return false;
    }
    return !session.mesasExcluidasIds.contains(table.id);
  }

  Widget _buildTableSelection() {
    final sectorProvider = context.watch<SectorProvider>();
    final sectors = _visibleSectors(sectorProvider);
    if (_selectedSectorId == null && sectors.isNotEmpty) {
      _selectedSectorId = sectors.first.id;
    }
    final tables = sectorProvider.tables
        .where((table) =>
            table.active &&
            (_selectedSectorId == null ||
                table.sectorId == _selectedSectorId) &&
            _isTableVisible(table))
        .toList();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 30),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
                child: _title('Ventas', 'Seleccioná un sector y una mesa')),
            _SaleLegend(),
          ]),
          const SizedBox(height: 18),
          if (sectorProvider.loading && sectors.isEmpty)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (sectorProvider.errorMessage != null && sectors.isEmpty)
            Expanded(child: Center(child: Text(sectorProvider.errorMessage!)))
          else ...[
            SizedBox(
              height: 46,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: sectors.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, index) {
                  final sector = sectors[index];
                  return ChoiceChip(
                    avatar: const Icon(Icons.grid_view_rounded, size: 17),
                    label: Text(sector.name),
                    selected: sector.id == _selectedSectorId,
                    onSelected: (_) =>
                        setState(() => _selectedSectorId = sector.id),
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 1200),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFDFDFC),
                      borderRadius: BorderRadius.circular(24),
                      border:
                          Border.all(color: const Color(0xFFB9B9B4), width: 2),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: tables.isEmpty
                        ? const Center(
                            child: Text('No hay mesas en este sector.'))
                        : LayoutBuilder(builder: (context, constraints) {
                            return Stack(children: [
                              for (final table in tables)
                                Positioned(
                                  left: table.positionX *
                                      (constraints.maxWidth -
                                          _saleTableSize(table).width),
                                  top: table.positionY *
                                      (constraints.maxHeight -
                                          _saleTableSize(table).height),
                                  width: _saleTableSize(table).width,
                                  height: _saleTableSize(table).height,
                                  child: _SaleTableCard(
                                    table: table,
                                    order: _orderForTable(table.id),
                                    joined: _isJoinedTable(table.id),
                                    onTap: () => setState(() {
                                      _selectedTableId =
                                          _ownerTableId(table.id);
                                      _tableOpenedAt = DateTime.now();
                                    }),
                                  ),
                                ),
                            ]);
                          }),
                  ),
                ),
              ),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _buildOrderWorkspace(int tableId) {
    final sectorProvider = context.watch<SectorProvider>();
    final tableMatches =
        sectorProvider.tables.where((item) => item.id == tableId);
    if (tableMatches.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => mounted ? setState(() => _selectedTableId = null) : null);
      return const SizedBox.shrink();
    }
    final table = tableMatches.first;
    final sector = sectorProvider.sectors
        .where((item) => item.id == table.sectorId)
        .firstOrNull;
    final order = _orders.putIfAbsent(tableId, () => _OrderDraft(tableId));
    final products = context.watch<ProductProvider>().products.where((product) {
      final query = _productSearch.trim().toLowerCase();
      return product.active &&
          product.showSalon &&
          (query.isEmpty ||
              product.name.toLowerCase().contains(query) ||
              product.code.toLowerCase().contains(query));
    }).toList();

    return SafeArea(
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          color: Colors.white,
          child: Row(children: [
            IconButton(
              onPressed: () => _leaveTable(order),
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: 'Volver a las mesas',
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(table.name,
                      style: GoogleFonts.poppins(
                          color: const Color(0xFF2D2260),
                          fontSize: 20,
                          fontWeight: FontWeight.w700)),
                  Text('${sector?.name ?? 'Sector'} · ${_status(order)}',
                      style: const TextStyle(color: Color(0xFF6B6589))),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: order.editLocked ? null : () => _selectWaiter(order),
              icon: const Icon(Icons.person_outline_rounded),
              label: Text(order.waiter ?? 'Sin mozo'),
            ),
            const SizedBox(width: 8),
            PopupMenuButton<String>(
              tooltip: 'Acciones de mesa',
              enabled: !order.editLocked,
              onSelected: (value) {
                if (value == 'move') _moveOrder(order);
                if (value == 'join') _joinOrder(order);
                if (value == 'clear') _clearOrder(order);
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                    value: 'move',
                    enabled: order.joinedTableIds.isEmpty,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Cambiar de mesa'),
                        if (order.joinedTableIds.isNotEmpty)
                          const Text('No disponible con mesas unidas',
                              style: TextStyle(fontSize: 12)),
                      ],
                    )),
                PopupMenuItem(
                    value: 'join',
                    enabled: order.sent && !order.hasPendingChanges,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Unir mesas'),
                        if (!order.sent || order.hasPendingChanges)
                          const Text('Primero enviá el pedido o sus cambios',
                              style: TextStyle(fontSize: 12)),
                      ],
                    )),
                if (!order.sent && order.lines.isEmpty)
                  const PopupMenuItem(
                      value: 'clear', child: Text('Anular mesa')),
              ],
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: Icon(Icons.more_vert_rounded),
              ),
            ),
          ]),
        ),
        Expanded(
          child: LayoutBuilder(builder: (context, constraints) {
            final compact = constraints.maxWidth < 850;
            final catalog = _ProductCatalog(
              products: products,
              search: _productSearch,
              asGrid: _productsAsGrid,
              onSearch: (value) => setState(() => _productSearch = value),
              onViewChanged: (value) => setState(() => _productsAsGrid = value),
              onAdd: (product) => _addProduct(order, product),
            );
            final ticket = _OrderTicket(
              order: order,
              onIncrease: (line) => _changeQuantity(order, line, 1),
              onDecrease: (line) => _changeQuantity(order, line, -1),
              onRemove: (line) => _removeLine(order, line),
              onComment: (line) => _editLineComment(order, line),
              onDiscount:
                  order.editLocked || (order.sent && order.hasPendingChanges)
                      ? null
                      : () => _applyDiscount(order),
              onSend: !order.editLocked && order.canSend
                  ? () => _sendOrder(order, table)
                  : null,
              onCheckout: order.sent && !order.hasPendingChanges
                  ? () => _checkout(order)
                  : null,
            );
            if (compact) {
              return Column(children: [
                Expanded(child: catalog),
                SizedBox(height: 300, child: ticket),
              ]);
            }
            return Row(children: [
              Expanded(flex: 7, child: catalog),
              SizedBox(width: 390, child: ticket),
            ]);
          }),
        ),
      ]),
    );
  }

  Widget _title(String title, String subtitle) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: GoogleFonts.poppins(
                  color: const Color(0xFF2D2260),
                  fontSize: 26,
                  fontWeight: FontWeight.w800)),
          Text(subtitle, style: const TextStyle(color: Color(0xFF6B6589))),
        ],
      );

  String _status(_OrderDraft order) =>
      order.lines.isEmpty && !order.sent ? 'Cerrada' : 'Abierta';

  /// Salir sin enviar descarta lo cargado: la mesa queda como si no se hubiese tocado.
  void _leaveTable(_OrderDraft order) {
    setState(() {
      if (!order.sent) {
        _orders.remove(order.tableId);
      } else if (order.hasPendingChanges) {
        order.restoreLastSent();
      }
      _selectedTableId = null;
      _productSearch = '';
    });
  }

  void _addProduct(_OrderDraft order, Product product) {
    if (_operationInProgress || order.editLocked) return;
    // Evita que el mismo toque que abre la mesa agregue un producto sin querer.
    if (_tableOpenedAt != null &&
        DateTime.now().difference(_tableOpenedAt!) <
            const Duration(milliseconds: 500)) {
      return;
    }
    setState(() {
      order.openedAt ??= DateTime.now();
      final existing =
          order.lines.where((line) => line.product.id == product.id);
      if (existing.isEmpty) {
        order.lines.add(_OrderLine(product));
      } else {
        existing.first.quantity++;
      }
    });
  }

  void _changeQuantity(_OrderDraft order, _OrderLine line, int delta) {
    if (_operationInProgress || order.editLocked) return;
    final nextQuantity = line.quantity + delta;
    if (delta < 0 &&
        order.sent &&
        (nextQuantity < (order.sentQuantities[line.product.id] ?? 0) ||
            (nextQuantity <= 0 && order.lines.length == 1))) {
      _requestAnnulment(order, line, nextQuantity.clamp(0, line.quantity));
      return;
    }
    setState(() {
      line.quantity = nextQuantity;
      if (line.quantity <= 0) order.lines.remove(line);
    });
  }

  void _removeLine(_OrderDraft order, _OrderLine line) {
    if (_operationInProgress || order.editLocked) return;
    if (order.sent &&
        ((order.sentQuantities[line.product.id] ?? 0) > 0 ||
            order.lines.length == 1)) {
      _requestAnnulment(order, line, 0);
      return;
    }
    setState(() => order.lines.remove(line));
  }

  Future<void> _requestAnnulment(
          _OrderDraft order, _OrderLine line, int remaining) =>
      _runOrderOperation(order, () async {
        final accepted = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Anular producto'),
            content: Text(
                'Vas a anular ${line.quantity - remaining} × ${line.product.name}.\n\n'
                'La anulación quedará pendiente hasta que envíes los cambios a cocina.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Volver')),
              FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Confirmar anulación')),
            ],
          ),
        );
        if (!mounted || accepted != true) return;
        setState(() {
          line.quantity = remaining;
          if (remaining == 0) order.lines.remove(line);
        });
      });

  Future<void> _editLineComment(_OrderDraft order, _OrderLine line) =>
      _runOrderOperation(order, () => _editLineCommentImpl(order, line));

  Future<void> _editLineCommentImpl(_OrderDraft order, _OrderLine line) async {
    final controller = TextEditingController(text: line.comment ?? '');
    final comment = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _DialogKeys(
        // Enter inserta salto de línea en el campo multilínea, no confirma el diálogo.
        onAccept: null,
        onCancel: () => Navigator.pop(dialogContext),
        child: AlertDialog(
          title: Text('Comentario · ${line.product.name}'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Comentario para la comanda (opcional)',
              hintText: 'Ej.: sin sal, bien caliente…',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, controller.text),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (comment == null || !mounted) return;
    setState(
        () => line.comment = comment.trim().isEmpty ? null : comment.trim());
  }

  Future<void> _selectWaiter(_OrderDraft order) =>
      _runOrderOperation(order, () => _selectWaiterImpl(order));

  Future<void> _selectWaiterImpl(_OrderDraft order) async {
    final waiter = await showDialog<String?>(
      context: context,
      builder: (_) => const _WaiterDialog(),
    );
    if (!mounted || waiter == null) return;
    setState(() {
      order.waiter = waiter == '__none__' ? null : waiter;
      if (order.sent) order.metadataDirty = true;
    });
  }

  Future<void> _runOrderOperation(
      _OrderDraft order, Future<void> Function() action,
      {bool allowPayments = false}) async {
    if (_operationInProgress || (!allowPayments && order.editLocked)) return;
    setState(() => _operationInProgress = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _operationInProgress = false);
    }
  }

  Future<void> _applyDiscount(_OrderDraft order) =>
      _runOrderOperation(order, () => _applyDiscountImpl(order));

  Future<void> _applyDiscountImpl(_OrderDraft order) async {
    try {
      final provider = context.read<SalesProvider>();
      final catalogs = await provider.discounts();
      if (!mounted) return;
      final discount = await showDialog<_DiscountValue>(
        context: context,
        builder: (_) => _DiscountDialog(
          current: order.discount,
          catalogs: catalogs,
        ),
      );
      if (discount == null || !mounted) return;
      if (order.sent) {
        order.updateFromServer(await provider.applyDiscount(
          order.orderId!,
          order.serverVersion,
          discountId: discount.id,
          name: discount.name,
          type: discount.type,
          value: discount.value,
        ));
      }
      if (!mounted) return;
      setState(() {
        if (!order.sent) order.discount = discount;
      });
    } catch (error) {
      if (order.sent) {
        try {
          final latest =
              await context.read<SalesProvider>().getSale(order.orderId!);
          if (!mounted || _closeCompletedSale(order, latest)) return;
          setState(() => _restoreCheckoutSnapshot(order, latest));
        } catch (_) {
          // Keep the original error when the refresh also fails.
        }
      }
      _showApiError(error);
    }
  }

  Future<void> _checkout(_OrderDraft order) =>
      _runOrderOperation(order, () => _checkoutImpl(order),
          allowPayments: true);

  void _restoreCheckoutSnapshot(_OrderDraft order, SaleSnapshot snapshot) {
    order.updateFromServer(snapshot);
    order.lines
      ..clear()
      ..addAll(snapshot.items.map((item) => _OrderLine(Product(
            id: '${item.productId}',
            name: item.name,
            category: '',
            price: item.unitPrice,
          ))
            ..quantity = item.quantity
            ..comment = item.comment));
    order.markAsSent();
    order.metadataDirty = snapshot.status == 'ConCambios';
    order.paymentUncertain = false;
  }

  bool _closeCompletedSale(_OrderDraft order, SaleSnapshot snapshot) {
    if (snapshot.status != 'Finalizada' && snapshot.status != 'Cancelada') {
      return false;
    }
    if (!mounted) return true;
    setState(() {
      _orders.removeWhere((_, value) => identical(value, order));
      _selectedTableId = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
          'Venta N.º ${snapshot.number}: ${snapshot.status}. La mesa quedó cerrada.'),
    ));
    return true;
  }

  Future<void> _checkoutImpl(_OrderDraft order) async {
    if (!order.sent || order.hasPendingChanges) return;
    final provider = context.read<SalesProvider>();
    try {
      var snapshot = await provider.getSale(order.orderId!);
      if (!mounted || _closeCompletedSale(order, snapshot)) return;
      final changed = snapshot.version != order.serverVersion;
      setState(() => _restoreCheckoutSnapshot(order, snapshot));
      if (changed || order.hasPendingChanges) {
        throw Exception(
            'La cuenta se actualizó. Revisá el total y enviá los cambios pendientes antes de cobrar.');
      }
      final remaining = ((snapshot.total - snapshot.paidAmount) * 100).round();
      if (remaining < 0) {
        throw Exception(
            'Los pagos registrados superan el total. Revisá la venta antes de cerrarla.');
      }
      if (remaining > 0) {
        final types = await provider.paymentTypes();
        if (!mounted) return;
        if (types.isEmpty) {
          throw Exception('No hay tipos de cobro configurados.');
        }
        types.sort((a, b) {
          final aQr = a.name.toLowerCase().contains('qr');
          final bQr = b.name.toLowerCase().contains('qr');
          return aQr == bQr ? a.name.compareTo(b.name) : (aQr ? -1 : 1);
        });
        final payments = await showDialog<List<_PaymentLine>>(
          context: context,
          barrierDismissible: false,
          builder: (_) => _CheckoutDialog(total: remaining / 100, types: types),
        );
        if (payments == null || !mounted) return;
        // Keep editing locked if the server receives the payment but its
        // response is lost. A fresh read must resolve that uncertainty.
        order.paymentUncertain = true;
        snapshot = await provider.addPayments(
          order.orderId!,
          order.serverVersion,
          [
            for (final payment in payments)
              (
                cardId: payment.type.id,
                baseAmount: (payment.amount * 100).round() / 100,
                amount: payment.finalAmount
              )
          ],
        );
        order.updateFromServer(snapshot);
        order.paymentUncertain = false;
      }
      snapshot = await provider.checkout(snapshot.id, snapshot.version);
      _closeCompletedSale(order, snapshot);
    } catch (error) {
      try {
        final latest = await provider.getSale(order.orderId!);
        if (!mounted || _closeCompletedSale(order, latest)) return;
        setState(() => _restoreCheckoutSnapshot(order, latest));
      } catch (_) {
        // Preserve payment uncertainty until the next successful refresh.
      }
      _showApiError(error);
    }
  }

  Future<void> _sendOrder(_OrderDraft order, RestaurantTable table) =>
      _runOrderOperation(order, () => _sendOrderImpl(order, table));

  Future<void> _sendOrderImpl(_OrderDraft order, RestaurantTable table) async {
    if (!order.canSend) return;
    final firstSend = !order.sent;
    final ticketRows = order.ticketRows(firstSend: firstSend);
    final provider = context.read<SalesProvider>();
    try {
      final accepted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _CommandTicketDialog(
          tableName: table.name,
          waiter: order.waiter,
          rows: ticketRows,
          isModification: !firstSend,
        ),
      );
      if (!mounted) return;
      if (accepted != true) {
        if (!firstSend) setState(order.restoreLastSent);
        return;
      }
      final lines = [
        for (final line in order.lines)
          (
            product: line.product,
            quantity: line.quantity,
            comment: line.comment,
          ),
      ];
      final initialDiscount = order.discount;
      SaleSnapshot snapshot;
      if (firstSend) {
        snapshot = await provider.createSale(
          tableId: order.tableId,
          lines: lines,
        );
      } else {
        snapshot = await provider.synchronizeItems(
          saleId: order.orderId!,
          version: order.serverVersion,
          existingItemIds: order.serverItemIds,
          lines: lines,
          onProgress: order.updateFromServer,
        );
      }
      order.updateFromServer(snapshot);
      final normalizedStatus = snapshot.status.trim().toLowerCase();
      final saleWasCancelled = normalizedStatus == 'cancelada' ||
          normalizedStatus == 'cancelado' ||
          normalizedStatus == 'cancelled' ||
          normalizedStatus == 'canceled';
      if (!firstSend &&
          lines.isEmpty &&
          (saleWasCancelled || snapshot.items.isEmpty)) {
        if (!mounted) return;
        final saleNumber = snapshot.number;
        setState(() {
          _orders.removeWhere((_, value) => identical(value, order));
          _selectedTableId = null;
          _productSearch = '';
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text('Venta N.º $saleNumber cancelada. La mesa quedó liberada.'),
        ));
        return;
      }
      if (firstSend && initialDiscount != null) {
        order.updateFromServer(await provider.applyDiscount(
          order.orderId!,
          order.serverVersion,
          discountId: initialDiscount.id,
          name: initialDiscount.name,
          type: initialDiscount.type,
          value: initialDiscount.value,
        ));
      }
      final command =
          await provider.sendCommand(order.orderId!, order.serverVersion);
      order.updateFromServer(await provider.getSale(order.orderId!));
      String? printError;
      try {
        await provider.enqueueCommandPrint(saleId: order.orderId!);
      } catch (error) {
        printError = error.toString().replaceFirst('Exception: ', '');
      }
      if (!mounted) return;
      setState(() {
        order.markAsSent();
        _selectedTableId = null;
        _productSearch = '';
      });
      if (printError != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('La comanda N.º ${command.number} fue enviada, '
              'pero no se pudo imprimir: $printError'),
        ));
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error.toString().replaceFirst('Exception: ', '')),
      ));
    }
  }

  Future<void> _moveOrder(_OrderDraft order) =>
      _runOrderOperation(order, () => _moveOrderImpl(order));

  Future<void> _moveOrderImpl(_OrderDraft order) async {
    if (order.joinedTableIds.isNotEmpty) return;
    if (order.lines.isEmpty) return;
    final target = await _chooseTargetTable(
        'Cambiar a otra mesa', order.tableId,
        onlyClosed: true);
    if (target == null || !mounted) return;
    try {
      final previousTableId = order.tableId;
      if (order.sent) {
        order.updateFromServer(await context
            .read<SalesProvider>()
            .moveTable(order.orderId!, target.id, order.serverVersion));
      } else {
        order.tableId = target.id;
      }
      if (!mounted) return;
      setState(() {
        _orders.remove(previousTableId);
        _orders[target.id] = order;
        _selectedTableId = null;
        _productSearch = '';
      });
    } catch (error) {
      _showApiError(error);
    }
  }

  Future<void> _joinOrder(_OrderDraft order) =>
      _runOrderOperation(order, () => _joinOrderImpl(order));

  Future<void> _joinOrderImpl(_OrderDraft order) async {
    if (!order.sent || order.hasPendingChanges) return;
    final target = await _chooseTargetTable('Unir con otra mesa', order.tableId,
        onlySavedOrders: true);
    if (target == null || !mounted) return;
    try {
      if (order.sent) {
        order.updateFromServer(await context
            .read<SalesProvider>()
            .joinTable(order.orderId!, target.id, order.serverVersion));
      }
      if (!mounted) return;
      setState(() {
        final other = _orders[target.id];
        if (other != null) {
          for (final line in other.lines) {
            final matches =
                order.lines.where((item) => item.product.id == line.product.id);
            if (matches.isEmpty) {
              order.lines.add(line);
            } else {
              matches.first.quantity += line.quantity;
            }
          }
          _orders.remove(target.id);
        }
        order.joinedTableIds.add(target.id);
        _selectedTableId = null;
        _productSearch = '';
      });
    } catch (error) {
      _showApiError(error);
    }
  }

  Future<RestaurantTable?> _chooseTargetTable(String title, int currentId,
      {bool onlyClosed = false, bool onlySavedOrders = false}) {
    final tables = context
        .read<SectorProvider>()
        .tables
        .where((item) =>
            item.active &&
            item.id != currentId &&
            !_isJoinedTable(item.id) &&
            _isTableVisible(item) &&
            (!onlySavedOrders ||
                _orderForTable(item.id) == null ||
                (_orderForTable(item.id)!.sent &&
                    !_orderForTable(item.id)!.hasPendingChanges &&
                    !_orderForTable(item.id)!.editLocked)) &&
            (!onlyClosed || _orderForTable(item.id) == null))
        .toList();
    return showDialog<RestaurantTable>(
      context: context,
      builder: (_) => SimpleDialog(
        title: Text(title),
        children: tables
            .map((table) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, table),
                  child: Text(table.name),
                ))
            .toList(),
      ),
    );
  }

  Future<void> _clearOrder(_OrderDraft order) =>
      _runOrderOperation(order, () => _clearOrderImpl(order));

  Future<void> _clearOrderImpl(_OrderDraft order) async {
    try {
      if (order.sent) {
        final accepted = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Anular pedido completo'),
            content: const Text(
                'Se anulará todo el pedido, se liberarán sus mesas y se enviará una comanda de anulación a cocina.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Volver')),
              FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Anular pedido')),
            ],
          ),
        );
        if (!mounted || accepted != true) return;
        final snapshot = await context
            .read<SalesProvider>()
            .cancel(order.orderId!, order.serverVersion);
        if (!mounted) return;
        _closeCompletedSale(order, snapshot);
        return;
      }
      if (!mounted) return;
      setState(() {
        _orders.remove(order.tableId);
        _selectedTableId = null;
      });
    } catch (error) {
      if (order.sent && mounted) {
        try {
          final latest =
              await context.read<SalesProvider>().getSale(order.orderId!);
          if (!mounted || _closeCompletedSale(order, latest)) return;
        } catch (_) {}
      }
      _showApiError(error);
    }
  }

  void _showApiError(Object error) {
    if (!mounted) return;
    if (error is UnauthorizedException) {
      context.read<AuthProvider>().logout();
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(error.toString().replaceFirst('Exception: ', '')),
    ));
  }

  _OrderDraft? _orderForTable(int tableId) {
    final direct = _orders[tableId];
    if (direct != null && direct.lines.isNotEmpty) return direct;
    return _orders.values
        .where((order) => order.joinedTableIds.contains(tableId))
        .firstOrNull;
  }

  bool _isJoinedTable(int tableId) =>
      _orders.values.any((order) => order.joinedTableIds.contains(tableId));

  int _ownerTableId(int tableId) =>
      _orders.values
          .where((order) => order.joinedTableIds.contains(tableId))
          .map((order) => order.tableId)
          .firstOrNull ??
      tableId;
}

Size _saleTableSize(RestaurantTable table) =>
    table.shape.toLowerCase() == 'rectangular'
        ? const Size(118, 80)
        : const Size(92, 92);

class _SaleTableCard extends StatelessWidget {
  final RestaurantTable table;
  final _OrderDraft? order;
  final bool joined;
  final VoidCallback onTap;

  const _SaleTableCard({
    required this.table,
    this.order,
    this.joined = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final open = order != null && (order!.lines.isNotEmpty || order!.sent);
    final color = joined
        ? const Color(0xFFE5E7EB)
        : open
            ? const Color(0xFFFFF1D6)
            : const Color(0xFFEAF7EC);
    final border = joined
        ? const Color(0xFF6B7280)
        : open
            ? const Color(0xFFF0A83A)
            : const Color(0xFF64A96B);
    final shape = table.shape.toLowerCase();
    final circular = shape == 'circular' || shape == 'redonda';
    final rectangular = shape == 'rectangular';
    final cardShape = circular
        ? CircleBorder(side: BorderSide(color: border, width: 1.5))
        : RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(rectangular ? 16 : 10),
            side: BorderSide(color: border, width: 1.5),
          );
    return Material(
      color: color,
      shape: cardShape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: joined ? null : onTap,
        canRequestFocus: !joined,
        customBorder: cardShape,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(table.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: joined ? const Color(0xFF6B7280) : null)),
            Text(
                joined
                    ? 'Unida · ${_elapsed(order?.openedAt)}'
                    : open
                        ? 'Abierta · ${_elapsed(order?.openedAt)}'
                        : 'Cerrada',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: border, fontSize: 9.5, fontWeight: FontWeight.w600)),
            if (open)
              Text('\$${order!.total.toStringAsFixed(2)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10.5)),
          ]),
        ),
      ),
    );
  }

  String _elapsed(DateTime? openedAt) {
    if (openedAt == null) return '0 min';
    final duration = DateTime.now().difference(openedAt);
    if (duration.inHours < 1) return '${duration.inMinutes.clamp(0, 59)} min';
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    return '${duration.inHours} h $minutes min';
  }
}

class _ProductCatalog extends StatelessWidget {
  final List<Product> products;
  final String search;
  final bool asGrid;
  final ValueChanged<String> onSearch;
  final ValueChanged<bool> onViewChanged;
  final ValueChanged<Product> onAdd;

  const _ProductCatalog({
    required this.products,
    required this.search,
    required this.asGrid,
    required this.onSearch,
    required this.onViewChanged,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(18),
        child: Column(children: [
          Row(children: [
            Expanded(
              child: TextField(
                onChanged: onSearch,
                decoration: const InputDecoration(
                  hintText: 'Buscar productos',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                    value: true,
                    icon: Icon(Icons.grid_view_rounded),
                    tooltip: 'Cuadrícula'),
                ButtonSegment(
                    value: false,
                    icon: Icon(Icons.view_list_rounded),
                    tooltip: 'Lista compacta'),
              ],
              selected: {asGrid},
              onSelectionChanged: (value) => onViewChanged(value.first),
            ),
          ]),
          const SizedBox(height: 14),
          Expanded(
            child: products.isEmpty
                ? const Center(child: Text('No hay productos disponibles.'))
                : asGrid
                    ? GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 190,
                          mainAxisExtent: 112,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                        itemCount: products.length,
                        itemBuilder: (_, index) {
                          final product = products[index];
                          return _ProductOptionCard(
                            product: product,
                            compact: false,
                            onTap: () => onAdd(product),
                          );
                        },
                      )
                    : ListView.separated(
                        itemCount: products.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 7),
                        itemBuilder: (_, index) => _ProductOptionCard(
                          product: products[index],
                          compact: true,
                          onTap: () => onAdd(products[index]),
                        ),
                      ),
          ),
        ]),
      );
}

class _ProductOptionCard extends StatelessWidget {
  final Product product;
  final bool compact;
  final VoidCallback onTap;
  const _ProductOptionCard(
      {required this.product, required this.compact, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        elevation: 1,
        shadowColor: const Color(0x336C5CE7),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFFCFC9E5), width: 1.2),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
                horizontal: 12, vertical: compact ? 8 : 10),
            child: compact
                ? Row(children: [
                    _icon(),
                    const SizedBox(width: 11),
                    Expanded(child: _details()),
                    const Icon(Icons.add_circle_outline_rounded,
                        color: Color(0xFF6C5CE7)),
                  ])
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        _icon(),
                        const Spacer(),
                        const Icon(Icons.add_circle_outline_rounded,
                            size: 19, color: Color(0xFF6C5CE7)),
                      ]),
                      const SizedBox(height: 5),
                      Expanded(child: _details()),
                    ],
                  ),
          ),
        ),
      );

  Widget _icon() => Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: const Color(0xFFEDE9FF),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.restaurant_menu_rounded,
            size: 17, color: Color(0xFF6C5CE7)),
      );

  Widget _details() => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(product.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(product.category,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFF77718E), fontSize: 11)),
          Text('\$${product.price.toStringAsFixed(2)}',
              style: const TextStyle(
                  color: Color(0xFF6C5CE7), fontWeight: FontWeight.w700)),
        ],
      );
}

class _OrderTicket extends StatelessWidget {
  final _OrderDraft order;
  final ValueChanged<_OrderLine> onIncrease;
  final ValueChanged<_OrderLine> onDecrease;
  final ValueChanged<_OrderLine> onRemove;
  final ValueChanged<_OrderLine> onComment;
  final VoidCallback? onDiscount;
  final VoidCallback? onSend;
  final VoidCallback? onCheckout;

  const _OrderTicket({
    required this.order,
    required this.onIncrease,
    required this.onDecrease,
    required this.onRemove,
    required this.onComment,
    required this.onDiscount,
    required this.onSend,
    required this.onCheckout,
  });

  @override
  Widget build(BuildContext context) => Container(
        color: Colors.white,
        padding: const EdgeInsets.all(16),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Comanda',
              style: GoogleFonts.poppins(
                  fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 5),
          _OrderPhase(order: order),
          if (order.pendingAnnulments.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                  'Anulaciones pendientes: ${order.pendingAnnulments.join(', ')}. Enviá los cambios para confirmarlas en cocina.',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(color: Color(0xFFC62828), fontSize: 12)),
            ),
          const Divider(height: 24),
          Expanded(
            child: order.lines.isEmpty
                ? const Center(
                    child: Text(
                        'Agregá el primer producto\npara abrir la mesa.',
                        textAlign: TextAlign.center))
                : ListView.separated(
                    itemCount: order.lines.length,
                    separatorBuilder: (_, __) => const Divider(height: 10),
                    itemBuilder: (_, index) {
                      final line = order.lines[index];
                      return Row(children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(line.product.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              Text('\$${line.total.toStringAsFixed(2)}'),
                              if (line.comment != null)
                                Text(
                                  line.comment!,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF6C5CE7),
                                    fontSize: 12,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed:
                              order.editLocked ? null : () => onComment(line),
                          tooltip: line.comment == null
                              ? 'Agregar comentario'
                              : 'Editar comentario',
                          icon: Icon(
                            line.comment == null
                                ? Icons.add_comment_outlined
                                : Icons.comment_rounded,
                            size: 20,
                            color: line.comment == null
                                ? const Color(0xFF77718E)
                                : const Color(0xFF6C5CE7),
                          ),
                        ),
                        IconButton(
                            onPressed: order.editLocked
                                ? null
                                : () => onDecrease(line),
                            tooltip:
                                (order.sentQuantities[line.product.id] ?? 0) >=
                                        line.quantity
                                    ? 'Anular una unidad'
                                    : 'Quitar una unidad',
                            icon: const Icon(Icons.remove_circle_outline)),
                        Text('${line.quantity}',
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        IconButton(
                            onPressed: order.editLocked
                                ? null
                                : () => onIncrease(line),
                            icon: const Icon(Icons.add_circle_outline)),
                        IconButton(
                            onPressed:
                                order.editLocked ? null : () => onRemove(line),
                            tooltip:
                                (order.sentQuantities[line.product.id] ?? 0) > 0
                                    ? 'Anular producto'
                                    : 'Quitar producto',
                            icon: const Icon(Icons.close_rounded, size: 18)),
                      ]);
                    },
                  ),
          ),
          const Divider(),
          _amountRow('Subtotal', order.subtotal),
          if (order.discountAmount > 0)
            _amountRow('Descuento', -order.discountAmount),
          if (order.paymentAdjustmentAmount != 0)
            _amountRow(
                'Ajuste por medio de pago', order.paymentAdjustmentAmount),
          _amountRow('Total', order.total, strong: true),
          if (order.paymentCount > 0 || order.paidAmount > 0) ...[
            _amountRow('Pagado', order.paidAmount),
            const Text(
                'Hay pagos registrados. Completá el cobro para cerrar la mesa.'),
          ],
          const SizedBox(height: 10),
          // El descuento se define recién al enviar/cobrar, no mientras se toma el pedido.
          if (order.sent) ...[
            OutlinedButton.icon(
              onPressed: onDiscount,
              icon: const Icon(Icons.discount_outlined),
              label: Text(order.discount == null
                  ? 'Aplicar descuento'
                  : 'Cambiar descuento'),
            ),
            const SizedBox(height: 8),
          ],
          if (!order.sent || order.hasPendingChanges)
            FilledButton.icon(
              onPressed: onSend,
              icon: Icon(order.sent
                  ? Icons.sync_alt_rounded
                  : Icons.receipt_long_outlined),
              label: Text(order.sent ? 'Enviar cambios' : 'Pedido terminado'),
            )
          else
            FilledButton.icon(
              onPressed: onCheckout,
              icon: const Icon(Icons.payments_outlined),
              label:
                  Text(order.editLocked ? 'Completar cobro' : 'Cobrar cuenta'),
            ),
        ]),
      );

  Widget _amountRow(String label, double value, {bool strong = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontWeight: strong ? FontWeight.w700 : FontWeight.w400))),
          Text('\$${value.toStringAsFixed(2)}',
              style: TextStyle(
                  fontSize: strong ? 18 : 14,
                  fontWeight: strong ? FontWeight.w800 : FontWeight.w500)),
        ]),
      );
}

class _OrderPhase extends StatelessWidget {
  final _OrderDraft order;
  const _OrderPhase({required this.order});

  @override
  Widget build(BuildContext context) {
    final current = !order.sent
        ? 0
        : order.hasPendingChanges
            ? 1
            : 2;
    const labels = ['Tomar pedido', 'Cambios', 'Cobrar'];
    return Row(children: [
      for (var index = 0; index < labels.length; index++) ...[
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 5),
            decoration: BoxDecoration(
              color: index == current
                  ? const Color(0xFFEDE9FF)
                  : const Color(0xFFF3F2F5),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(labels[index],
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight:
                      index == current ? FontWeight.w700 : FontWeight.w400,
                  color: index == current
                      ? const Color(0xFF5C4D9B)
                      : const Color(0xFF817C8D),
                )),
          ),
        ),
        if (index < labels.length - 1) const SizedBox(width: 4),
      ],
    ]);
  }
}

class _DiscountDialog extends StatefulWidget {
  final _DiscountValue? current;
  final List<SaleCatalogItem> catalogs;
  const _DiscountDialog({this.current, required this.catalogs});

  @override
  State<_DiscountDialog> createState() => _DiscountDialogState();
}

class _CommandTicketDialog extends StatelessWidget {
  final String tableName;
  final String? waiter;
  final List<_TicketRow> rows;
  final bool isModification;

  const _CommandTicketDialog({
    required this.tableName,
    required this.waiter,
    required this.rows,
    required this.isModification,
  });

  @override
  Widget build(BuildContext context) => _DialogKeys(
      onAccept: () => Navigator.pop(context, true),
      onCancel: () => Navigator.pop(context, false),
      child: AlertDialog(
        title: Text(isModification ? 'Confirmar cambios' : 'Confirmar pedido'),
        content: Container(
          width: 360,
          padding: const EdgeInsets.all(20),
          color: Colors.white,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('COMANDA A CONFIRMAR',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              Text(isModification ? 'MODIFICACIÓN' : 'NUEVO PEDIDO',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: isModification
                        ? const Color(0xFFC56A22)
                        : const Color(0xFF388E3C),
                  )),
              const Divider(height: 24),
              Text('Mesa: $tableName'),
              Text('Mozo: ${waiter ?? 'Sin asignar'}'),
              Text('Fecha: ${_formattedNow()}'),
              const Divider(height: 24),
              for (final row in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 48,
                          child: Text(row.displayQuantity,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: row.delta == 0
                                    ? Colors.black
                                    : row.delta > 0
                                        ? const Color(0xFF388E3C)
                                        : const Color(0xFFC62828),
                              )),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(row.product.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              if (row.comment != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(row.comment!,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontStyle: FontStyle.italic)),
                                ),
                            ],
                          ),
                        ),
                      ]),
                ),
              const Divider(height: 24),
              const Text('Al aceptar se enviará a la impresora',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF77737E))),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              autofocus: true,
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Aceptar')),
        ],
      ));

  static String _formattedNow() {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(now.day)}/${two(now.month)}/${now.year} '
        '${two(now.hour)}:${two(now.minute)}';
  }
}

class _DiscountDialogState extends State<_DiscountDialog> {
  SaleCatalogItem? selected;

  @override
  void initState() {
    super.initState();
    selected = widget.catalogs
        .where((item) => item.id == widget.current?.id)
        .firstOrNull;
    selected ??= widget.catalogs.firstOrNull;
  }

  @override
  Widget build(BuildContext context) => _DialogKeys(
      onAccept: selected == null
          ? null
          : () => Navigator.pop(
              context,
              _DiscountValue(selected!.type, selected!.value,
                  id: selected!.id, name: selected!.name)),
      onCancel: () => Navigator.pop(context),
      child: AlertDialog(
        title: const Text('Aplicar descuento'),
        content: SizedBox(
          width: 430,
          child: widget.catalogs.isEmpty
              ? const Text('No hay descuentos configurados.')
              : DropdownButtonFormField<SaleCatalogItem>(
                  value: selected,
                  decoration: const InputDecoration(
                    labelText: 'Descuento configurado',
                    border: OutlineInputBorder(),
                  ),
                  items: widget.catalogs
                      .map((item) => DropdownMenuItem(
                            value: item,
                            child: Text(
                                '${item.name} · ${item.value.toStringAsFixed(2)}'
                                '${item.type.toLowerCase().contains('porc') ? '%' : ''}'),
                          ))
                      .toList(),
                  onChanged: (item) => setState(() => selected = item),
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(
            autofocus: true,
            onPressed: selected == null
                ? null
                : () => Navigator.pop(
                    context,
                    _DiscountValue(selected!.type, selected!.value,
                        id: selected!.id, name: selected!.name)),
            child: const Text('Aplicar'),
          ),
        ],
      ));
}

class _CheckoutDialog extends StatefulWidget {
  final double total;
  final List<SaleCatalogItem> types;
  const _CheckoutDialog({required this.total, required this.types});

  @override
  State<_CheckoutDialog> createState() => _CheckoutDialogState();
}

class _CheckoutDialogState extends State<_CheckoutDialog> {
  late final List<_PaymentLine> payments;

  @override
  void initState() {
    super.initState();
    payments = [_PaymentLine(widget.types.first)..amount = widget.total];
  }

  double get paid => payments.fold(0, (sum, item) => sum + item.amount);

  bool get canConfirm => validPaymentAmounts(
      payments.map((payment) => payment.amount), widget.total);

  void _confirm() {
    if (canConfirm) Navigator.pop(context, payments);
  }

  double get adjustment =>
      payments.fold(0, (sum, line) => sum + line.adjustment);
  double get finalTotal => widget.total + adjustment;

  @override
  Widget build(BuildContext context) => _DialogKeys(
      onAccept: canConfirm ? _confirm : null,
      onCancel: () => Navigator.pop(context),
      child: AlertDialog(
        title: const Text('Cobrar cuenta'),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              const Expanded(child: Text('Saldo de la cuenta')),
              Text('\$${widget.total.toStringAsFixed(2)}'),
            ]),
            const SizedBox(height: 8),
            const Text(
                'Asigná el importe de la cuenta a cada medio. Su recargo o descuento se calcula automáticamente.'),
            const SizedBox(height: 16),
            for (var index = 0; index < payments.length; index++)
              Padding(
                key: ObjectKey(payments[index]),
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        Expanded(
                          child: DropdownButtonFormField<SaleCatalogItem>(
                            isExpanded: true,
                            decoration: const InputDecoration(
                                labelText: 'Medio de pago'),
                            value: payments[index].type,
                            items: widget.types
                                .map((item) => DropdownMenuItem(
                                    value: item,
                                    child: Text(item.name,
                                        overflow: TextOverflow.ellipsis)))
                                .toList(),
                            onChanged: (value) =>
                                setState(() => payments[index].type = value!),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            initialValue: payments[index].amount == 0
                                ? ''
                                : '${payments[index].amount}',
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: const InputDecoration(
                                prefixText: '\$ ',
                                labelText: 'Importe de cuenta'),
                            onChanged: (value) => setState(() => payments[index]
                                    .amount =
                                double.tryParse(value.replaceAll(',', '.')) ??
                                    0),
                          ),
                        ),
                        IconButton(
                          onPressed: payments.length == 1
                              ? null
                              : () => setState(() => payments.removeAt(index)),
                          icon: const Icon(Icons.delete_outline_rounded),
                        ),
                      ]),
                      const SizedBox(height: 6),
                      Text(payments[index].type.value == 0
                          ? 'Sin ajuste'
                          : '${payments[index].type.type} ${payments[index].type.value.toStringAsFixed(2)}%: \$${payments[index].adjustment.toStringAsFixed(2)}'),
                      Text(
                          'A cobrar con este medio: \$${payments[index].finalAmount.toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ]),
              ),
            TextButton.icon(
              onPressed: () => setState(
                  () => payments.add(_PaymentLine(widget.types.first))),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Agregar otro medio de pago'),
            ),
            const Divider(),
            if (!canConfirm)
              const Text(
                  'Los importes de cuenta deben ser positivos y sumar exactamente el saldo.'),
            Row(children: [
              const Expanded(child: Text('Importe asignado')),
              Text('\$${paid.toStringAsFixed(2)}'),
            ]),
            Row(children: [
              const Expanded(child: Text('Ajustes por medios de pago')),
              Text('\$${adjustment.toStringAsFixed(2)}'),
            ]),
            Row(children: [
              const Expanded(child: Text('Total a cobrar')),
              Text('\$${finalTotal.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w800)),
            ]),
          ])),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton.icon(
            autofocus: true,
            onPressed: canConfirm ? _confirm : null,
            icon: const Icon(Icons.check_rounded),
            label: const Text('Confirmar cobro'),
          ),
        ],
      ));
}

class _DialogKeys extends StatelessWidget {
  final VoidCallback? onAccept;
  final VoidCallback onCancel;
  final Widget child;
  const _DialogKeys(
      {required this.onAccept, required this.onCancel, required this.child});

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
        bindings: {
          if (onAccept != null)
            const SingleActivator(LogicalKeyboardKey.enter): onAccept!,
          const SingleActivator(LogicalKeyboardKey.escape): onCancel,
        },
        child: Focus(autofocus: true, child: child),
      );
}

class _WaiterDialog extends StatelessWidget {
  const _WaiterDialog();
  @override
  Widget build(BuildContext context) => SimpleDialog(
        title: const Text('Asignar mozo'),
        children: ['__none__', 'Juan', 'María', 'Carlos']
            .map((name) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, name),
                  child: Text(name == '__none__' ? 'Sin asignar' : name),
                ))
            .toList(),
      );
}

class _SaleLegend extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const Wrap(spacing: 12, children: [
        _LegendDot(color: Color(0xFF64A96B), label: 'Cerrada'),
        _LegendDot(color: Color(0xFFF0A83A), label: 'Abierta'),
        SizedBox(width: 14),
        _LegendDot(color: Color(0xFF6B7280), label: 'Unida'),
      ]);
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});
  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label),
      ]);
}

class _OrderDraft {
  int tableId;
  int? orderId;
  int saleNumber = 0;
  int serverVersion = 0;
  DateTime? openedAt;
  final Map<String, int> serverItemIds = {};
  String? waiter;
  final List<_OrderLine> lines = [];
  final Set<int> joinedTableIds = {};
  _DiscountValue? discount;
  final Map<String, int> sentQuantities = {};
  final Map<String, String?> sentComments = {};
  String? sentWaiter;
  bool metadataDirty = false;
  double paidAmount = 0;
  double? serverTotal;
  bool paymentUncertain = false;
  int paymentCount = 0;
  double paymentAdjustmentAmount = 0;
  bool get editLocked => paymentCount > 0 || paidAmount > 0 || paymentUncertain;

  _OrderDraft(this.tableId);

  void updateFromServer(SaleSnapshot snapshot) {
    paidAmount = snapshot.paidAmount;
    paymentCount = snapshot.paymentCount;
    paymentAdjustmentAmount = snapshot.paymentAdjustment;
    serverTotal = snapshot.total;
    metadataDirty = snapshot.status == 'ConCambios';
    discount = snapshot.discount == null
        ? null
        : _DiscountValue(
            snapshot.discount!.type,
            snapshot.discount!.value,
            id: snapshot.discount!.id == 0 ? null : snapshot.discount!.id,
            name: snapshot.discount!.name,
          );
    orderId = snapshot.id;
    saleNumber = snapshot.number;
    serverVersion = snapshot.version;
    openedAt = snapshot.openedAt ?? openedAt;
    tableId = snapshot.tableId;
    serverItemIds
      ..clear()
      ..addAll(snapshot.itemIds);
    joinedTableIds
      ..clear()
      ..addAll(snapshot.joinedTableIds);
  }

  double get subtotal => lines.fold(0, (sum, item) => sum + item.total);
  double get discountAmount {
    if (discount == null) return 0;
    final normalizedType = discount!.type.toLowerCase();
    final amount =
        normalizedType.contains('porc') || normalizedType.contains('percent')
            ? subtotal * discount!.value / 100
            : discount!.value;
    return amount.clamp(0, subtotal);
  }

  double get total => sent && !hasPendingChanges && serverTotal != null
      ? serverTotal!
      : subtotal - discountAmount;

  bool get sent => orderId != null;
  bool get hasPendingChanges {
    final current = {for (final line in lines) line.product.id: line.quantity};
    return metadataDirty ||
        current.length != sentQuantities.length ||
        current.entries
            .any((entry) => sentQuantities[entry.key] != entry.value) ||
        lines.any((line) => sentComments[line.product.id] != line.comment);
  }

  List<String> get pendingAnnulments => [
        for (final sent in sentQuantities.entries)
          if (sent.value >
              (lines
                      .where((line) => line.product.id == sent.key)
                      .firstOrNull
                      ?.quantity ??
                  0))
            '${sent.value - (lines.where((line) => line.product.id == sent.key).firstOrNull?.quantity ?? 0)} × ${_lastSentProducts[sent.key]?.name ?? 'Producto'}',
      ];

  bool get canSend => lines.isNotEmpty
      ? (!sent || hasPendingChanges)
      : sent && sentQuantities.isNotEmpty;

  void markAsSent() {
    rememberSentProducts();
    sentQuantities
      ..clear()
      ..addEntries(
          lines.map((line) => MapEntry(line.product.id, line.quantity)));
    sentComments
      ..clear()
      ..addEntries(
          lines.map((line) => MapEntry(line.product.id, line.comment)));
    sentWaiter = waiter;
    metadataDirty = false;
  }

  void restoreLastSent() {
    lines
      ..clear()
      ..addAll(sentQuantities.entries.map((entry) {
        final product = _lastSentProducts[entry.key]!;
        return _OrderLine(product)
          ..quantity = entry.value
          ..comment = sentComments[entry.key];
      }));
    waiter = sentWaiter;
    metadataDirty = false;
  }

  List<_TicketRow> ticketRows({required bool firstSend}) {
    if (firstSend) {
      return [
        for (final line in lines)
          _TicketRow(
            product: line.product,
            quantity: line.quantity,
            comment: line.comment,
          ),
      ];
    }
    final rows = <_TicketRow>[];
    for (final line in lines) {
      final delta = line.quantity - (sentQuantities[line.product.id] ?? 0);
      rows.add(_TicketRow(
        product: line.product,
        quantity: line.quantity,
        delta: delta,
        comment: line.comment,
      ));
    }
    for (final sent in sentQuantities.entries) {
      if (lines.any((line) => line.product.id == sent.key)) continue;
      // Se conserva el producto original para mostrar una baja completa.
      final removed = _lastSentProducts[sent.key];
      if (removed != null) {
        rows.add(_TicketRow(product: removed, quantity: 0, delta: -sent.value));
      }
    }
    return rows;
  }

  final Map<String, Product> _lastSentProducts = {};

  void rememberSentProducts() {
    for (final line in lines) {
      _lastSentProducts[line.product.id] = line.product;
    }
  }
}

class _TicketRow {
  final Product product;
  final int quantity;
  final int delta;
  final String? comment;
  const _TicketRow({
    required this.product,
    required this.quantity,
    this.delta = 0,
    this.comment,
  });

  String get displayQuantity =>
      delta == 0 ? '$quantity' : '${delta > 0 ? '+' : ''}$delta';
}

class _OrderLine {
  final Product product;
  int quantity = 1;
  String? comment;
  _OrderLine(this.product);
  double get total => product.price * quantity;
}

class _DiscountValue {
  final String type;
  final double value;
  final int? id;
  final String name;
  const _DiscountValue(this.type, this.value,
      {this.id, this.name = 'Descuento'});
}

class _PaymentLine {
  SaleCatalogItem type;
  double amount = 0;
  _PaymentLine(this.type);
  double get adjustment => paymentAdjustment(amount, type.type, type.value);
  double get finalAmount =>
      amount.isFinite ? (amount * 100).round() / 100 + adjustment : 0;
}
