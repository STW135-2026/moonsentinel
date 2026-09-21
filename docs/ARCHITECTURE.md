# MoonSentinel 技术架构

## 系统边界

MoonSentinel 位于已经完成格式解析和质量检查的数据，与即将接收数据的下游系统之间。
`shunge/arrow` 负责 Arrow Schema、Column、RecordBatch 和 IPC；MoonSentinel 只负责隐私
发布授权、k-匿名、l-diversity、最小化处置和审计工件。

```text
                 ReleaseRequest
            request_id / purpose / recipient
                         |
                         v
RecordBatch ------> PrivacyPolicy
                         |
              +----------+----------+
              |                     |
       request authorization   schema safeguards
              |                     |
              +----------+----------+
                         |
                    row consent
                         |
               k-anonymity groups
                         |
           sensitive-value l-diversity
                         |
               minimization / mask
                         |
       +---------+---------+----------+----------+
       |                   |          |          |
   approved          quarantine   findings   manifest
```

## 核心对象

### PrivacyPolicy

保存政策名称、允许用途、允许接收方、同意字段、列分类与处置、最小匿名组大小、敏感
属性多样性列、最小不同值数量及诊断上限。
构造时执行以下失败关闭约束：

- 用途、接收方和同意值不能为空或重复；
- 列政策不能重复；
- `DirectIdentifier` 和 `Sensitive` 不能使用 `Keep`；
- `QuasiIdentifier` 必须参与发布，才能验证发布结果的 k-匿名；
- `minimum_group_size` 至少为 2；
- 启用 l-diversity 时至少指定一个 `Sensitive` UTF-8 列，最小不同值数量至少为 2；
- 至少发布一列且至少声明一个准标识符。

### ReleaseRequest

描述一次具体发布：稳定 request id、purpose 和 recipient。政策是静态授权范围，请求是运行
时上下文；同一份数据对一个用途可放行，对另一个用途可以整批拒绝。

### ColumnPolicy

每个显式列政策包含 `DataClass` 与 `Treatment`。未出现的输入列默认不发布。

- `PublicData`：可保留、替换或删除；
- `QuasiIdentifier`：保留并参与等价类计算；
- `Sensitive`：只能替换或删除；
- `DirectIdentifier`：只能替换或删除；
- `Keep`、`ReplaceUtf8`、`Drop`：当前三种处置。

### PrivacyReport 与 ReleaseBundle

`PrivacyReport` 保存总拒绝数、受限 findings、approved/quarantine 行索引、发布列、k 值和
l-diversity 配置。
`ReleaseBundle` 输出四个 Arrow RecordBatch：

- `approved`：通过授权、同意和 k-匿名，并经过最小化与脱敏的数据；
- `quarantine`：未放行的原始行，只能进入受控区域；
- `findings`：request id、机器码、行号、列名和不含原始值的说明；
- `manifest`：政策、请求、用途、接收方、决策、行数、k、l、敏感多样性列和发布列。

## 决策顺序

1. 重新验证输入 `RecordBatch`，防止调用方在构造后修改底层数组；
2. 检查 purpose 与 recipient 是否在政策允许列表；
3. 校验 consent 和列策略引用的字段及类型；
4. 隔离未同意当前用途的行；
5. 固化候选行集合，按所有准标识符生成确定性等价类 key；
6. 隔离组大小小于 k 的候选行；
7. 在通过 k-匿名的固定候选集上，检查每个等价类的敏感属性不同值数量；
8. 按源顺序生成 approved 与 quarantine；
9. 对 approved 执行显式列投影和替换；
10. 生成 findings 和单行 release manifest。

## k-匿名语义

等价类只统计通过同意检查的候选行，避免一个本就无权发布的行被用来抬高匿名组大小。
多个准标识符按列政策声明顺序组合；当前支持 Boolean、Int32、Int64 和 Utf8。算法采用
确定性双循环，MVP 优先保证语义透明和跨后端一致，尚未声称适用于超大批次。

## l-diversity 语义

l-diversity 只在已经通过同意和 k-匿名的固定候选集上计算。每个配置列必须在列政策中
标为 `Sensitive`，当前仅支持 UTF-8；空值不贡献不同值数量。某等价类中任一配置列的
非空不同值少于 l，该组对应行均以 `l_diversity_violation` 隔离。算法不把已拒绝行用于
抬高多样性，也不把原始敏感值写入 finding。

## 失败关闭语义

- 不允许的 purpose 或 recipient：整批拒绝，approved 返回零列零行；
- consent 列或政策列缺失、类型错误：整批拒绝；
- 行级 consent、k-匿名或 l-diversity 失败：仅隔离对应行；
- 无论 findings 是否因上限截断，拒绝总数和行去向均保持准确；
- findings 不记录原始同意值和准标识符值。

## 与数据质量层的边界

MoonSentinel 没有通用数据质量 `Rule`、字段 contract、CSV/JSONL parser、profile、quality
score 或 contract diff。上游可先运行 MoonVerity 等质量工具，再把合格数据交给本项目完成
隐私发布决策。这一分层是当前架构约束，而不是临时文档声明。
