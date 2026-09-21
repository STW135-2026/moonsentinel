# MoonSentinel GitHub 同类项目差异化核查

## 核查结论

2026-09-20 核查了
[`Wchwch777/MoonVerity`](https://github.com/Wchwch777/MoonVerity) 的公开 README、比赛
申报书、架构、`core/types.mbt`、`core/validation.mbt`、`core/profile.mbt`、
`core/diff.mbt` 和 `cli/commands.mbt`。

上一版 MoonSentinel 的必需列、非空、范围、允许列表、唯一性、跨字段比较和
Error/Warning 门禁与 MoonVerity 的数据质量范围重合。当前代码已删除这些 API，并将核心
问题改为：**一批数据是否被授权为指定用途交付给指定接收方，以及输出是否达到隐私
发布条件。**

这次差异来自数据模型、决策依据、核心算法和输出工件的共同变化，不是名称或文案变化。

2026-09-21 又以 MoonBit、privacy、redaction、consent、k-anonymity、l-diversity、Arrow、
data release、data governance 等关键词扩展检索 GitHub，并阅读候选仓库 README 与隐私
相关源码。没有发现另一项同时实现 `Arrow RecordBatch + 发布请求 + 行级同意 + k-匿名 +
l-diversity + 四类 Arrow 输出` 的 MoonBit 项目。

## 扩展候选核查

| 候选项目 | 实际范围 | 与 MoonSentinel 的边界 |
| --- | --- | --- |
| [MoonRedact](https://github.com/chenliyi-cly/moonredact) | 自由文本敏感值检测、遮盖、删除、令牌化和残留复检 | 不接收 Arrow 表，不核验用途/接收方/逐行同意，不计算匿名等价类 |
| [moonbit-fhir](https://github.com/cxh123-alt/moonbit-fhir) | FHIR JSON 验证、字段删除、资源导出与临床数据工具 | 面向 FHIR JSON 字段政策，不是请求绑定的通用 Arrow 发布门禁，没有 k/l 匿名组判断 |
| [moon-privacy-budget](https://github.com/ppyq882/moon-privacy-budget) | 差分隐私查询机制、ε/δ 预算账户和审计账本 | 控制聚合查询隐私预算，不选择可出域的明细行列，也不执行 consent/k/l 门禁 |
| [MoonTrustFlow](https://github.com/lllg123/MoonTrustFlow-MoonBit) | 源到汇的数据流路径和 Policy-as-Code 分析 | 分析架构图与路径，不处理真实 RecordBatch 或生成最小化数据 |
| [MoonLogfmt Lens](https://github.com/sqhyyy/moonlogfmt-lens) | logfmt 合同、质量、敏感文本清理和漂移检查 | 面向日志文本；核心仍是合同/质量/清理，不绑定一次数据发布请求 |
| [PhotoPrivacy](https://github.com/zangyunyidao/photo_privacy) | 浏览器本地图像元数据检查与清理 | 处理图片容器与 Exif/XMP，不处理结构化表发布 |

局部共性主要是“政策”“遮盖”“审计”等通用词。为让差异落在算法而非描述上，本项目
新增了 distinct l-diversity：仅对已通过同意与 k-匿名的固定候选集检查指定敏感属性，
不足 l 的匿名组继续隔离，并把 l 与多样性列写入 Arrow manifest。

## 逐项对比

| 对比维度 | MoonVerity | MoonSentinel |
| --- | --- | --- |
| 主要问题 | 数据是否符合契约和质量规则 | 此次出域是否符合用途、接收方、同意和匿名阈值 |
| 主要输入 | CSV/JSONL 记录和 JSON contract | Arrow RecordBatch、PrivacyPolicy、ReleaseRequest |
| 请求上下文 | 数据集名称与合同版本 | request id、purpose、recipient |
| 行级逻辑 | 完整性、枚举、范围、唯一性、模式、条件必填等 | 同意是否覆盖当前发布请求 |
| 集合级逻辑 | 行数、distinct count、质量评分 | 多列准标识符等价类的 k-匿名 |
| 列处置 | 以检查和报告为主 | 默认拒绝投影、Keep、ReplaceUtf8、Drop |
| 扩展工具 | profile、contract diff、contract check、benchmark | release manifest、隐私 findings、受控 quarantine |
| 输出 | 文本/JSON 报告 | approved、quarantine、findings、manifest 四个 Arrow 批次 |
| 当前公共类型 | Contract、Rule、ValidationReport | PrivacyPolicy、ReleaseRequest、PrivacyReport |

## 当前代码证据

### MoonSentinel 已实现而 MoonVerity 当前未提供

- `ReleaseRequest`：一次发布必须提供稳定请求编号、具体用途和接收方级别；
- purpose allowlist：用途不匹配时整批失败关闭；
- recipient allowlist：Internal、Partner、Public 信任边界不匹配时整批失败关闭；
- consent binding：在请求上下文下逐行检查同意值，拒绝原因不复制原始敏感值；
- k-anonymity：只在通过同意检查的候选行中计算准标识符等价类；
- l-diversity：只在通过 k-匿名的固定候选集中统计敏感属性非空不同值；
- data minimization：列未显式配置即不会进入 approved；
- classification guard：DirectIdentifier 和 Sensitive 在策略构造时禁止 Keep；
- release manifest：每次输出一行可审计决策清单。

### MoonVerity 已实现而 MoonSentinel 当前明确不做

- JSON 数据合同解析和字段 schema；
- CSV/JSONL 解析、归一化与 round-trip；
- 非空、范围、枚举、唯一性、模式、字符串长度、条件必填和行数规则；
- Warning/Error 质量严重度；
- 数据画像、质量评分和 benchmark suite；
- contract diff、contract check 和校验 CLI；
- 文本/JSON 质量报告。

## 源码级防回退检查

当前生产包 `src/gate` 只公开：

- `PrivacyPolicy`、`ColumnPolicy`、`ConsentRequirement`；
- `ReleaseRequest`、`Recipient`；
- `DataClass`、`Treatment`；
- `PrivacyReport`、`Finding`、`ReleaseBundle`。

不再公开 `Contract`、`Rule`、`Severity`、`ValidationReport`、`profile` 或 `diff`。README、
申报书、架构、演示和生成的 `.mbti` 均与此边界一致。

## 互补关系

MoonVerity 可以先检查 CSV/JSONL 的字段和质量，再由上游转换为 Arrow；MoonSentinel 随后
依据具体发布请求执行隐私授权与最小化。前者回答“数据合不合格”，后者回答“这次能不能
给、能给哪些行和列”。两者处于连续但不同的处理阶段。

## 仍需避免的方向

为防止再次形成同类项目，MoonSentinel 近期不会增加：

- 通用非空、范围、枚举、唯一性或 pattern 质量规则；
- CSV/JSONL 数据合同 CLI；
- 数据画像、质量评分和合同 diff；
- DataFrame、通用筛选、分组、连接或查询语言。

后续功能必须能直接回答隐私发布问题，例如 t-closeness、用途撤销、策略有效期、不可逆
令牌化适配和多批次匿名状态。
