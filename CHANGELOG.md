# Changelog

## 0.4.0

- 增加扁平 JSONL 与 Arrow RecordBatch 的双向适配，发布仍复用同一套策略。
- 增加 JSONL 端到端发布、脱敏导出、类型提升、缺失值和非法输入测试。
- 增加 CSV 与 Arrow RecordBatch 的双向适配；CSV 支持表头、引号转义、逗号、LF/CRLF 和引号内换行。
- CSV 导入保留 UTF-8 文本，未加引号的空单元格转为 null，引用的空字符串保留；格式错误、重复表头和列数不一致会被拒绝。
- 增加 CSV 经过隐私策略的端到端用例，以及格式错误输入测试。
- 同意值改为按允许用途分别配置；缺失或越权的用途映射会使策略创建失败。
- JSONL 导入和导出采用相同的精确数值范围，超范围的 Int64/Float64 在导出时显式拒绝。
- 自动化测试共 16 项，覆盖用途绑定同意、JSONL 数值往返、隐私发布流程和 CSV/JSONL 格式适配。
- 将项目定位调整为多场景数据共享前的授权核验与隐私发布工具。
- 补充实际使用者、临时导出脚本的风险和 6 行反欺诈研究交付案例。
- 明确 approved、quarantine、findings、manifest 在交付流程中的用途。
- 更新申报书、README、架构、演示和差异化记录，功能表述保持与现有实现一致。

## 0.3.0

- 根据 MoonVerity 重合审核，删除通用数据质量 Contract、Rule 和 Warning/Error API。
- 新增用途与接收方绑定的 `ReleaseRequest` 和失败关闭授权。
- 新增逐行同意检查以及只在获准候选行上计算的多列 k-匿名。
- 新增只在通过 k-匿名的固定候选集上计算的敏感属性 l-diversity。
- 新增直接标识符、敏感字段、准标识符和公开数据四类字段分类。
- 新增默认拒绝列投影、敏感 UTF-8 替换及整批拒绝的零列输出。
- 新增 Arrow 原生 privacy findings 和单行 release manifest。
- 将测试更新为 9 项，并在 Native、JavaScript、Wasm、Wasm-GC 上验证。
- 补充与 MoonVerity 的逐项源码差异和防回退边界。

## 0.2.0

- 将项目从 MoonQuery 更名并重构为 MoonSentinel。
- 移除与 MoonFrame 重合的查询、排序、分组、连接和逻辑计划实现。
- 新增 Arrow RecordBatch 质量规则、错误和警告严重度、行隔离与数据集级阻断。
- 新增受限诊断收集、准确总计和 Arrow 原生 findings 输出。
- 新增 approved 字段替换脱敏和 quarantine 原值保留。
- 新增 7 项测试，并在 Native、JavaScript、Wasm、Wasm-GC 上验证。

## 0.1.0

- 初始 MoonQuery 探索版本。该版本只保留在 Git 历史中，不属于当前申报成果。
