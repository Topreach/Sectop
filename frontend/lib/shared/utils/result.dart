/// A generic Result type for consistent error handling.
/// TODO: Migrate existing methods to return Result<T> instead of throwing or returning null.
sealed class Result<T> {
  const Result();

  /// Transform the result by applying [onSuccess] to the value or [onFailure] to the error.
  R fold<R>(R Function(T value) onSuccess, R Function(Exception error) onFailure);
}

/// Represents a successful operation with a [value].
final class Success<T> extends Result<T> {
  final T value;
  const Success(this.value);

  @override
  R fold<R>(R Function(T value) onSuccess, R Function(Exception error) onFailure) =>
      onSuccess(value);
}

/// Represents a failed operation with an [error].
final class Failure<T> extends Result<T> {
  final Exception error;
  const Failure(this.error);

  @override
  R fold<R>(R Function(T value) onSuccess, R Function(Exception error) onFailure) =>
      onFailure(error);
}
