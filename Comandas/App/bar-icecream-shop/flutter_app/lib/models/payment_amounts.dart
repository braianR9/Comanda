/// Compare payments in cents, matching the amounts sent to the server.
bool validPaymentAmounts(Iterable<double> amounts, double total) {
  final values = amounts.toList();
  if (!total.isFinite || total <= 0 || values.isEmpty) return false;
  if (values.any((amount) =>
      !amount.isFinite || amount <= 0 || (amount * 100).round() <= 0)) {
    return false;
  }
  return values.fold<int>(0, (sum, amount) => sum + (amount * 100).round()) ==
      (total * 100).round();
}

/// Adjust only the portion of the account assigned to this payment method.
double paymentAdjustment(double basis, String type, double percentage) {
  if (!basis.isFinite || !percentage.isFinite) return 0;
  final normalized = type.toLowerCase();
  final sign = normalized == 'recargo'
      ? 1
      : normalized == 'descuento'
          ? -1
          : 0;
  final cents = (basis * 100).round();
  return (cents * percentage / 100).round() * sign / 100;
}
