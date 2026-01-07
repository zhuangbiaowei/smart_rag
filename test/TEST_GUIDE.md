# RAG 测试文档使用指南

本目录包含用于测试 SmartRAG 系统的测试文档和脚本。

## 文件说明

### 测试文档（14篇）

#### 技术类（3篇）
- `python_basics.md` - Python 基础编程
- `javascript_guide.md` - JavaScript 开发指南
- `machine_learning_intro.md` - 机器学习入门

#### 科学类（4篇）
- `quantum_physics_intro.md` - 量子物理导论
- `calculus_fundamentals.md` - 微积分基础
- `biology_ecosystem.md` - 生物生态系统
- `astronomy_basics.md` - 天文学基础

#### 历史类（3篇）
- `ancient_civilizations.md` - 古代文明
- `world_war_ii.md` - 第二次世界大战
- `industrial_revolution.md` - 工业革命

#### 商业类（4篇）
- `marketing_strategies.md` - 营销策略
- `financial_analysis.md` - 财务分析
- `project_management.md` - 项目管理
- `startup_guide.md` - 创业指南

### 测试脚本

#### import_doc.rb
将测试文档导入到 RAG 数据库。

**使用方法：**
```bash
# 导入文档（跳过已存在的）
ruby test/import_doc.rb import

# 强制重新导入
ruby test/import_doc.rb import --force

# 清理所有测试文档
ruby test/import_doc.rb clean

# 清理并重新导入
ruby test/import_doc.rb reimport
```

#### test_rag.rb
测试 RAG 系统的各种搜索功能。

**使用方法：**
```bash
# 运行所有测试
ruby test/test_rag.rb all

# 运行特定测试
ruby test/test_rag.rb vector      # 向量搜索测试
ruby test/test_rag.rb fulltext    # 全文搜索测试
ruby test/test_rag.rb hybrid      # 混合搜索测试
ruby test/test_rag.rb cross       # 跨领域搜索测试
ruby test/test_rag.rb tags        # 基于标签的搜索测试
ruby test/test_rag.rb chinese     # 中文语义搜索测试
ruby test/test_rag.rb alpha       # 不同 alpha 值测试
ruby test/test_rag.rb boolean     # 布尔查询测试
ruby test/test_rag.rb performance  # 性能测试
ruby test/test_rag.rb diversity   # 结果多样性测试
```

## 快速开始

### 1. 确保环境变量已设置

```bash
export OPENAI_API_KEY="your-api-key"
export SMARTRAG_DB_HOST="localhost"
export SMARTRAG_DB_NAME="smart_rag_development"
export SMARTRAG_DB_USER="smart_rag_user"
export SMARTRAG_DB_PASSWORD="your-password"
```

### 2. 导入测试文档

```bash
cd /root/smart_rag
ruby test/import_doc.rb import
```

### 3. 运行搜索测试

```bash
ruby test/test_rag.rb all
```

## 测试覆盖

### 测试1: 向量搜索 - 语义相似性
测试 RAG 系统是否能根据语义理解返回相关文档。

**测试用例：**
- "什么是导数？" → 微积分基础
- "如何使用 Python 定义函数？" → Python 基础编程
- "生态系统中的能量是如何流动的？" → 生物生态系统

**预期效果：** 语义相似度高的文档排在前面。

### 测试2: 全文搜索 - 精确关键词匹配
测试 RAG 系统是否能精确匹配关键词。

**测试用例：**
- "机器学习算法" → 机器学习入门
- "薛定谔猫" → 量子物理导论
- "第二次世界大战" → 第二次世界大战

**预期效果：** 包含精确关键词的文档排在前面。

### 测试3: 混合搜索 - 结合向量和全文
测试 RAG 系统是否能平衡语义和关键词匹配。

**测试用例：**
- "Python 数据结构" → 技术类文档
- "古代文明的历史" → 历史类文档
- "生态系统" → 科学类文档

**预期效果：** 返回语义相关且包含关键词的文档。

### 测试4: 跨领域搜索
测试 RAG 系统是否能识别跨领域的内容关联。

**测试用例：**
- "数学在计算机科学中的应用" → 数学和技术类文档
- "工业革命的技术创新" → 历史和技术类文档
- "生物学的数学模型" → 科学类文档

**预期效果：** 返回多个领域的相关文档。

### 测试5: 基于标签的搜索
测试 RAG 系统是否能通过标签筛选文档。

**测试用例：**
- 标签: ["编程"] → Python 和 JavaScript 文档
- 标签: ["历史"] → 历史类文档
- 标签: ["AI", "机器学习"] → 机器学习文档

**预期效果：** 只返回具有指定标签的文档。

### 测试6: 中文语义搜索
测试 RAG 系统对中文的理解能力。

**测试用例：**
- "如何优化数据库性能？" → 技术类文档
- "生态系统的食物链是如何运作的？" → 科学类文档
- "古代文明的主要特点是什么？" → 历史类文档

**预期效果：** 准确理解中文查询并返回相关文档。

### 测试7: 不同 alpha 值的混合搜索
测试 alpha 参数对搜索结果的影响。

**测试用例：**
- alpha=0.0 (纯全文搜索)
- alpha=0.5 (均衡混合)
- alpha=1.0 (纯向量搜索)

**预期效果：** 不同 alpha 值产生不同的结果排序。

### 测试8: 布尔查询（全文搜索）
测试 RAG 系统是否支持布尔运算符。

**测试用例：**
- "Python AND 函数"
- "Python OR JavaScript"
- '"机器学习" AND "算法"'

**预期效果：** 正确处理 AND、OR 等布尔运算符。

### 测试9: 搜索性能测试
测试各种搜索类型的性能。

**测试内容：**
- 向量搜索平均响应时间
- 全文搜索平均响应时间
- 混合搜索平均响应时间

**预期效果：** 所有搜索类型的平均响应时间 < 1秒。

### 测试10: 结果多样性测试
测试 RAG 系统是否能返回多样化的结果。

**测试用例：**
- 查询 "科学" 返回多个科学类文档

**预期效果：** 结果包含多个不同的科学领域文档。

## 文档元数据

每个文档包含以下元数据：
- **标题**: 文档标题
- **标签**: 3-5个相关标签
- **类别**: 技术/科学/历史/商业

## 注意事项

1. 首次使用前确保数据库已正确配置
2. 导入文档时需要 OpenAI API 密钥用于生成嵌入
3. 测试脚本会记录详细的结果信息
4. 如果测试失败，请检查数据库连接和 API 配置

## 故障排除

### 问题：文档导入失败
**解决方案：**
- 检查数据库连接
- 确认 OpenAI API 密钥有效
- 查看日志了解详细错误信息

### 问题：搜索无结果
**解决方案：**
- 确认文档已成功导入
- 检查嵌入是否已生成
- 尝试不同的搜索类型

### 问题：测试失败
**解决方案：**
- 查看测试输出的详细错误信息
- 检查数据库中的文档数量
- 确认所有测试文档都已正确导入

## 扩展测试

你可以通过修改 `test_rag.rb` 添加更多测试用例，或者添加新的测试文档来扩展测试覆盖范围。
