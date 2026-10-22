-- =====================================================================
-- Syllabi are entered as content (courses by year and semester) instead
-- of uploaded as PDF files. The content is stored as JSON:
--   {"programTitle": "...", "notes": "...",
--    "sections": [{"title": "First Year - First Semester",
--                  "courses": [{"code": "IT 111",
--                               "title": "Introduction to Computing",
--                               "units": 3}]}]}
-- Learning materials still use file_url. Safe to re-run.
-- =====================================================================

alter table public.materials
  add column if not exists content jsonb;

-- A syllabus needs either content or (older ones) a file.
comment on column public.materials.content is
  'Syllabus content (courses by semester) for type = syllabus';
