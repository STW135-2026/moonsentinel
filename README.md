# MoonSentinel

[![CI](https://github.com/STW135-2026/moonsentinel/actions/workflows/ci.yml/badge.svg)](https://github.com/STW135-2026/moonsentinel/actions/workflows/ci.yml)

MoonSentinel 是用 MoonBit 编写的**用途绑定隐私发布门禁**。它接收 Arrow
`RecordBatch`、`PrivacyPolicy` 和 `ReleaseRequest`，在数据离开当前信任边界前检查：
本次用途是否获准、接收方是否获准、每行是否有对应同意，以及准标识符组合是否达到
指定的 k-匿名阈值、等价类内敏感属性是否达到 l-diversity。通过的行会按最小化策略
投影和脱敏，同时生成可归档的发布清单。

项目不再提供通用数据质量合同、非空/范围/枚举/唯一性规则、数据画像、合同差异或
CSV/JSONL 校验 CLI。上述能力属于
[`MoonVerity`](https://github.com/Wchwch777/MoonVerity) 的公开范围，不是本项目成果。

## 已实现

- `ReleaseRequest` 将请求编号、处理用途和接收方信任边界绑定到一次发布；
- 用途和接收方双重允许列表，任一不匹配时整批拒绝；
- 逐行同意检查：缺失同意或同意值不覆盖当前用途时隔离该行；
- 对获准候选行执行多列 k-匿名检查，稀有准标识符组合不会被发布；
- 对通过 k-匿名的等价类执行可配置 l-diversity，敏感属性过于单一时继续隔离；
- 默认拒绝的字段最小化：未写入列策略的输入列不会进入输出；
- `DirectIdentifier` 和 `Sensitive` 列不能以 `Keep` 方式发布；
- `Keep`、`ReplaceUtf8`、`Drop` 三种输出处置；
- `approved`、`quarantine`、`privacy_findings`、`release_manifest` 四个 Arrow 输出；
- findings 数量可设上限，但拒绝总数和行处置仍保持准确；
- Native、JavaScript、Wasm、Wasm-GC 四目标自动检查和测试。

## 三分钟验证

```sh
moon update
moon fmt --check
moon check --target all --deny-warn
moon test --target all --deny-warn
moon run cmd/main --target native --deny-warn
```

演示模拟一次面向合作方的反欺诈研究数据发布。6 行源数据中，1 行没有对应用途的同意，
1 行因 `country + age_band` 组合未达到 `k=2` 被隔离；直接标识符和同意列被删除，邮件
被替换后只发布 4 行：

```text
MoonSentinel purpose-bound privacy release
fraud-research-v1/req-2026-001: partial; purpose=fraud_research; recipient=partner; rows=6; released=4; quarantined=2; denials=2; k=2; l=2; diversity=case_outcome; findings_shown=2; truncated=false
released columns: email, country, age_band, risk_score
approved rows: 4
quarantined rows: 2
privacy findings: 2
release manifest rows: 1
masked email: [EMAIL]
Arrow IPC handoff: 1136 bytes, 4 released rows
```

IPC 字节数可能随底层 Arrow 版本变化；决策、行数、列名和脱敏结果是验收依据。

## API 示例

```mbt
let policy = @gate.PrivacyPolicy::new(
  "fraud-research-v1",
  ["fraud_research"],
  [@gate.Partner],
  { column: "research_consent", granted_values: ["yes"] },
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
  ],
  minimum_group_size=2,
  diversity_columns=["case_outcome"],
  minimum_distinct_sensitive_values=2,
).unwrap()

let request = @gate.ReleaseRequest::new(
  "req-2026-001",
  "fraud_research",
  @gate.Partner,
).unwrap()

let bundle = policy.release(batch, request).unwrap()
let safe_rows = bundle.approved()
let controlled_quarantine = bundle.quarantine()
let denials = bundle.findings()
let manifest = bundle.manifest()
```

## 与 MoonVerity 的实质差异

| 维度 | MoonVerity | MoonSentinel |
| --- | --- | --- |
| 核心问题 | 数据是否满足 schema 与质量规则 | 数据是否被授权向特定接收方用于特定目的 |
| 输入 | CSV/JSONL、数据合同 | Arrow RecordBatch、隐私政策、发布请求 |
| 核心算法 | 完整性、枚举、范围、唯一性、画像、合同 diff | 用途/接收方授权、逐行同意、k-匿名、l-diversity、字段最小化 |
| 输出 | 文本/JSON 校验报告和画像 | 最小化数据、受控隔离、隐私拒绝、发布清单，均为 Arrow |
| 当前 API | `Contract`、`Rule`、`ValidationReport` | `PrivacyPolicy`、`ReleaseRequest`、`PrivacyReport` |

完整的逐项代码证据见[差异化核查](docs/DIFFERENTIATION.zh-CN.md)。

## 处理顺序

```text
RecordBatch + PrivacyPolicy + ReleaseRequest
                    |
                    v
       purpose / recipient authorization
                    |
                    v
              row consent check
                    |
                    v
      k-anonymity on eligible candidates
                    |
                    v
       l-diversity on sensitive values
                    |
                    v
     fail-closed projection and masking
          /        |        |       \
   approved  quarantine  findings  manifest
```

## 当前边界

- k-匿名和 l-diversity 在单个 `RecordBatch` 内计算，尚未支持跨批次状态；
- 当前 l-diversity 的敏感属性列只支持 UTF-8，空值不计入不同值数量；
- 当前脱敏为 UTF-8 固定替换，不声称是密码学匿名化；
- 当前接收方只有 `Internal`、`Partner`、`Public` 三档；
- quarantine 保留源列，必须由调用方存放在受控区域；
- 数据读写由 `shunge/arrow@0.1.0` 提供，本项目不重复实现 IPC；
- 本工具提供技术门禁，不替代组织的法务判断或合规审批。

## 文档

- [项目申报书](docs/PROPOSAL.zh-CN.md)
- [与 MoonVerity 的差异化核查](docs/DIFFERENTIATION.zh-CN.md)
- [开发与差异化记录](docs/DEVELOPMENT_LOG.zh-CN.md)
- [技术架构](docs/ARCHITECTURE.md)
- [演示步骤](docs/DEMO.zh-CN.md)

## 许可证

Apache-2.0。`shunge/arrow` 是独立的 MIT 许可依赖。
