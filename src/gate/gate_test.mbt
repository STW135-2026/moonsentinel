///|
fn research_batch() -> @arrow.RecordBatch {
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
fn research_policy(max_findings? : Int = 100) -> PrivacyPolicy {
  PrivacyPolicy::new(
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
    max_findings~,
  ).unwrap()
}

///|
fn research_request() -> ReleaseRequest {
  ReleaseRequest::new("req-2026-001", "fraud_research", @gate.Partner).unwrap()
}

///|
test "release binds purpose, consent, k-anonymity, and minimization" {
  let bundle = research_policy()
    .release(research_batch(), research_request())
    .unwrap()
  let report = bundle.report()
  assert_eq(report.decision(), "partial")
  assert_eq(report.denial_count(), 2)
  assert_eq(report.approved_row_count(), 4)
  assert_eq(report.quarantined_row_count(), 2)
  assert_eq(report.released_columns(), [
    "email", "country", "age_band", "risk_score",
  ])
  assert_true(report.findings()[0].code is @gate.ConsentDenied)
  assert_true(report.findings()[1].code is @gate.KAnonymityViolation)
  assert_eq(bundle.approved().schema.fields.length(), 4)
  assert_eq(bundle.approved().num_rows, 4)
  assert_eq(bundle.quarantine().schema.fields.length(), 6)
  assert_eq(bundle.quarantine().num_rows, 2)
  assert_eq(bundle.findings().num_rows, 2)
  assert_eq(bundle.manifest().num_rows, 1)
  assert_true(
    bundle.approved().columns[0]
    is @arrow.Strings(
      [Some("[EMAIL]"), Some("[EMAIL]"), Some("[EMAIL]"), Some("[EMAIL]")]
    ),
  )
}

///|
test "unapproved purpose denies the complete release" {
  let request = ReleaseRequest::new("req-purpose", "advertising", @gate.Partner).unwrap()
  let bundle = research_policy().release(research_batch(), request).unwrap()
  assert_eq(bundle.report().decision(), "denied")
  assert_eq(bundle.report().approved_row_count(), 0)
  assert_eq(bundle.report().quarantined_row_count(), 6)
  assert_true(bundle.report().findings()[0].code is @gate.PurposeNotAllowed)
  assert_eq(bundle.approved().schema.fields.length(), 0)
}

///|
test "unapproved recipient denies the complete release" {
  let request = ReleaseRequest::new(
    "req-recipient",
    "fraud_research",
    @gate.Public,
  ).unwrap()
  let bundle = research_policy().release(research_batch(), request).unwrap()
  assert_eq(bundle.report().decision(), "denied")
  assert_true(bundle.report().findings()[0].code is @gate.RecipientNotAllowed)
}

///|
test "policies are fail-closed" {
  assert_true(
    PrivacyPolicy::new(
      "unsafe",
      ["analytics"],
      [@gate.Partner],
      { column: "consent", granted_values: ["yes"], },
      [
        {
          column: "user_id",
          classification: @gate.DirectIdentifier,
          treatment: @gate.Keep,
        },
        {
          column: "country",
          classification: @gate.QuasiIdentifier,
          treatment: @gate.Keep,
        },
      ],
    )
    is Err(@gate.InvalidPolicy(_)),
  )
  assert_true(
    PrivacyPolicy::new(
      "bad-k",
      ["analytics"],
      [@gate.Partner],
      { column: "consent", granted_values: ["yes"], },
      [
        {
          column: "country",
          classification: @gate.QuasiIdentifier,
          treatment: @gate.Keep,
        },
      ],
      minimum_group_size=1,
    )
    is Err(@gate.InvalidPolicy(_)),
  )
  assert_true(
    ReleaseRequest::new("", "analytics", @gate.Internal)
    is Err(@gate.InvalidRequest(_)),
  )
}

///|
test "missing consent fails closed with a dataset denial" {
  let schema = @arrow.Schema::new([
    @arrow.Field::new("country", @arrow.Utf8),
    @arrow.Field::new("age_band", @arrow.Utf8),
    @arrow.Field::new("risk_score", @arrow.Int32),
    @arrow.Field::new("user_id", @arrow.Utf8),
    @arrow.Field::new("email", @arrow.Utf8),
  ])
  let batch = try! @arrow.RecordBatch::new(schema, [
    @arrow.Strings([Some("CN"), Some("CN")]),
    @arrow.Strings([Some("30-39"), Some("30-39")]),
    @arrow.Int32s([Some(10), Some(20)]),
    @arrow.Strings([Some("u-1"), Some("u-2")]),
    @arrow.Strings([Some("a@example.com"), Some("b@example.com")]),
  ])
  let bundle = research_policy().release(batch, research_request()).unwrap()
  assert_eq(bundle.report().decision(), "denied")
  assert_eq(bundle.report().approved_row_count(), 0)
  assert_true(bundle.report().findings()[0].code is @gate.MissingColumn)
}

///|
test "bounded findings preserve exact denial counts" {
  let report = research_policy(max_findings=1)
    .release(research_batch(), research_request())
    .unwrap()
    .report()
  assert_eq(report.denial_count(), 2)
  assert_eq(report.findings().length(), 1)
  assert_true(report.truncated())
}

///|
test "findings and manifest survive Arrow IPC" {
  let bundle = research_policy()
    .release(research_batch(), research_request())
    .unwrap()
  let findings_bytes = try! @arrow.write_stream(bundle.findings().schema, [
    bundle.findings(),
  ])
  let manifest_bytes = try! @arrow.write_stream(bundle.manifest().schema, [
    bundle.manifest(),
  ])
  let findings = try! @arrow.read_stream(findings_bytes)
  let manifest = try! @arrow.read_stream(manifest_bytes)
  assert_eq(findings.batches[0].num_rows, 2)
  assert_eq(manifest.batches[0].num_rows, 1)
}

///|
test "mutated invalid Arrow batches are rejected" {
  let values : Array[String?] = [Some("CN")]
  let schema = @arrow.Schema::new([
    @arrow.Field::new("country", @arrow.Utf8, nullable=false),
  ])
  let batch = try! @arrow.RecordBatch::new(schema, [@arrow.Strings(values)])
  values[0] = None
  assert_true(
    research_policy().release(batch, research_request())
    is Err(@gate.InvalidBatch),
  )
}
