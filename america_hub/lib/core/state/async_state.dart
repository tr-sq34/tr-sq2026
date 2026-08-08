sealed class AsyncState<T> {
  const AsyncState();
}

class AsyncLoading<T> extends AsyncState<T> {
  const AsyncLoading();
}

class AsyncData<T> extends AsyncState<T> {
  const AsyncData(this.value);
  final T value;
}

class AsyncFailure<T> extends AsyncState<T> {
  const AsyncFailure(this.message);
  final String message;
}
