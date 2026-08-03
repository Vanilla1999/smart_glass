enum DataMatrixInverse {
  SIMPLE(0),
  INVERSE_ONLY(1),
  AUTO_INVERSE_CHECK(2);

  final int value;

  const DataMatrixInverse(this.value);
}
