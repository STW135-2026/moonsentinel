# MoonSentinel 开发与差异化记录

本文记录可由代码、测试和 Git 历史核验的方向调整，避免项目定位只停留在申报文案。

## 2026-09-20 隐私发布方向重构

### 触发原因

复核 `Wchwch777/MoonVerity` 后确认，旧版 MoonSentinel 的 Required、非空、范围、枚举、
唯一性、质量报告等能力与其数据质量门禁存在明显重叠。

### 已移除的重叠面

- 通用 `Contract`、`Rule`、`Severity` 和 `ValidationReport` 公共模型；
- Required、NotNull、Range、AllowList、Unique、跨字段比较等质量规则；
- “质量合格或不合格”作为核心项目价值的表述；
- 把通用质量诊断、数据画像或合同差异列入路线图的表述。

### 已落地的新能力

- `ReleaseRequest` 绑定请求编号、用途和接收方；
- `PrivacyPolicy` 定义用途与接收方允许列表；
- `ConsentRequirement` 对每行核验当前用途的同意；
- 在同意候选集内执行多列 k-匿名，避免未授权记录虚增群体；
- 在通过 k-匿名的固定候选集内执行敏感属性 l-diversity；
- `DataClass` 与 `Treatment` 强制敏感列删除或替换；
- 未配置字段默认不进入获准数据，实现失败关闭的数据最小化；
- 同时返回 approved、quarantine、findings 和 manifest 四类 Arrow 批次。

### 对照证据

本次对照阅读了 MoonVerity 的 README、申报书、架构文档及以下实现：

- `core/quality.mbt`
- `core/validation.mbt`
- `core/profile.mbt`
- `core/diff.mbt`
- `cli/commands.mbt`

逐项对比和当前不做事项见 [DIFFERENTIATION.zh-CN.md](DIFFERENTIATION.zh-CN.md)。

### 验证基线

- `moon fmt --check`
- `moon check --target all --deny-warn`
- `moon test --target all --deny-warn`
- 9 项测试在 Native、JavaScript、Wasm、Wasm-GC 四个目标通过；
- 演示输出验证 6 行输入、4 行放行、2 行隔离、字段最小化、邮件替换和 IPC 交接。

## 后续差异化复核清单

每次扩展前先回答以下问题：

1. 新能力是否属于通用数据质量、数据画像或合同差异；
2. 是否直接支撑用途、接收方、同意、再识别风险或审计证据；
3. 是否能通过新的公开 API 和自动化测试证明，而不是只修改文案；
4. README、Markdown 申报书、Word 申报书、演示与代码是否保持同一口径；
5. GitHub 是否出现新的同类 MoonBit 项目，需要更新对比说明。

计划中的 t-closeness、策略版本签名和可验证发布清单也必须通过这份清单后再实现。
