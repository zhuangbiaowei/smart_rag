-- Database fix script for SmartRAG search issues
-- This script fixes three bugs:
-- 1. Incorrect jieba configuration name
-- 2. Wrong language in existing data
-- 3. Rebuild fulltext indexes with correct tokenizer

BEGIN;

-- Fix 1: Update text_search_configs to use correct jieba config name
UPDATE text_search_configs
SET config_name = 'jiebacfg'
WHERE config_name = 'jieba';

-- Verify the fix
SELECT 'Fixed text_search_configs: Changed jieba to jiebacfg' AS status,
       COUNT(*) as updated_rows
FROM text_search_configs
WHERE config_name = 'jiebacfg';

-- Fix 2: Detect and update language for source_documents
-- For documents with Chinese content, set language to 'zh'
-- First, identify documents with Chinese content based on sections
WITH chinese_sections AS (
  SELECT DISTINCT ss.document_id
  FROM source_sections ss
  WHERE ss.content ~ '[\u4e00-\u9fff]'
)
UPDATE source_documents sd
SET language = 'zh'
WHERE sd.id IN (SELECT document_id FROM chinese_sections)
  AND (sd.language = 'en' OR sd.language IS NULL OR sd.language = '');

-- Verify the fix
SELECT 'Fixed source_documents language: Set to zh for Chinese documents' AS status,
       COUNT(*) as updated_docs
FROM source_documents
WHERE language = 'zh';

-- Fix 3: Rebuild fulltext indexes
-- Delete existing fulltext indexes
DELETE FROM section_fts;

-- Rebuild fulltext indexes using the trigger
-- The trigger will use the updated language and correct config name
INSERT INTO section_fts (section_id, document_id, language, fts_title, fts_content, fts_combined)
SELECT
  ss.id,
  ss.document_id,
  COALESCE(sd.language, 'zh'),
  NULL,
  NULL,
  NULL
FROM source_sections ss
JOIN source_documents sd ON sd.id = ss.document_id;

-- Now update the fts fields by calling the trigger
-- This will cause the trigger to fire and rebuild with correct language/tokenizer
UPDATE source_sections SET updated_at = CURRENT_TIMESTAMP;

COMMIT;

-- Verification queries
-- Check updated text_search_configs
SELECT '=== Verification: text_search_configs ===' AS info;
SELECT language_code, config_name FROM text_search_configs WHERE language_code LIKE 'zh%';

-- Check updated source_documents
SELECT '=== Verification: source_documents ===' AS info;
SELECT id, title, language FROM source_documents;

-- Check rebuilt section_fts
SELECT '=== Verification: section_fts sample ===' AS info;
SELECT section_id, language FROM section_fts LIMIT 5;

-- Test fulltext search with Chinese
SELECT '=== Test: Fulltext search with Chinese ===' AS info;
SELECT ss.section_title, ssf.language
FROM section_fts ssf
JOIN source_sections ss ON ss.id = ssf.section_id
WHERE ssf.fts_combined @@ to_tsquery('jiebacfg', '小动物')
LIMIT 3;
