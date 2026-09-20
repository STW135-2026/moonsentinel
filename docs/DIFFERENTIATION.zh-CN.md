# MoonSentinel 与 MoonVerity 差异化核查

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

后续功能必须能直接回答隐私发布问题，例如 l-diversity、用途撤销、策略有效期、不可逆
令牌化适配和多批次匿名状态。
