-- Seed data for text_search_configs table
-- This file contains the standard language configurations for full-text search

-- Clear existing data
TRUNCATE TABLE text_search_configs;

-- Insert language configurations
INSERT INTO text_search_configs (language_code, config_name, is_installed) VALUES
('en', 'pg_catalog.english', true),
('en_us', 'pg_catalog.english', true),
('en_gb', 'pg_catalog.english', true),
('zh', 'jiebacfg', true),
('zh_cn', 'jiebacfg', true),
('zh_tw', 'jiebacfg', true),
('ja', 'pg_catalog.simple', true),
('ja_jp', 'pg_catalog.simple', true),
('ko', 'pg_catalog.simple', true),
('ko_kr', 'pg_catalog.simple', true),
('es', 'pg_catalog.spanish', true),
('fr', 'pg_catalog.french', true),
('de', 'pg_catalog.german', true),
('it', 'pg_catalog.italian', true),
('ru', 'pg_catalog.russian', true),
('ar', 'pg_catalog.simple', true),
('default', 'pg_catalog.simple', true);

-- Add comment for jieba configuration
COMMENT ON COLUMN text_search_configs.config_name IS 'Full-text search configuration name. For Chinese support, ensure pg_jieba extension is installed';
