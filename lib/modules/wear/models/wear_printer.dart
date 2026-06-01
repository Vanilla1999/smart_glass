class WearPrinter {
  const WearPrinter({required this.id, required this.name});
  final String id;
  final String name;

  @override
  String toString() => '$id $name';
}
