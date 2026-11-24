///|
fn benchmark_release(it : @bench.T, rows : Int32, groups : Int32) -> Unit {
  let schema = @arrow.Schema::new([
    @arrow.Field::new("group", @arrow.Int32),
    @arrow.Field::new("consent", @arrow.Utf8),
    @arrow.Field::new("sensitive", @arrow.Utf8),
  ])
  let batch = try! @arrow.RecordBatch::new(schema, [
    @arrow.Int32s(Array::makei(rows, row => Some(row % groups))),
    @arrow.Strings(Array::make(rows, Some("yes"))),
    @arrow.Strings(
      Array::makei(rows, row => {
        Some(if row / groups % 2 == 0 { "a" } else { "b" })
      }),
    ),
  ])
  let policy = @gate.PrivacyPolicy::new(
    "benchmark",
    ["share"],
    [@gate.Partner],
    {
      column: "consent",
      grants: [{ purpose: "share", granted_values: ["yes"], }],
    },
    [
      {
        column: "group",
        classification: @gate.QuasiIdentifier,
        treatment: @gate.Keep,
      },
      {
        column: "sensitive",
        classification: @gate.Sensitive,
        treatment: @gate.Drop,
      },
    ],
    minimum_group_size=2,
    diversity_columns=["sensitive"],
    minimum_distinct_sensitive_values=2,
  ).unwrap()
  let request = @gate.ReleaseRequest::new("benchmark", "share", @gate.Partner).unwrap()
  let baseline = policy.release(batch, request).unwrap()
  if baseline.approved().num_rows != rows || baseline.quarantine().num_rows != 0 {
    abort("benchmark fixture unexpectedly rejected rows")
  }
  it.bench(fn() { it.keep(policy.release(batch, request).unwrap()) })
}

///|
test "release: 512 rows in 128 interleaved groups" (it : @bench.T) {
  benchmark_release(it, 512, 128)
}

///|
test "release: 2048 rows in 512 interleaved groups" (it : @bench.T) {
  benchmark_release(it, 2048, 512)
}

///|
test "release: 2048 rows in one large group" (it : @bench.T) {
  benchmark_release(it, 2048, 1)
}
