import '../../core/errors/app_exception.dart';
import '../models/shift_template.dart';
import 'crud_repository.dart';
import 'stored_repository.dart';
import 'schedule_operation_models.dart';

abstract interface class ShiftTemplateRepository
    implements CrudRepository<ShiftTemplate> {
  Future<ShiftTemplate?> getByCode(String code);
  Future<bool> isCodeDuplicate(String code, {String? excludingId});
  Future<List<ShiftTemplate>> getEnabled();
  Future<bool> canDelete(String id);
  Future<ShiftReferenceSummary> getReferenceSummary(String id);
}

class LocalShiftTemplateRepository extends StoredRepository<ShiftTemplate>
    implements ShiftTemplateRepository {
  LocalShiftTemplateRepository(
    super.store, {
    Future<ShiftReferenceSummary> Function(String id)? referenceChecker,
  }) : _referenceChecker = referenceChecker;

  final Future<ShiftReferenceSummary> Function(String id)? _referenceChecker;

  @override
  String get collection => 'shift_templates';

  String _normalizeCode(String code) => code.trim().toUpperCase();

  @override
  String idOf(ShiftTemplate item) => item.id;

  @override
  Map<String, Object?> encode(ShiftTemplate item) => item.toMap();

  @override
  ShiftTemplate decode(Map<String, Object?> map) => ShiftTemplate.fromMap(map);

  @override
  String uniqueKeyOf(ShiftTemplate item) => _normalizeCode(item.code);

  @override
  Future<void> add(ShiftTemplate item) async {
    _validate(item);
    if (await isCodeDuplicate(item.code)) {
      throw const DuplicateShiftCodeException();
    }
    await super.add(item);
  }

  @override
  Future<void> update(ShiftTemplate item) async {
    _validate(item);
    if (await isCodeDuplicate(item.code, excludingId: item.id)) {
      throw const DuplicateShiftCodeException();
    }
    await super.update(item);
  }

  void _validate(ShiftTemplate item) {
    if (item.code.trim().isEmpty) throw const ValidationException('班次代码不能为空');
    if (item.name.trim().isEmpty) throw const ValidationException('班次名称不能为空');
    if (item.type.storageValue == 'work' && item.arrivalTime == null) {
      throw const ValidationException('工作班必须设置到岗时间');
    }
  }

  @override
  Future<ShiftTemplate?> getByCode(String code) async {
    final payload = await store.readByUniqueKey(
      collection,
      _normalizeCode(code),
    );
    if (payload == null) return null;
    final all = await getAll();
    return all
        .where((item) => _normalizeCode(item.code) == _normalizeCode(code))
        .firstOrNull;
  }

  @override
  Future<bool> isCodeDuplicate(String code, {String? excludingId}) async {
    final existing = await getByCode(code);
    return existing != null && existing.id != excludingId;
  }

  @override
  Future<List<ShiftTemplate>> getEnabled() async {
    final result = (await getAll()).where((item) => item.isEnabled).toList();
    result.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return result;
  }

  @override
  Future<List<ShiftTemplate>> getAll() async {
    final result = await super.getAll();
    result.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return result;
  }

  @override
  Future<bool> canDelete(String id) async {
    return !(await getReferenceSummary(id)).isReferenced;
  }

  @override
  Future<ShiftReferenceSummary> getReferenceSummary(String id) =>
      _referenceChecker?.call(id) ??
      Future.value(
        const ShiftReferenceSummary(scheduleCount: 0, changeLogCount: 0),
      );
}
