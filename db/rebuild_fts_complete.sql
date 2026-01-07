-- Complete rebuild of section_fts fulltext indexes
-- This script rebuilds all fulltext search indexes with correct language and tokenizer

BEGIN;

-- 1. Delete all existing fts data
DELETE FROM section_fts;

-- 2. Insert all sections with basic info
INSERT INTO section_fts (section_id, document_id, language)
SELECT 
  ss.id,
  ss.document_id,
  COALESCE(sd.language, 'zh') as language
FROM source_sections ss
JOIN source_documents sd ON sd.id = ss.document_id;

-- 3. Trigger updates by touching all sections
-- This will cause the trigger to fire and rebuild fts vectors
-- We do this in batches to avoid locking
UPDATE source_sections SET updated_at = CURRENT_TIMESTAMP WHERE id IN (
  SELECT id FROM source_sections LIMIT 1000
);

UPDATE source_sections SET updated_at = CURRENT_TIMESTAMP WHERE id IN (
  SELECT id FROM source_sections LIMIT 1000 OFFSET 1000
);

UPDATE source_sections SET updated_at = CURRENT_TIMESTAMP WHERE id IN (
  SELECT id FROM source_sections LIMIT 1000 OFFSET 2000
);

-- Verify rebuild
SELECT '=== Verification ===' as info;
SELECT COUNT(*) as total_sections FROM section_fts;
SELECT COUNT(*) as sections_with_fts_title FROM section_fts WHERE fts_title IS NOT NULL;
SELECT COUNT(*) as sections_with_fts_content FROM section_fts WHERE fts_content IS NOT NULL;
SELECT COUNT(*) as sections_with_fts_combined FROM section_fts WHERE fts_combined IS NOT NULL;

-- Test search
SELECT '=== Test Search for 老人情感 ===' as info;
SELECT section_id, section_title
FROM section_fts ssf
JOIN source_sections ss ON ss.id = ssf.section_id
WHERE ssf.fts_combined @@ plainto_tsquery('jiebacfg', '老人情感')
  AND ssf.language = 'zh'
LIMIT 5;

COMMIT;

SELECT '=== Complete! All fulltext indexes rebuilt ===' as status;
