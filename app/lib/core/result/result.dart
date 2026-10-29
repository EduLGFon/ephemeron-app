// Lightweight Result type for typed failures at boundaries.
sealed class Result<T, E> {
  const Result();
  bool get isSuccess => this is Success<T, E>;
  bool get isFailure => this is Failure<T, E>;
}

final class Success<T, E> extends Result<T, E> {
  const Success(this.value);
  final T value;
}

final class Failure<T, E> extends Result<T, E> {
  const Failure(this.error);
  final E error;
}
