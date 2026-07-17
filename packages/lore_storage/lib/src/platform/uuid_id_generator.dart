import 'package:lore_application/lore_application.dart';
import 'package:uuid/uuid.dart';

final class UuidIdGenerator implements IdGenerator {
  const UuidIdGenerator([this._uuid = const Uuid()]);

  final Uuid _uuid;

  @override
  String generate() => _uuid.v4();
}
