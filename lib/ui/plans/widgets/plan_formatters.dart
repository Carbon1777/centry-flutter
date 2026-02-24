String formatPlanDateTime(DateTime? dt) {
  if (dt == null) return '—';
  final d = dt.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}
