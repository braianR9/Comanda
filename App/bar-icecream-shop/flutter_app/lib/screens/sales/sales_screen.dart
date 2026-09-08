import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../models/product.dart';
import '../../models/restaurant_table.dart';
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
  String _productSearch = '';
  bool _productsAsGrid = true;
  Timer? _occupationTimer;

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
            draft.lines.add(_OrderLine(product)
              ..quantity = item.quantity
              ..comment = item.comment);
          }
          draft.joinedTableIds.addAll(sale.joinedTableIds);
          draft.markAsSent();
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
    return widget.embedded
        ? ColoredBox(color: const Color(0xFFF5F5F8), child: body)
        : Scaffold(backgroundColor: const Color(0xFFF5F5F8), body: body);
  }

  Widget _buildTableSelection() {
    final sectorProvider = context.watch<SectorProvider>();
    final sectors = sectorProvider.sectors.where((item) => item.active).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    if (_selectedSectorId == null && sectors.isNotEmpty) {
      _selectedSectorId = sectors.first.id;
    }
    final tables = sectorProvider.tables
        .where((table) =>
            table.active &&
            (_selectedSectorId == null || table.sectorId == _selectedSectorId))
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
                                    onTap: () => setState(() =>
                                        _selectedTableId =
                                            _ownerTableId(table.id)),
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
              onPressed: () => setState(() {
                _selectedTableId = null;
                _productSearch = '';
              }),
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
              onPressed: () => _selectWaiter(order),
              icon: const Icon(Icons.person_outline_rounded),
              label: Text(order.waiter ?? 'Sin mozo'),
            ),
            const SizedBox(width: 8),
            PopupMenuButton<String>(
              tooltip: 'Acciones de mesa',
              onSelected: (value) {
                if (value == 'move') _moveOrder(order);
                if (value == 'join') _joinOrder(order);
                if (value == 'clear') _clearOrder(order);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'move', child: Text('Cambiar de mesa')),
                PopupMenuItem(value: 'join', child: Text('Unir con otra mesa')),
                PopupMenuItem(value: 'clear', child: Text('Vaciar comanda')),
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
              onDiscount: () => _applyDiscount(order),
              onSend: order.canSend ? () => _sendOrder(order, table) : null,
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

  void _addProduct(_OrderDraft order, Product product) {
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
    setState(() {
      line.quantity += delta;
      if (line.quantity <= 0) order.lines.remove(line);
    });
  }

  void _removeLine(_OrderDraft order, _OrderLine line) =>
      setState(() => order.lines.remove(line));

  Future<void> _editLineComment(_OrderDraft order, _OrderLine line) async {
    final controller = TextEditingController(text: line.comment ?? '');
    final comment = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _DialogKeys(
        onAccept: () => Navigator.pop(dialogContext, controller.text),
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

  Future<void> _selectWaiter(_OrderDraft order) async {
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

  Future<void> _applyDiscount(_OrderDraft order) async {
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
      setState(() => order.discount = discount);
    } catch (error) {
      _showApiError(error);
    }
  }

  Future<void> _checkout(_OrderDraft order) async {
    try {
      final provider = context.read<SalesProvider>();
      final types = await provider.paymentTypes();
      if (!mounted) return;
      if (types.isEmpty) throw Exception('No hay tipos de cobro configurados.');
      types.sort((a, b) {
        final aQr = a.name.toLowerCase().contains('qr');
        final bQr = b.name.toLowerCase().contains('qr');
        return aQr == bQr ? a.name.compareTo(b.name) : (aQr ? -1 : 1);
      });
      final payments = await showDialog<List<_PaymentLine>>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _CheckoutDialog(total: order.total, types: types),
      );
      if (payments == null || !mounted) return;
      var snapshot = await provider.addPayments(
        order.orderId!,
        order.serverVersion,
        [
          for (final payment in payments)
            (paymentTypeId: payment.type.id, amount: payment.amount)
        ],
      );
      snapshot = await provider.checkout(snapshot.id, snapshot.version);
      if (!mounted) return;
      final number = snapshot.number;
      setState(() {
        _orders.remove(order.tableId);
        _selectedTableId = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Venta N.º $number finalizada. La mesa quedó cerrada.'),
      ));
    } catch (error) {
      _showApiError(error);
    }
  }

  Future<void> _sendOrder(_OrderDraft order, RestaurantTable table) async {
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

  Future<void> _moveOrder(_OrderDraft order) async {
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

  Future<void> _joinOrder(_OrderDraft order) async {
    final target =
        await _chooseTargetTable('Unir con otra mesa', order.tableId);
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
      {bool onlyClosed = false}) {
    final tables = context
        .read<SectorProvider>()
        .tables
        .where((item) =>
            item.active &&
            item.id != currentId &&
            !_isJoinedTable(item.id) &&
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

  Future<void> _clearOrder(_OrderDraft order) async {
    try {
      if (order.sent) {
        await context
            .read<SalesProvider>()
            .cancel(order.orderId!, order.serverVersion);
      }
      if (!mounted) return;
      setState(() {
        _orders.remove(order.tableId);
        _selectedTableId = null;
      });
    } catch (error) {
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
    final color = open ? const Color(0xFFFFF1D6) : const Color(0xFFEAF7EC);
    final border = open ? const Color(0xFFF0A83A) : const Color(0xFF64A96B);
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
        onTap: onTap,
        customBorder: cardShape,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(table.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                    fontSize: 11.5, fontWeight: FontWeight.w700)),
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
  final VoidCallback onDiscount;
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
                          onPressed: () => onComment(line),
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
                            onPressed: () => onDecrease(line),
                            icon: const Icon(Icons.remove_circle_outline)),
                        Text('${line.quantity}',
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        IconButton(
                            onPressed: () => onIncrease(line),
                            icon: const Icon(Icons.add_circle_outline)),
                        IconButton(
                            onPressed: () => onRemove(line),
                            icon: const Icon(Icons.close_rounded, size: 18)),
                      ]);
                    },
                  ),
          ),
          const Divider(),
          _amountRow('Subtotal', order.subtotal),
          if (order.discountAmount > 0)
            _amountRow('Descuento', -order.discountAmount),
          _amountRow('Total', order.total, strong: true),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onDiscount,
            icon: const Icon(Icons.discount_outlined),
            label: Text(order.discount == null
                ? 'Aplicar descuento'
                : 'Cambiar descuento'),
          ),
          const SizedBox(height: 8),
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
              label: const Text('Cobrar cuenta'),
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

  bool get canConfirm =>
      (paid - widget.total).abs() <= .01 || paid > widget.total;

  void _confirm() {
    if (canConfirm) Navigator.pop(context, payments);
  }

  @override
  Widget build(BuildContext context) => _DialogKeys(
      onAccept: canConfirm ? _confirm : null,
      onCancel: () => Navigator.pop(context),
      child: AlertDialog(
        title: const Text('Cobrar cuenta'),
        content: SizedBox(
          width: 520,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              const Expanded(child: Text('Total a cobrar')),
              Text('\$${widget.total.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 16),
            for (var index = 0; index < payments.length; index++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<SaleCatalogItem>(
                      value: payments[index].type,
                      items: widget.types
                          .map((item) => DropdownMenuItem(
                              value: item, child: Text(item.name)))
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
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(prefixText: '\$ '),
                      onChanged: (value) => setState(() =>
                          payments[index].amount =
                              double.tryParse(value.replaceAll(',', '.')) ?? 0),
                    ),
                  ),
                  IconButton(
                    onPressed: payments.length == 1
                        ? null
                        : () => setState(() => payments.removeAt(index)),
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ]),
              ),
            TextButton.icon(
              onPressed: () => setState(
                  () => payments.add(_PaymentLine(widget.types.first))),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Agregar otro medio de pago'),
            ),
            const Divider(),
            Row(children: [
              const Expanded(child: Text('Ingresado')),
              Text('\$${paid.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: paid >= widget.total
                        ? const Color(0xFF388E3C)
                        : const Color(0xFFC56A22),
                  )),
            ]),
          ]),
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

  _OrderDraft(this.tableId);

  void updateFromServer(SaleSnapshot snapshot) {
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

  double get total => subtotal - discountAmount;

  bool get sent => orderId != null;
  bool get hasPendingChanges {
    final current = {for (final line in lines) line.product.id: line.quantity};
    return metadataDirty ||
        current.length != sentQuantities.length ||
        current.entries
            .any((entry) => sentQuantities[entry.key] != entry.value) ||
        lines.any((line) => sentComments[line.product.id] != line.comment);
  }

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
}
