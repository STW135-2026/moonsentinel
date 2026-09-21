# MoonSentinel 演示步骤

## 准备与质量门禁

```sh
moon update
moon fmt --check
moon info
moon check --target all --deny-warn
moon test --target all --deny-warn
```

预期结果是 9 项测试在 wasm、wasm-gc、js、native 四个目标上全部通过。

## 运行

```sh
moon run cmd/main --target native --deny-warn
```

演示包含 6 行反欺诈研究数据：

- 请求 `req-2026-001` 的用途是 `fraud_research`，接收方是 `Partner`；
- `research_consent=yes` 才覆盖该用途；
- `country + age_band` 作为准标识符，要求每个等价类至少 2 行；
- `case_outcome` 作为不发布的敏感属性，要求每个等价类至少 2 个不同非空值；
- `user_id` 和 `research_consent` 不进入发布数据；
- `email` 在发布前替换为 `[EMAIL]`；
- `risk_score` 原样保留。

预期输出：

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

IPC 字节数可能随底层依赖版本变化；其余决策和计数应保持一致。

## 讲解顺序

1. 打开 `ReleaseRequest`，说明发布决策绑定 request id、purpose 和 recipient；
2. 打开 `PrivacyPolicy`，说明同意字段、数据分类、输出处置、`k=2` 和 `l=2`；
3. 指出 consent=no 的行先被隔离，不会参与匿名组计数；
4. 指出 DE + 50-59 只有一行，因此触发 `KAnonymityViolation`；
5. 指出剩余匿名组的 `case_outcome` 均有 2 个不同值，满足 l-diversity；
6. 展示 approved 只剩四列，直接标识符、同意列和多样性敏感列按策略消失；
7. 展示 findings 不复制原始准标识符或敏感属性值，manifest 记录完整请求上下文；
8. 打开差异化核查，说明项目已经删除 MoonVerity 同类的数据质量规则。

## 建议答辩问答

**为什么不把这些功能并入普通数据质量规则？**

因为用途、接收方和同意是一次发布的动态授权上下文，k-匿名也是对最终候选集合的隐私
约束。数据通过非空、范围或枚举检查后，仍然可能没有权利被发布。

**k-匿名是否等于完全匿名？**

不是。当前实现组合 k-匿名和 distinct l-diversity，但没有实现 t-closeness 或差分隐私，
也不声称抵御所有背景知识攻击。项目不会作出超出实现范围的隐私承诺。

**quarantine 为什么保留原始数据？**

它用于受控排查，不属于可发布输出。实际部署必须把 quarantine 写入访问受限的区域；
公开或合作方出口只能连接 approved。
