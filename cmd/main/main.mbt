///|
fn source_batch() -> @arrow.RecordBatch {
  let schema = @arrow.Schema::new([
    @arrow.Field::new("user_id", @arrow.Utf8, nullable=false),
    @arrow.Field::new("email", @arrow.Utf8),
    @arrow.Field::new("research_consent", @arrow.Utf8),
    @arrow.Field::new("country", @arrow.Utf8),
    @arrow.Field::new("age_band", @arrow.Utf8),
    @arrow.Field::new("case_outcome", @arrow.Utf8),
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
    @arrow.Strings([
      Some("confirmed"),
      Some("cleared"),
      Some("confirmed"),
      Some("confirmed"),
      Some("cleared"),
      Some("confirmed"),
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
    {
      column: "research_consent",
      grants: [{ purpose: "fraud_research", granted_values: ["yes"], }],
    },
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
        column: "case_outcome",
        classification: @gate.Sensitive,
        treatment: @gate.Drop,
      },
      {
        column: "risk_score",
        classification: @gate.PublicData,
        treatment: @gate.Keep,
      },
    ],
    minimum_group_size=2,
    diversity_columns=["case_outcome"],
    minimum_distinct_sensitive_values=2,
  ).unwrap()
}

///|
fn main {
  let request = @gate.ReleaseRequest::new(
    "req-2026-001",
    "fraud_research",
    @gate.Partner,
  ).unwrap()
  let source_jsonl = @gate.batch_to_jsonl(source_batch()).unwrap()
  let source_from_jsonl = @gate.jsonl_to_batch(source_jsonl).unwrap()
  let bundle = policy().release(source_from_jsonl, request).unwrap()
  println("MoonSentinel partner data delivery check")
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
  let approved_jsonl = @gate.batch_to_jsonl(bundle.approved()).unwrap()
  let jsonl_round_trip = @gate.jsonl_to_batch(approved_jsonl).unwrap()
  println(
    "JSONL handoff: \{jsonl_round_trip.num_rows} released rows, \{jsonl_round_trip.schema.fields.length()} fields",
  )
  let source_csv = @gate.batch_to_csv(source_batch()).unwrap()
  let source_from_csv = @gate.csv_to_batch(source_csv).unwrap()
  let csv_request = @gate.ReleaseRequest::new(
    "req-csv-001",
    "fraud_research",
    @gate.Partner,
  ).unwrap()
  let csv_bundle = policy().release(source_from_csv, csv_request).unwrap()
  let approved_csv = @gate.batch_to_csv(csv_bundle.approved()).unwrap()
  let csv_round_trip = @gate.csv_to_batch(approved_csv).unwrap()
  println(
    "CSV handoff: \{csv_round_trip.num_rows} released rows, \{csv_round_trip.schema.fields.length()} fields",
  )
}
