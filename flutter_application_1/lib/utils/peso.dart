/// Nearest peso. Slot charges and the overtime penalty do not keep centavos.
double roundPeso(double amount) {
  if (!amount.isFinite || amount <= 0) return 0;
  return amount.roundToDouble();
}

/// Whole-peso label, for example `₱28`.
String formatPeso(double amount) => '₱${roundPeso(amount).toStringAsFixed(0)}';
