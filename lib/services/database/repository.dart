// lib/services/database/repository.dart
//
// Sealed result type for all repository operations.
// Design.md §1 — authoritative definition.
// Consumers use valueOr() to fall back safely; never catch exceptions from repos.

/// Result type for repository operations. Either Ok<T> or Err<T>.
sealed class RepoResult<T> {
  const RepoResult();

  factory RepoResult.ok(T value) = Ok<T>;
  factory RepoResult.err(RepoError error, {String? detail}) = Err<T>;

  /// Returns [value] if Ok, otherwise [fallback].
  T valueOr(T fallback) => switch (this) {
        Ok<T> o => o.value,
        Err<T> _ => fallback,
      };
}

/// Successful result carrying a value.
final class Ok<T> extends RepoResult<T> {
  const Ok(this.value);
  final T value;
}

/// Failed result carrying an error code and optional detail string.
final class Err<T> extends RepoResult<T> {
  const Err(this.error, {this.detail});
  final RepoError error;
  final String? detail;
}

/// Repository error codes. All repos return one of these — never throw.
enum RepoError {
  network,
  auth,
  notFound,
  conflict,
  unknown,
}
