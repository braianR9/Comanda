/// Comprobante electrónico (factura o nota de crédito) emitido en AFIP.
class Invoice {
  final int id;
  final int saleId;
  final String environment;
  final int type;
  final String typeName;
  final String number;
  final DateTime date;
  final String receiverName;
  final int docType;
  final int docNumber;
  final double total;
  final double net;
  final double vat;
  final String status;
  final String? cae;
  final DateTime? caeExpiresAt;
  final String messages;
  final int? creditNoteId;
  final int? associatedInvoiceId;
  final DateTime createdAt;
  final DateTime? authorizedAt;
  final String userName;
  final String reason;

  const Invoice({
    required this.id,
    required this.saleId,
    required this.environment,
    required this.type,
    required this.typeName,
    required this.number,
    required this.date,
    required this.receiverName,
    required this.docType,
    required this.docNumber,
    required this.total,
    required this.net,
    required this.vat,
    required this.status,
    this.cae,
    this.caeExpiresAt,
    this.messages = '',
    this.creditNoteId,
    this.associatedInvoiceId,
    required this.createdAt,
    this.authorizedAt,
    this.userName = '',
    this.reason = '',
  });

  bool get authorized => status == 'Autorizado';
  bool get isCreditNote => type == 3 || type == 8 || type == 13;
  bool get canCreditNote => authorized && !isCreditNote && creditNoteId == null;
  bool get testing => environment != 'Produccion';

  String get receiver => docType == 99
      ? 'Consumidor final'
      : '$receiverName · ${docType == 80 ? 'CUIT' : docType == 86 ? 'CUIL' : 'Doc.'} $docNumber';

  factory Invoice.fromJson(Map<String, dynamic> json) => Invoice(
        id: (json['id'] as num).toInt(),
        saleId: (json['orderId'] as num).toInt(),
        environment: json['environment']?.toString() ?? 'Homologacion',
        type: (json['type'] as num).toInt(),
        typeName: json['typeName']?.toString() ?? '',
        number: json['formattedNumber']?.toString() ?? '',
        date:
            DateTime.tryParse(json['date']?.toString() ?? '') ?? DateTime.now(),
        receiverName: json['receiverName']?.toString() ?? '',
        docType: (json['docType'] as num?)?.toInt() ?? 99,
        docNumber: (json['docNumber'] as num?)?.toInt() ?? 0,
        total: (json['total'] as num?)?.toDouble() ?? 0,
        net: (json['net'] as num?)?.toDouble() ?? 0,
        vat: (json['vat'] as num?)?.toDouble() ?? 0,
        status: json['status']?.toString() ?? '',
        cae: json['cae']?.toString(),
        caeExpiresAt: DateTime.tryParse(json['caeExpiresAt']?.toString() ?? ''),
        messages: json['messages']?.toString() ?? '',
        creditNoteId: (json['creditNoteId'] as num?)?.toInt(),
        associatedInvoiceId: (json['associatedInvoiceId'] as num?)?.toInt(),
        createdAt:
            DateTime.tryParse(json['createdAt']?.toString() ?? '')?.toLocal() ??
                DateTime.now(),
        authorizedAt: DateTime.tryParse(json['authorizedAt']?.toString() ?? '')
            ?.toLocal(),
        userName: json['userName']?.toString() ?? '',
        reason: json['reason']?.toString() ?? '',
      );
}
