# Changelog

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
