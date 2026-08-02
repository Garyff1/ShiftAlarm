class AppException implements Exception {
  const AppException(this.userMessage, {this.cause});

  final String userMessage;
  final Object? cause;

  @override
  String toString() => 'AppException($userMessage, cause: $cause)';
}

class ValidationException extends AppException {
  const ValidationException(super.userMessage);
}

class DuplicateShiftCodeException extends ValidationException {
  const DuplicateShiftCodeException() : super('班次代码已存在，请使用其他代码');
}

class StorageException extends AppException {
  const StorageException(super.userMessage, {super.cause});
}
