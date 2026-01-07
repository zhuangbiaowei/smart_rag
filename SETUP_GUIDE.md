# SmartRAG 设置和安装指南

## 系统要求

### 操作系统
- Linux (Ubuntu 20.04+, CentOS 8+, Debian 10+)
- macOS (11.0+)
- Windows 10+ (WSL2 推荐)

### 软件依赖
- Ruby 3.3.0+
- PostgreSQL 16.0+
- Python 3.8+ (用于 markitdown)
- GCC/G++ 9.0+ (用于编译 pgvector)

### 硬件要求
- 内存: 最低 4GB, 推荐 8GB+
- 存储: 50GB+ 可用空间
- CPU: 4+ 核心 (用于并行搜索)

## 安装步骤

### 1. 安装 PostgreSQL 和扩展

#### Ubuntu/Debian

```bash
# 添加 PostgreSQL 官方仓库
sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -

# 更新包列表
sudo apt-get update

# 安装 PostgreSQL 16
sudo apt-get install -y postgresql-16 postgresql-16-pgvector postgresql-16-pg_jieba

# 启动服务
sudo systemctl start postgresql
sudo systemctl enable postgresql
```

#### CentOS/RHEL

```bash
# 安装 PostgreSQL 16
sudo dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-8-x86_64/pgdg-redhat-repo-latest.noarch.rpm
sudo dnf -y module disable postgresql
sudo dnf install -y postgresql16-server postgresql16-contrib

# 启用 pgvector 和 pg_jieba (需要编译安装)
sudo dnf install -y gcc make postgresql16-devel

# 编译安装 pgvector
git clone https://github.com/pgvector/pgvector.git
cd pgvector
git checkout v0.7.0
make
sudo make install

# 安装 pg_jieba (中文分词)
git clone https://github.com/jaiminpan/pg_jieba_pg16.git
cd pg_jieba_pg16
make
sudo make install
```

#### macOS (使用 Homebrew)

```bash
# 安装 PostgreSQL
brew install postgresql@16

# 启动服务
brew services start postgresql@16

# 安装 pgvector
git clone https://github.com/pgvector/pgvector.git
cd pgvector
git checkout v0.7.0
make
make install

# 安装 pg_jieba
git clone https://github.com/jaiminpan/pg_jieba_pg16.git
cd pg_jieba_pg16
make
make install

# 设置 PostgreSQL 环境
export PATH="/usr/local/opt/postgresql@16/bin:$PATH"
```

### 2. 配置 PostgreSQL

#### 2.1 创建数据库和用户

```bash
# 切换到 postgres 用户
sudo -u postgres psql

-- 创建数据库
CREATE DATABASE smart_rag_development;
CREATE DATABASE smart_rag_test;

-- 创建用户
CREATE USER smart_rag_user WITH PASSWORD 'your_secure_password';

-- 授权
GRANT ALL PRIVILEGES ON DATABASE smart_rag_development TO smart_rag_user;
GRANT ALL PRIVILEGES ON DATABASE smart_rag_test TO smart_rag_user;

-- 退出 psql
\q
```

#### 2.2 启用扩展

```bash
# 连接到数据库
sudo -u postgres psql smart_rag_development

-- 启用扩展
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pg_jieba;

-- 验证安装
SELECT * FROM pg_extension WHERE extname IN ('vector', 'pg_jieba');

-- 应该看到两行输出
```

#### 2.3 优化 PostgreSQL 配置

编辑 `/etc/postgresql/16/main/postgresql.conf` (Ubuntu) 或 `/var/lib/pgsql/16/data/postgresql.conf` (CentOS):

```conf
# 共享内存和缓存
shared_buffers = 2GB
work_mem = 64MB
maintenance_work_mem = 512MB

# 并行查询
max_parallel_workers_per_gather = 4
max_parallel_workers = 8

# 检查点和 WAL
checkpoint_timeout = 15min
max_wal_size = 4GB

# 向量搜索优化
ivfflat.probes = 10  # 增加探测数以提高准确性

# 日志 (可选)
log_statement = 'all'
log_min_duration_statement = 1000  # 记录慢查询 (ms)
```

重启 PostgreSQL:

```bash
sudo systemctl restart postgresql
```

### 3. 安装 Ruby 依赖

#### 3.1 安装 Ruby 3.3+

```bash
# 使用 rbenv (推荐)
curl -fsSL https://github.com/rbenv/rbenv-installer/raw/HEAD/bin/rbenv-installer | bash

# 添加到 shell
echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.bashrc
echo 'eval "$(rbenv init -)"' >> ~/.bashrc
source ~/.bashrc

# 安装 Ruby 3.3.4
rbenv install 3.3.4
rbenv global 3.3.4

# 验证
ruby --version
# 应该显示 ruby 3.3.4
```

#### 3.2 安装 Bundler

```bash
gem install bundler
```

#### 3.3 安装项目依赖

```bash
# 克隆项目 (如果尚未克隆)
git clone https://github.com/your-org/smart_rag.git
cd smart_rag

# 安装 gems
bundle install
```

### 4. 安装 Python markitdown

SmartRAG 使用 Python 的 markitdown 进行文档转换。

#### 4.1 安装 Python 3.8+

```bash
# Ubuntu/Debian
sudo apt-get install -y python3 python3-pip

# CentOS/RHEL
sudo dnf install -y python3 python3-pip

# macOS (Homebrew)
brew install python3
```

#### 4.2 安装 markitdown

```bash
pip3 install markitdown

# 验证安装
markitdown --version
```

#### 4.3 配置 Ruby-Python 桥接

SmartRAG 自动检测 Python，无需额外配置。如果需要指定 Python 路径:

```ruby
# config/smart_rag.yml
markitdown:
  python_path: '/usr/bin/python3'  # 或 '/usr/local/bin/python3'
```

### 5. 数据库迁移

#### 5.1 创建数据库表

```bash
# 创建数据库 (如果不存在)
bundle exec rake db:create

# 运行迁移
bundle exec rake db:migrate

# 运行测试数据库迁移
RACK_ENV=test bundle exec rake db:migrate
```

#### 5.2 加载种子数据

```bash
# 加载语言配置
psql -U smart_rag_user -d smart_rag_development -f db/seeds/text_search_configs.sql
```

#### 5.3 验证数据库

```bash
# 连接到数据库
psql -U smart_rag_user -d smart_rag_development

-- 检查表
dt

-- 应该看到以下表:
-- embeddings
-- research_topic_sections
-- research_topic_tags
-- research_topics
-- search_logs
-- section_fts
-- section_tags
-- source_documents
-- source_sections
-- tags
-- text_search_configs

-- 验证嵌入表有向量列
\d+ embeddings

-- 验证全文检索表有 tsvector 列
\d+ section_fts

-- 退出
\q
```

### 6. 配置环境变量

创建 `.env` 文件:

```bash
# 数据库
cp .env.example .env
```

编辑 `.env`:

```bash
# PostgreSQL
SMARTRAG_DB_HOST=localhost
SMARTRAG_DB_PORT=5432
SMARTRAG_DB_NAME=smart_rag_development
SMARTRAG_DB_USER=smart_rag_user
SMARTRAG_DB_PASSWORD=your_secure_password

# Test database
SMARTRAG_TEST_DB_NAME=smart_rag_test
SMARTRAG_TEST_DB_USER=smart_rag_user
SMARTRAG_TEST_DB_PASSWORD=your_secure_password

# LLM API (OpenAI)
OPENAI_API_KEY=sk-...

# 可选配置
SMARTRAG_LOG_LEVEL=info
SMARTRAG_MAX_WORKERS=5
```

### 7. 运行测试

```bash
# 运行所有测试
bundle exec rspec

# 运行特定测试
bundle exec rspec spec/models
bundle exec rspec spec/services

# 使用并行测试 (如果使用 parallel_tests gem)
bundle exec rake parallel:spec
```

### 8. 验证安装

```bash
# 启动交互式控制台
bundle exec irb -r smart_rag

# 测试连接
SmartRAG.config = SmartRAG::Config.load
SmartRAG.init_db

# 添加测试文档
smart_rag = SmartRAG::SmartRAG.new(SmartRAG.config)
result = smart_rag.add_document('https://example.com', generate_embeddings: false)
puts "✓ Document added: #{result[:document_id]}"

# 搜索测试
results = smart_rag.search('test', limit: 1)
puts "✓ Search working: #{results[:results].length} results"

# 查看统计
stats = smart_rag.statistics
puts "✓ Statistics: #{stats.inspect}"
```

## Docker 安装 (可选)

### 1. 构建 Docker 镜像

```dockerfile
# Dockerfile
FROM ruby:3.3.4-slim

# 安装系统依赖
RUN apt-get update && apt-get install -y \
    build-essential \
    postgresql-client \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

# 安装 Python markitdown
RUN pip3 install markitdown

# 设置工作目录
WORKDIR /app

# 复制 Gemfile
COPY Gemfile Gemfile.lock ./
RUN bundle install

# 复制应用代码
COPY . .

# 创建非 root 用户
RUN groupadd -r smart_rag && useradd -r -g smart_rag smart_rag
USER smart_rag

# 暴露端口
EXPOSE 3000

CMD ["bundle", "exec", "irb", "-r", "smart_rag"]
```

构建:

```bash
docker build -t smart_rag .
```

### 2. 使用 Docker Compose

```yaml
# docker-compose.yml
version: '3.8'

services:
  db:
    image: pgvector/pgvector:pg16
    environment:
      POSTGRES_DB: smart_rag_development
      POSTGRES_USER: smart_rag_user
      POSTGRES_PASSWORD: your_secure_password
    volumes:
      - postgres_data:/var/lib/postgresql/data
    ports:
      - "5432:5432"

  app:
    build: .
    depends_on:
      - db
    environment:
      SMARTRAG_DB_HOST: db
      SMARTRAG_DB_NAME: smart_rag_development
      SMARTRAG_DB_USER: smart_rag_user
      SMARTRAG_DB_PASSWORD: your_secure_password
      OPENAI_API_KEY: ${OPENAI_API_KEY}
    volumes:
      - .:/app
    stdin_open: true
    tty: true

volumes:
  postgres_data:
```

启动:

```bash
docker-compose up -d
docker-compose exec app bash
```

## 生产环境配置

### 1. 数据库优化

```sql
-- 创建分区表 (对于大型数据集)
CREATE TABLE embeddings_2024 PARTITION OF embeddings
    FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');

-- 创建更具体的索引
CREATE INDEX CONCURRENTLY idx_embeddings_cosine ON embeddings
    USING ivfflat (vector vector_cosine_ops)
    WITH (lists = 100);

-- 自动清理配置
ALTER TABLE embeddings SET (autovacuum_vacuum_scale_factor = 0.1);
ALTER TABLE embeddings SET (autovacuum_analyze_scale_factor = 0.05);
```

### 2. 连接池配置

```yaml
# config/smart_rag.yml
production:
  database:
    pool: 25              # 增加连接池
    timeout: 5000         # 连接超时
    connect_timeout: 10   # 连接尝试超时
    keepalives: true
    keepalives_idle: 600
    keepalives_interval: 60
    keepalives_count: 5
```

### 3. 监控和日志

```ruby
# 配置结构化日志
require 'logger'
require 'json'

class JsonLogger < Logger
  def format_message(severity, datetime, progname, msg)
    {
      timestamp: datetime.iso8601,
      level: severity,
      message: msg,
      pid: Process.pid
    }.to_json + "\n"
  end
end

SmartRAG.logger = JsonLogger.new('log/smart_rag.log')
SmartRAG.logger.level = Logger::INFO
```

### 4. 备份策略

```bash
#!/bin/bash
# backup.sh

# 数据库备份
pg_dump -U smart_rag_user -h localhost smart_rag_development > backups/smart_rag_$(date +%Y%m%d).sql

# 向量化备份 (可选)
psql -U smart_rag_user -h localhost -d smart_rag_development -c "COPY embeddings TO 'backups/embeddings_$(date +%Y%m%d).csv' CSV;"

# 压缩
gzip backups/*_$(date +%Y%m%d).*

# 清理旧备份 (保留30天)
find backups/ -name "*.gz" -mtime +30 -delete
```

## 故障排除

### 问题 1: pgvector 安装失败

**症状**: `ERROR: could not open extension control file`

**解决**:
```bash
# 确保 PostgreSQL dev 包已安装
sudo apt-get install postgresql-server-dev-16

# 重新编译 pgvector
cd pgvector
clean && make
sudo make install
```

### 问题 2: pg_jieba 中文分词不工作

**症状**: `ERROR: text search configuration "jieba" does not exist`

**解决**:
```bash
# pg_jieba 使用不同的配置名
sudo -u postgres psql

-- 检查可用配置
SELECT * FROM pg_ts_config;

-- pg_jieba 可能使用 jiebacfg
-- 更新种子数据
UPDATE text_search_configs SET config_name = 'jiebacfg' WHERE language_code = 'zh';
```

### 问题 3: 向量维度不匹配

**症状**: `ERROR: expected 1024 dimensions, not 768`

**解决**:
```ruby
# 检查嵌入模型配置
config = {
  llm: {
    model: 'text-embedding-ada-002',  # OpenAI: 1536维
    # model: 'text-embedding-3-small',  # OpenAI: 1536维
    # 或自定义维度
    dimensions: 1024  # 确保与迁移一致
  }
}
```

### 问题 4: 连接池耗尽

**症状**: `Sequel::PoolTimeout: timeout: 5.0`

**解决**:
```ruby
# 增加连接池和超时
config = {
  database: {
    pool: 50,          # 增加池大小
    timeout: 10000,    # 增加超时
    max_connections: 100
  }
}
```

### 问题 5: markitdown 找不到

**症状**: `Errno::ENOENT: No such file or directory - markitdown`

**解决**:
```bash
# 检查 Python 路径
which python3
which markitdown

# 如果不在 PATH，配置完整路径
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# 或在 config 中指定
markitdown:
  python_path: '/usr/bin/python3'
  markitdown_path: '/usr/local/bin/markitdown'
```

## 验证步骤

运行以下命令验证安装:

```bash
# 1. 检查 PostgreSQL 版本
psql --version  # 应该显示 16.x

# 2. 检查扩展
psql -U smart_rag_user -d smart_rag_development -c "SELECT * FROM pg_extension WHERE extname IN ('vector', 'pg_jieba');"

# 3. 检查 markitdown
markitdown --version

# 4. 运行快速测试
bundle exec rspec spec/models --format documentation

# 5. 运行集成测试
bundle exec rspec spec/integration/api_end_to_end_workflow_spec.rb

# 预期结果: 所有测试应该通过
```

## 下一步

安装完成后，查看:
- [API 文档](API_DOCUMENTATION.md) - 完整的 API 参考
- [使用示例](USAGE_EXAMPLES.md) - 实际使用示例
- [性能优化](PERFORMANCE_TUNE.md) - 性能调优指南

## 支持

如果遇到问题:
1. 检查 [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
2. 查看 [FAQ](FAQ.md)
3. 提交 Issue: https://github.com/your-org/smart_rag/issues
