# MoonSentinel

[![CI](https://github.com/STW135-2026/moonsentinel/actions/workflows/ci.yml/badge.svg)](https://github.com/STW135-2026/moonsentinel/actions/workflows/ci.yml)

MoonSentinel 是用 MoonBit 编写的**多场景数据共享前授权核验与隐私发布工具**。

一份数据通过格式和质量检查，不等于它可以直接交给合作方。交付人员还要确认本次用途和
接收方是否获准、每条记录是否具有对应同意、交付结果中是否残留直接标识符，以及小群体
特征是否可能重新识别个人。MoonSentinel 把这些条件写成可执行策略，在数据离开当前系统前
统一检查。

它接收 Arrow `RecordBatch`、扁平 JSONL 记录或带表头的 CSV，并结合 `PrivacyPolicy` 和
`ReleaseRequest`。JSONL 和 CSV 会先转换为 Arrow；通过的行会按列白名单
投影和脱敏；不符合条件的行进入隔离结果；每次运行还会生成机器可读的拒绝原因和交付回执。

## 为什么需要这个工具

在临时 SQL 或导出脚本中，授权条件、字段删除和脱敏通常分开维护。源表增加字段后，
`select *` 还可能把新列带出。即使脚本得到了一个结构正确的文件，也不一定能回答“为什么
这次可以交给这个接收方”以及“哪些记录因什么原因没有交付”。

MoonSentinel 适合接在数据导出任务的最后一步。它不替代上游质量检查，而是把一次交付
绑定到请求编号、用途和接收方，并产出可保存的判断依据。适用工作流不限于某个行业：研究
机构交换样本、企业向外部服务商提供业务数据、团队共享用户或设备数据、以及整理公开数据
集，都可能需要回答“这批数据是否可以按本次用途交付，具体哪些行和字段可以出去”。

当前版本既可直接接收 Arrow `RecordBatch`，也可把 JSONL 或 CSV 转换为 Arrow 后执行相同策略；
通过门禁的 Arrow 结果还能导出为 JSONL 或 CSV。CSV 不携带列类型，因此导入后所有列均按
UTF-8 字符串处理；未加引号的空单元格转为 null，`""` 保留为空字符串。

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
- JSONL 与 Arrow 的适配：每行一个扁平 JSON 对象，支持字符串、布尔、数字和 null；缺失字段按 null 处理；
- `batch_to_jsonl` 可把筛选后的 Arrow 批次序列化为 JSONL；
- CSV 与 Arrow 的适配：带表头、逗号和引号转义、LF/CRLF、引号内换行；字段保持文本，未加引号的空单元格按 null 处理；
- `batch_to_csv` 可把筛选后的 Arrow 批次序列化为带表头的 CSV；
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

演示模拟一次面向合作方的反欺诈研究数据交付。6 行源数据中，1 行没有对应用途的同意，
1 行因 `country + age_band` 组合未达到 `k=2` 被隔离；直接标识符和同意列被删除，邮件
被替换后只发布 4 行：

```text
MoonSentinel partner data delivery check
fraud-research-v1/req-2026-001: partial; purpose=fraud_research; recipient=partner; rows=6; released=4; quarantined=2; denials=2; k=2; l=2; diversity=case_outcome; findings_shown=2; truncated=false
released columns: email, country, age_band, risk_score
approved rows: 4
quarantined rows: 2
privacy findings: 2
release manifest rows: 1
masked email: [EMAIL]
Arrow IPC handoff: 1152 bytes, 4 released rows
JSONL handoff: 4 released rows, 4 fields
CSV handoff: 4 released rows, 4 fields
```

演示先将示例记录转为 JSONL，再解析为 Arrow 后执行发布策略；获准结果同时演示 Arrow IPC 与 JSONL 交接。
IPC 字节数可能随底层 Arrow 版本变化；决策、行数、列名和脱敏结果是验收依据。

## API 示例

```mbt
let policy = @gate.PrivacyPolicy::new(
  "fraud-research-v1",
  ["fraud_research"],
  [@gate.Partner],
  {
    column: "research_consent",
    grants: [
      { purpose: "fraud_research", granted_values: ["yes"] },
    ],
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

let jsonl_batch = @gate.jsonl_to_batch(jsonl_text).unwrap()
let jsonl_bundle = policy.release(jsonl_batch, request).unwrap()
let approved_jsonl = @gate.batch_to_jsonl(jsonl_bundle.approved()).unwrap()

let csv_batch = @gate.csv_to_batch(csv_text).unwrap()
let csv_bundle = policy.release(csv_batch, request).unwrap()
let approved_csv = @gate.batch_to_csv(csv_bundle.approved()).unwrap()
```

## 与 MoonVerity 的实质差异

| 维度 | MoonVerity | MoonSentinel |
| --- | --- | --- |
| 核心问题 | 数据是否满足 schema 与质量规则 | 数据是否被授权向特定接收方用于特定目的 |
| 输入 | CSV/JSONL、数据合同 | CSV、JSONL 或 Arrow RecordBatch、隐私政策、发布请求 |
| 核心算法 | 完整性、枚举、范围、唯一性、画像、合同 diff | 用途/接收方授权、逐行同意、k-匿名、l-diversity、字段最小化 |
| 输出 | 文本/JSON 校验报告和画像 | 最小化数据、受控隔离、隐私拒绝、发布清单为 Arrow；获准数据可导出 CSV/JSONL |
| 当前 API | `Contract`、`Rule`、`ValidationReport` | `PrivacyPolicy`、`ReleaseRequest`、`PrivacyReport` |

完整的逐项代码证据见[差异化核查](docs/DIFFERENTIATION.zh-CN.md)。

## 处理顺序

```text
CSV / JSONL / RecordBatch + PrivacyPolicy + ReleaseRequest
                    |
                    v
          CSV / JSONL -> RecordBatch
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

- JSONL 当前仅接受一行一个扁平对象；嵌套对象和数组不支持；CSV 要求首行为表头且每行列数一致；
- CSV 列按 UTF-8 字符串导入，不自动猜测数值或布尔类型；未加引号的空单元格转为 null，引用的空字符串保留为空字符串；
- JSONL 输入与导出都对绝对值大于 `9007199254740991` 的数值失败关闭，避免导出的数据无法无损导回；同列混合类型会拒绝，整数和小数可提升为浮点数；
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
