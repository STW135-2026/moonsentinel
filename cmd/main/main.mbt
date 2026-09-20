///|
fn source_batch() -> @arrow.RecordBatch {
  let schema = @arrow.Schema::new([
    @arrow.Field::new("user_id", @arrow.Utf8, nullable=false),
    @arrow.Field::new("email", @arrow.Utf8),
    @arrow.Field::new("research_consent", @arrow.Utf8),
    @arrow.Field::new("country", @arrow.Utf8),
    @arrow.Field::new("age_band", @arrow.Utf8),
    @arrow.Field::new("risk_score", @arrow.Int32),
  ])
  try! @arrow.RecordBatch::new(schema, [
    @arrow.Strings([
      Some("u-1"),
      Some("u-2"),
      Some("u-3"),
      Some("u-4"),
      Some("u-5"),
      Some("u-6"),
    ]),
    @arrow.Strings([
      Some("one@example.com"),
      Some("two@example.com"),
      Some("three@example.com"),
      Some("four@example.com"),
      Some("five@example.com"),
      Some("six@example.com"),
    ]),
    @arrow.Strings([
      Some("yes"),
      Some("yes"),
      Some("yes"),
      Some("no"),
      Some("yes"),
      Some("yes"),
    ]),
    @arrow.Strings([
      Some("CN"),
      Some("CN"),
      Some("US"),
      Some("CN"),
      Some("US"),
      Some("DE"),
    ]),
    @arrow.Strings([
      Some("30-39"),
      Some("30-39"),
      Some("20-29"),
      Some("30-39"),
      Some("20-29"),
      Some("50-59"),
    ]),
    @arrow.Int32s([Some(10), Some(20), Some(30), Some(40), Some(50), Some(60)]),
  ])
}

///|
fn policy() -> @gate.PrivacyPolicy {
  @gate.PrivacyPolicy::new(
    "fraud-research-v1",
    ["fraud_research"],
    [@gate.Partner],
    { column: "research_consent", granted_values: ["yes"], },
    [
      {
        column: "user_id",
        classification: @gate.DirectIdentifier,
        treatment: @gate.Drop,
      },
      {
        column: "email",
        classification: @gate.Sensitive,
        treatment: @gate.ReplaceUtf8("[EMAIL]"),
      },
      {
        column: "research_consent",
        classification: @gate.Sensitive,
        treatment: @gate.Drop,
      },
      {
        column: "country",
        classification: @gate.QuasiIdentifier,
        treatment: @gate.Keep,
      },
      {
        column: "age_band",
        classification: @gate.QuasiIdentifier,
        treatment: @gate.Keep,
      },
      {
        column: "risk_score",
        classification: @gate.PublicData,
        treatment: @gate.Keep,
      },
    ],
    minimum_group_size=2,
  ).unwrap()
}

///|
fn main {
  let request = @gate.ReleaseRequest::new(
    "req-2026-001",
    "fraud_research",
    @gate.Partner,
  ).unwrap()
  let bundle = policy().release(source_batch(), request).unwrap()
  println("MoonSentinel purpose-bound privacy release")
  println(bundle.report().summary())
  println("released columns: \{bundle.report().released_columns().join(", ")}")
  println("approved rows: \{bundle.approved().num_rows}")
  println("quarantined rows: \{bundle.quarantine().num_rows}")
  println("privacy findings: \{bundle.findings().num_rows}")
  println("release manifest rows: \{bundle.manifest().num_rows}")
  match bundle.approved().columns[0] {
    @arrow.Strings(values) => println("masked email: \{values[0].unwrap()}")
    _ => println("unexpected email column")
  }
  let bytes = try! @arrow.write_stream(bundle.approved().schema, [
    bundle.approved(),
  ])
  let restored = try! @arrow.read_stream(bytes)
  println(
    "Arrow IPC handoff: \{bytes.length()} bytes, \{restored.batches[0].num_rows} released rows",
  )
}
