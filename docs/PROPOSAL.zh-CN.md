# MoonSentinel 项目申报书

## 一、项目基本信息

- 项目名称：MoonSentinel
- 项目副标题：用途绑定的 Arrow 隐私发布门禁
- 项目负责人：苏天纬
- 开源许可证：Apache-2.0
- 代码仓库：<https://github.com/STW135-2026/moonsentinel>
- 底层依赖：`shunge/arrow@0.1.0`，MIT 许可证

## 二、项目定位

MoonSentinel 使用 MoonBit 在 Arrow 数据离开当前信任边界之前执行隐私发布决策。一次
调用同时提供 `RecordBatch`、隐私政策和发布请求；发布请求包含可追踪编号、具体处理用途
及接收方级别。系统依次核验用途授权、接收方授权、逐行同意和 k-匿名阈值，再按照默认
拒绝的列策略删除直接标识符、替换敏感文本并生成发布清单。

项目解决“这批数据能否为这次用途交给这个接收方”的问题，而不是“数据是否满足一般
质量规则”的问题。

## 三、实际问题与应用价值

数据格式正确、内容完整，并不代表它可以被合法或安全地发布。即使一个数据集已经通过
非空、范围、枚举和唯一性检查，仍可能出现以下风险：

1. 数据主体只同意反欺诈研究，数据却被用于广告；
2. 内部可见的数据被直接交给合作方或公开发布；
3. 姓名和账号被删除后，地区、年龄段等准标识符组合仍能识别少数个体；
4. 调用方忘记删除新加入的敏感列；
5. 发布后无法回答由谁、以何用途、按哪份政策放行了哪些列。

MoonSentinel 将这些检查和处置组合成一个失败即关闭的接口，适用于研究数据出域、合作方
数据交付、AI 训练样本准备和浏览器本地隐私筛选。

## 四、目标用户

- 需要向研究团队或合作方交付 Arrow 数据的工程团队；
- 在 MoonBit/Wasm 中执行本地隐私检查的浏览器与边缘应用；
- 需要将发布请求、处置结果和发布字段存档的审计系统；
- 希望在数据质量工具之后增加独立隐私门禁的 MoonBit 项目。

## 五、已完成的核心能力

1. **用途绑定**：`ReleaseRequest` 明确 request id、purpose 和 recipient；
2. **接收方边界**：区分 Internal、Partner 和 Public，未列入政策即整批拒绝；
3. **逐行同意**：同意字段缺失或同意值不覆盖请求用途时隔离对应行；
4. **k-匿名**：在已通过同意检查的候选行上，对多个准标识符组成的等价类执行最小组
   大小检查；
5. **数据最小化**：只有列政策明确选择的列可进入 approved，未配置列默认删除；
6. **安全处置**：直接标识符和敏感列在策略构造时就禁止 `Keep`，只能删除或替换；
7. **四类 Arrow 输出**：approved、quarantine、privacy findings 和 release manifest；
8. **有界诊断**：可限制保存的 finding 数量，但拒绝总数和行处置保持准确；
9. **跨目标验证**：Native、JavaScript、Wasm、Wasm-GC 使用同一套隐私语义。

## 六、核心流程

```text
Arrow RecordBatch + PrivacyPolicy + ReleaseRequest
                       |
                       v
       purpose / recipient authorization
                       |
                       v
                 row consent
                       |
                       v
       k-anonymity on eligible candidates
                       |
                       v
        projection / masking / manifest
          /          |          |          \
    approved    quarantine   findings    manifest
```

整批拒绝时 approved 是零列零行的空批次，不返回可推断的发布 schema；quarantine 仅用于
调用方受控排查。部分行被拒绝时，其余行仍可按同一隐私政策发布。

## 七、可运行示例

演示构造 6 行反欺诈研究数据：

- `user_id` 是直接标识符，必须删除；
- `email` 是敏感字段，发布时替换为 `[EMAIL]`；
- `research_consent` 决定每行能否用于 `fraud_research`；
- `country + age_band` 是准标识符组合，要求 `k >= 2`；
- 接收方必须是政策允许的 `Partner`。

实际输出：

```text
fraud-research-v1/req-2026-001: partial; purpose=fraud_research; recipient=partner; rows=6; released=4; quarantined=2; denials=2; k=2; findings_shown=2; truncated=false
released columns: email, country, age_band, risk_score
approved rows: 4
quarantined rows: 2
privacy findings: 2
release manifest rows: 1
masked email: [EMAIL]
```

其中 1 行因缺少对应同意被隔离，1 行因准标识符等价类只有一个成员被隔离。

## 八、与 MoonVerity 的逐项差异

审核意见指出本项目与近期可用的 MoonVerity 存在重合。项目于 2026-09-20 重新核查
[`Wchwch777/MoonVerity`](https://github.com/Wchwch777/MoonVerity) 的公开 README、申报书、
架构、核心类型、验证规则和 CLI，并据此删除了重合职责。

| 维度 | MoonVerity | 当前 MoonSentinel |
| --- | --- | --- |
| 业务目标 | 数据契约与数据质量校验 | 目的限制、同意和去识别后的隐私发布 |
| 输入 | CSV/JSONL + JSON contract | Arrow RecordBatch + PrivacyPolicy + ReleaseRequest |
| 决策依据 | schema、完整性、范围、枚举、唯一性等 | purpose、recipient、consent、k-anonymity、column treatment |
| 附加能力 | profile、quality score、contract diff、CLI | 默认拒绝投影、敏感字段处置、发布 manifest |
| 输出 | 文本/JSON 校验报告 | 四个 Arrow RecordBatch |
| 主 API | Contract、Rule、ValidationReport | PrivacyPolicy、ReleaseRequest、PrivacyReport |

当前源码已删除 `RequiredColumn`、`NotNull`、数值范围、允许列表、唯一性、跨字段顺序、
Warning/Error 等通用质量 API，也不包含 CSV/JSONL 解析、数据画像、质量评分或合同 diff。
两项目可以串联：先用 MoonVerity 检查质量，再用 MoonSentinel 决定能否出域。

## 九、创新点

1. 将用途和接收方作为运行时发布请求，而不是数据合同的静态描述；
2. 在同一决策中组合行级同意与集合级 k-匿名，两者任一不满足都不会泄露行；
3. 列策略默认拒绝，新增输入列不会因调用方忘记配置而自动流向下游；
4. 在构造策略时禁止直接标识符和敏感列原样发布，错误更早暴露；
5. 发布数据、隔离数据、拒绝原因和审计清单都使用 Arrow，可直接进入 IPC 或 Wasm；
6. 诊断内容不记录原始准标识符值，避免错误报告成为新的敏感信息副本。

## 十、原创与依赖边界

本仓库原创实现隐私政策模型、发布请求、用途/接收方授权、同意检查、k-匿名等价类、
失败关闭策略、列级最小化、隐私 findings、release manifest、测试和演示。

Arrow Schema、Column、RecordBatch 和 IPC 来自 `shunge/arrow`，不作为原创成果申报。
MoonVerity 仅用于功能边界对比，没有复制其源码、数据合同、规则模型或 CLI。

## 十一、当前限制

- k-匿名只在单个 RecordBatch 内计算，尚未支持跨批次状态；
- 当前未实现 l-diversity、t-closeness 或差分隐私；
- UTF-8 固定替换不是密码学匿名化；
- quarantine 仍含源数据，必须由调用方存入受控区域；
- 技术门禁不替代法律意见、数据保护影响评估或组织审批。

## 十二、后续路线

1. 增加 l-diversity，约束等价类内敏感属性分布；
2. 增加政策有效期和用途撤销记录；
3. 增加不可逆哈希/令牌化适配接口，不在库内托管密钥；
4. 支持多批次 k-匿名状态和隐私回归测试；
5. 构建浏览器演示，展示请求、决策、最小化结果和发布清单。

## 十三、验收标准

1. `moon fmt --check` 通过；
2. `moon check --target all --deny-warn` 通过；
3. `moon test --target all --deny-warn` 在四个目标上全部通过；
4. 未授权用途或接收方触发整批拒绝；
5. 未同意行和小于 k 的等价类被隔离；
6. approved 不包含直接标识符和同意字段，敏感邮件已替换；
7. manifest 记录 request id、policy、purpose、recipient、decision、行数、k 和发布列；
8. findings 与 manifest 均可写入 Arrow IPC 并回读；
9. 当前公开 API 不含 MoonVerity 同类的通用质量规则、画像或合同 diff。
