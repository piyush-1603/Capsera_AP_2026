-- =============================================================================
-- CAPSERA — Database Query Repository (`dbms/04_queries.sql`)
-- Course: Database Management Systems (DBMS) & Advanced Programming (AP)
-- System: CAPSERA — Digital Capacity Building and Competency Tracking Portal
-- Database Engine: PostgreSQL 15+ (capsera_db)
-- Checkpoint: CP-3 (Operational Queries & Relational Join Catalog)
--
-- All application queries across the 18 canonical tables and 4 functional modules.
-- Every query is explicitly categorized and labeled as:
--   -- READ  : Data retrieval, multi-table joins, reporting, dashboard analytics.
--   -- WRITE : Inserts, transactional state mutations, updates, upserts, deletes.
-- =============================================================================


-- =============================================================================
-- MODULE 1: IDENTITY, AUTHENTICATION & USER GOVERNANCE (MEMBER 1)
-- Canonical Tables: users, trainee_profiles, trainer_profiles
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1.1 User Registration (Trainee / Trainer / Admin)
-- Inserts a new user record with default status 'PENDING'.
-- -----------------------------------------------------------------------------
-- WRITE
INSERT INTO users (
    full_name,
    email,
    password_hash,
    role,
    status
) VALUES (
    $1,                -- full_name: VARCHAR(150)
    LOWER(BTRIM($2)),  -- email: VARCHAR(255)
    $3,                -- password_hash: VARCHAR(255)
    $4,                -- role: 'TRAINEE' | 'TRAINER' | 'ADMIN'
    'PENDING'          -- status default
)
RETURNING id, full_name, email, role, status, created_at;


-- -----------------------------------------------------------------------------
-- 1.2 Create Initial Trainee Profile
-- Associated 1:1 extension record created upon Trainee registration.
-- -----------------------------------------------------------------------------
-- WRITE
INSERT INTO trainee_profiles (
    user_id,
    headline,
    organization,
    biography,
    qualifications,
    work_experience,
    interests,
    external_certifications
) VALUES (
    $1, -- user_id: BIGINT
    $2, -- headline: VARCHAR(200)
    $3, -- organization: VARCHAR(200)
    $4, -- biography: TEXT
    $5, -- qualifications: TEXT
    $6, -- work_experience: TEXT
    $7, -- interests: TEXT
    $8  -- external_certifications: TEXT
)
RETURNING id, user_id, headline, organization, created_at;


-- -----------------------------------------------------------------------------
-- 1.3 Create Initial Trainer Profile
-- Associated 1:1 extension record created upon Trainer registration.
-- -----------------------------------------------------------------------------
-- WRITE
INSERT INTO trainer_profiles (
    user_id,
    headline,
    organization,
    biography,
    qualifications,
    work_experience,
    subject_expertise,
    years_of_experience
) VALUES (
    $1, -- user_id: BIGINT
    $2, -- headline: VARCHAR(200)
    $3, -- organization: VARCHAR(200)
    $4, -- biography: TEXT
    $5, -- qualifications: TEXT
    $6, -- work_experience: TEXT
    $7, -- subject_expertise: VARCHAR(255)
    $8  -- years_of_experience: NUMERIC(4,1)
)
RETURNING id, user_id, headline, subject_expertise, years_of_experience, created_at;


-- -----------------------------------------------------------------------------
-- 1.4 User Authentication & Session Resolution
-- Resolves user credentials and loads role-specific profile details in a single query.
-- Uses case-insensitive email index (uq_users_email_ci) and LEFT JOINs on profiles.
-- -----------------------------------------------------------------------------
-- READ
SELECT 
    u.id AS user_id,
    u.full_name,
    u.email,
    u.password_hash,
    u.role,
    u.status,
    u.approved_by,
    u.approved_at,
    approver.full_name AS approved_by_name,
    tp.id AS trainee_profile_id,
    tp.headline AS trainee_headline,
    tp.organization AS trainee_organization,
    trp.id AS trainer_profile_id,
    trp.headline AS trainer_headline,
    trp.subject_expertise,
    trp.years_of_experience
FROM users u
LEFT JOIN users approver ON u.approved_by = approver.id
LEFT JOIN trainee_profiles tp ON u.id = tp.user_id AND u.role = 'TRAINEE'
LEFT JOIN trainer_profiles trp ON u.id = trp.user_id AND u.role = 'TRAINER'
WHERE LOWER(u.email) = LOWER(BTRIM($1));


-- -----------------------------------------------------------------------------
-- 1.5 Fetch Complete Trainee Profile with Skill Summary & Enrollment Counts
-- Comprehensive profile retrieval joining trainee identity, bio, skills, and enrollments.
-- -----------------------------------------------------------------------------
-- READ
SELECT 
    u.id AS user_id,
    u.full_name,
    u.email,
    u.status,
    u.created_at AS member_since,
    tp.headline,
    tp.organization,
    tp.biography,
    tp.qualifications,
    tp.work_experience,
    tp.interests,
    tp.external_certifications,
    COUNT(DISTINCT ts.skill_id) AS total_skills_recorded,
    COUNT(DISTINCT e.id) AS total_enrolled_courses,
    COUNT(DISTINCT c.id) AS total_certificates_earned
FROM users u
INNER JOIN trainee_profiles tp ON u.id = tp.user_id
LEFT JOIN trainee_skills ts ON u.id = ts.trainee_id
LEFT JOIN enrollments e ON u.id = e.trainee_id
LEFT JOIN certificates c ON u.id = c.trainee_id AND c.revoked_at IS NULL
WHERE u.id = $1 AND u.role = 'TRAINEE'
GROUP BY 
    u.id, u.full_name, u.email, u.status, u.created_at,
    tp.headline, tp.organization, tp.biography, tp.qualifications,
    tp.work_experience, tp.interests, tp.external_certifications;


-- -----------------------------------------------------------------------------
-- 1.6 Fetch Complete Trainer Profile with Authored Courses & Teaching Statistics
-- Multi-table JOIN combining trainer bio, skills, published courses, and average feedback.
-- -----------------------------------------------------------------------------
-- READ
SELECT 
    u.id AS trainer_id,
    u.full_name,
    u.email,
    u.status,
    u.created_at AS member_since,
    trp.headline,
    trp.organization,
    trp.biography,
    trp.qualifications,
    trp.work_experience,
    trp.subject_expertise,
    trp.years_of_experience,
    COUNT(DISTINCT crs.id) AS total_courses_authored,
    COUNT(DISTINCT e.id) AS total_students_taught,
    COALESCE(ROUND(AVG(fb.rating)::numeric, 2), 0.00) AS overall_trainer_rating
FROM users u
INNER JOIN trainer_profiles trp ON u.id = trp.user_id
LEFT JOIN courses crs ON u.id = crs.trainer_id AND crs.status = 'PUBLISHED'
LEFT JOIN enrollments e ON crs.id = e.course_id
LEFT JOIN feedback fb ON crs.id = fb.course_id
WHERE u.id = $1 AND u.role = 'TRAINER'
GROUP BY 
    u.id, u.full_name, u.email, u.status, u.created_at,
    trp.headline, trp.organization, trp.biography, trp.qualifications,
    trp.work_experience, trp.subject_expertise, trp.years_of_experience;


-- -----------------------------------------------------------------------------
-- 1.7 Update User Password Hash
-- Security credential rotation for authenticated user.
-- -----------------------------------------------------------------------------
-- WRITE
UPDATE users
SET 
    password_hash = $2,
    updated_at = CURRENT_TIMESTAMP
WHERE id = $1;


-- -----------------------------------------------------------------------------
-- 1.8 Update Trainee Profile Details
-- Modifies professional summary and capacity development attributes.
-- -----------------------------------------------------------------------------
-- WRITE
UPDATE trainee_profiles
SET 
    headline = $2,
    organization = $3,
    biography = $4,
    qualifications = $5,
    work_experience = $6,
    interests = $7,
    external_certifications = $8,
    updated_at = CURRENT_TIMESTAMP
WHERE user_id = $1
RETURNING id, user_id, headline, organization, updated_at;


-- -----------------------------------------------------------------------------
-- 1.9 Update Trainer Profile Details
-- Modifies trainer subject matter expertise and background.
-- -----------------------------------------------------------------------------
-- WRITE
UPDATE trainer_profiles
SET 
    headline = $2,
    organization = $3,
    biography = $4,
    qualifications = $5,
    work_experience = $6,
    subject_expertise = $7,
    years_of_experience = $8,
    updated_at = CURRENT_TIMESTAMP
WHERE user_id = $1
RETURNING id, user_id, headline, subject_expertise, years_of_experience, updated_at;


-- -----------------------------------------------------------------------------
-- 1.10 Admin User Directory Search with Profile Join & Approver Audit
-- Powers GET /api/v1/admin/users with filtering by role, status, and approval history.
-- -----------------------------------------------------------------------------
-- READ
SELECT 
    u.id,
    u.full_name,
    u.email,
    u.role,
    u.status,
    u.created_at,
    u.approved_at,
    approver.full_name AS approved_by_admin,
    COALESCE(tp.headline, trp.headline, 'N/A') AS headline,
    COALESCE(tp.organization, trp.organization, 'N/A') AS organization
FROM users u
LEFT JOIN users approver ON u.approved_by = approver.id
LEFT JOIN trainee_profiles tp ON u.id = tp.user_id AND u.role = 'TRAINEE'
LEFT JOIN trainer_profiles trp ON u.id = trp.user_id AND u.role = 'TRAINER'
WHERE 
    ($1::VARCHAR IS NULL OR u.role = $1)
    AND ($2::VARCHAR IS NULL OR u.status = $2)
    AND (
        $3::VARCHAR IS NULL 
        OR u.full_name ILIKE '%' || $3 || '%' 
        OR u.email ILIKE '%' || $3 || '%'
    )
ORDER BY u.created_at DESC
LIMIT $4 OFFSET $5;


-- -----------------------------------------------------------------------------
-- 1.11 Admin Pending User Approval Queue
-- Retrieves accounts awaiting administrative activation.
-- -----------------------------------------------------------------------------
-- READ
SELECT 
    u.id,
    u.full_name,
    u.email,
    u.role,
    u.created_at,
    COALESCE(tp.organization, trp.organization, 'N/A') AS organization,
    COALESCE(trp.subject_expertise, tp.interests, 'N/A') AS domain_focus
FROM users u
LEFT JOIN trainee_profiles tp ON u.id = tp.user_id AND u.role = 'TRAINEE'
LEFT JOIN trainer_profiles trp ON u.id = trp.user_id AND u.role = 'TRAINER'
WHERE u.status = 'PENDING'
ORDER BY u.created_at ASC;


-- -----------------------------------------------------------------------------
-- 1.12 Approve User Account
-- Transitions user status from PENDING to ACTIVE and logs the approving Admin ID.
-- -----------------------------------------------------------------------------
-- WRITE
UPDATE users
SET 
    status = 'ACTIVE',
    approved_by = $1,
    approved_at = CURRENT_TIMESTAMP,
    updated_at = CURRENT_TIMESTAMP
WHERE id = $2 AND status = 'PENDING'
RETURNING id, full_name, email, role, status, approved_by, approved_at;


-- -----------------------------------------------------------------------------
-- 1.13 Reject User Account
-- Marks a registration request as REJECTED with administrative audit logging.
-- -----------------------------------------------------------------------------
-- WRITE
UPDATE users
SET 
    status = 'REJECTED',
    approved_by = $1,
    approved_at = CURRENT_TIMESTAMP,
    updated_at = CURRENT_TIMESTAMP
WHERE id = $2 AND status = 'PENDING'
RETURNING id, full_name, email, role, status, approved_by, approved_at;


-- -----------------------------------------------------------------------------
-- 1.14 Suspend / Deactivate User Account
-- Administrative security override revoking access privileges.
-- -----------------------------------------------------------------------------
-- WRITE
UPDATE users
SET 
    status = 'SUSPENDED',
    updated_at = CURRENT_TIMESTAMP
WHERE id = $1 AND role <> 'ADMIN'
RETURNING id, full_name, email, role, status, updated_at;



-- =============================================================================
-- MODULE 2: SKILL CATALOGUE & COMPETENCY MAPPING (MEMBER 4)
-- Canonical Tables: skills, trainee_skills, trainer_skills
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 2.1 Skill Catalogue Discovery with Adoption Metrics
-- Lists standard skills with counts of active trainees and trainers having each skill.
-- -----------------------------------------------------------------------------
-- READ
SELECT 
    s.id AS skill_id,
    s.name AS skill_name,
    s.category AS skill_category,
    s.created_at,
    COUNT(DISTINCT ts.trainee_id) AS total_trainees_acquired,
    ROUND(COALESCE(AVG(ts.proficiency), 0), 2) AS avg_trainee_proficiency,
    COUNT(DISTINCT trs.trainer_id) AS total_qualified_trainers
FROM skills s
LEFT JOIN trainee_skills ts ON s.id = ts.skill_id
LEFT JOIN trainer_skills trs ON s.id = trs.skill_id
WHERE ($1::VARCHAR IS NULL OR s.category = $1)
GROUP BY s.id, s.name, s.category, s.created_at
ORDER BY s.category ASC, s.name ASC;


-- -----------------------------------------------------------------------------
-- 2.2 Add New Skill to Master Catalogue
-- Registers a new canonical competence with trimmed lowercase uniqueness check.
-- -----------------------------------------------------------------------------
-- WRITE
INSERT INTO skills (
    name,
    category
) VALUES (
    BTRIM($1),
    BTRIM($2)
)
RETURNING id, name, category, created_at;


-- -----------------------------------------------------------------------------
-- 2.3 Update Skill Definition
-- Modifies existing skill master name or category.
-- -----------------------------------------------------------------------------
-- WRITE
UPDATE skills
SET 
    name = BTRIM($2),
    category = BTRIM($3)
WHERE id = $1
RETURNING id, name, category;


-- -----------------------------------------------------------------------------
-- 2.4 Delete Unused Skill
-- Deletes a skill only if no trainee or trainer mapping references it.
-- -----------------------------------------------------------------------------
-- WRITE
DELETE FROM skills
WHERE id = $1
  AND NOT EXISTS (SELECT 1 FROM trainee_skills WHERE skill_id = $1)
  AND NOT EXISTS (SELECT 1 FROM trainer_skills WHERE skill_id = $1)
RETURNING id, name;


-- -----------------------------------------------------------------------------
-- 2.5 Trainee Skill Upsert (Add or Update Proficiency)
-- Associates a skill with a trainee or updates existing proficiency rating (1..4).
-- -----------------------------------------------------------------------------
-- WRITE
INSERT INTO trainee_skills (
    trainee_id,
    skill_id,
    proficiency
) VALUES (
    $1, -- trainee_id
    $2, -- skill_id
    $3  -- proficiency: 1=Novice, 2=Intermediate, 3=Advanced, 4=Expert
)
ON CONFLICT (trainee_id, skill_id) 
DO UPDATE SET 
    proficiency = EXCLUDED.proficiency
RETURNING id, trainee_id, skill_id, proficiency;


-- -----------------------------------------------------------------------------
-- 2.6 Remove Skill from Trainee Profile
-- Unlinks a skill from a trainee portfolio.
-- -----------------------------------------------------------------------------
-- WRITE
DELETE FROM trainee_skills
WHERE trainee_id = $1 AND skill_id = $2
RETURNING id, trainee_id, skill_id;


-- -----------------------------------------------------------------------------
-- 2.7 Fetch Trainee Skill Portfolio with Detailed Metadata
-- Retrieves all skills mapped to a trainee with category information.
-- -----------------------------------------------------------------------------
-- READ
SELECT 
    ts.id AS trainee_skill_id,
    s.id AS skill_id,
    s.name AS skill_name,
    s.category AS skill_category,
    ts.proficiency,
    CASE ts.proficiency
        WHEN 1 THEN 'Novice'
        WHEN 2 THEN 'Intermediate'
        WHEN 3 THEN 'Advanced'
        WHEN 4 THEN 'Expert'
    END AS proficiency_label
FROM trainee_skills ts
INNER JOIN skills s ON ts.skill_id = s.id
WHERE ts.trainee_id = $1
ORDER BY s.category ASC, ts.proficiency DESC, s.name ASC;


-- -----------------------------------------------------------------------------
-- 2.8 Trainer Skill Upsert (Add or Update Expertise)
-- Maps a skill to a trainer with verified proficiency and years of experience.
-- -----------------------------------------------------------------------------
-- WRITE
INSERT INTO trainer_skills (
    trainer_id,
    skill_id,
    proficiency,
    years_of_experience
) VALUES (
    $1, -- trainer_id
    $2, -- skill_id
    $3, -- proficiency: 1..4
    $4  -- years_of_experience: NUMERIC(4,1)
)
ON CONFLICT (trainer_id, skill_id)
DO UPDATE SET 
    proficiency = EXCLUDED.proficiency,
    years_of_experience = EXCLUDED.years_of_experience
RETURNING id, trainer_id, skill_id, proficiency, years_of_experience;


-- -----------------------------------------------------------------------------
-- 2.9 Remove Skill from Trainer Profile
-- Unlinks a competence from a trainer's portfolio.
-- -----------------------------------------------------------------------------
-- WRITE
DELETE FROM trainer_skills
WHERE trainer_id = $1 AND skill_id = $2
RETURNING id, trainer_id, skill_id;


-- -----------------------------------------------------------------------------
-- 2.10 Fetch Trainer Skill Portfolio with Detailed Metadata
-- Retrieves all verified competences belonging to a trainer.
-- -----------------------------------------------------------------------------
-- READ
SELECT 
    trs.id AS trainer_skill_id,
    s.id AS skill_id,
    s.name AS skill_name,
    s.category AS skill_category,
    trs.proficiency,
    trs.years_of_experience,
    CASE trs.proficiency
        WHEN 1 THEN 'Novice'
        WHEN 2 THEN 'Intermediate'
        WHEN 3 THEN 'Advanced'
        WHEN 4 THEN 'Expert'
    END AS proficiency_label
FROM trainer_skills trs
INNER JOIN skills s ON trs.skill_id = s.id
WHERE trs.trainer_id = $1
ORDER BY trs.proficiency DESC, trs.years_of_experience DESC, s.name ASC;


-- -----------------------------------------------------------------------------
-- 2.11 Deterministic Trainer Recommendation Engine (PRD Section 6.8)
-- Ranks qualified trainers for a required skill matching:
-- 1. Exact skill_id match -> 2. Highest proficiency DESC -> 3. Experience DESC.
-- Uses composite index: idx_trainer_skills_recommendation.
-- -----------------------------------------------------------------------------
-- READ
SELECT 
    u.id AS trainer_id,
    u.full_name AS trainer_name,
    u.email AS trainer_email,
    trp.headline AS trainer_headline,
    trp.organization,
    s.id AS skill_id,
    s.name AS skill_name,
    trs.proficiency,
    trs.years_of_experience,
    COUNT(DISTINCT c.id) AS active_courses_count,
    COALESCE(ROUND(AVG(fb.rating)::numeric, 2), 0.00) AS avg_course_rating
FROM trainer_skills trs
INNER JOIN skills s ON trs.skill_id = s.id
INNER JOIN users u ON trs.trainer_id = u.id AND u.status = 'ACTIVE'
INNER JOIN trainer_profiles trp ON u.id = trp.user_id
LEFT JOIN courses c ON u.id = c.trainer_id AND c.status = 'PUBLISHED'
LEFT JOIN feedback fb ON c.id = fb.course_id
WHERE s.id = $1
GROUP BY 
    u.id, u.full_name, u.email, trp.headline, trp.organization,
    s.id, s.name, trs.proficiency, trs.years_of_experience
ORDER BY 
    trs.proficiency DESC,
    trs.years_of_experience DESC,
    avg_course_rating DESC,
    u.full_name ASC
LIMIT $2;



-- =============================================================================
-- MODULE 3: COURSES, LESSONS & LEARNING RESOURCES (MEMBER 2)
-- Canonical Tables: courses, lessons, learning_resources
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 3.1 Create Draft Course
-- Authors a new course draft assigned to an authenticated trainer.
-- -----------------------------------------------------------------------------
-- WRITE
INSERT INTO courses (
    trainer_id,
    title,
    summary,
    description,
    subject,
    level,
    thumbnail_url,
    status
) VALUES (
    $1,        -- trainer_id: BIGINT
    $2,        -- title: VARCHAR(200)
    $3,        -- summary: VARCHAR(500)
    $4,        -- description: TEXT
    $5,        -- subject: VARCHAR(120)
    $6,        -- level: 'BEGINNER' | 'INTERMEDIATE' | 'ADVANCED'
    $7,        -- thumbnail_url: VARCHAR(2048)
    'DRAFT'    -- status default
)
RETURNING id, trainer_id, title, status, created_at;


-- -----------------------------------------------------------------------------
-- 3.2 Update Course Metadata
-- Modifies syllabus details and classification for a non-archived course.
-- -----------------------------------------------------------------------------
-- WRITE
UPDATE courses
SET 
    title = $3,
    summary = $4,
    description = $5,
    subject = $6,
    level = $7,
    thumbnail_url = $8,
    updated_at = CURRENT_TIMESTAMP
WHERE id = $1 AND trainer_id = $2 AND status <> 'ARCHIVED'
RETURNING id, title, summary, subject, level, updated_at;


-- -----------------------------------------------------------------------------
-- 3.3 Validate and Publish Course
-- Validates that the course contains at least one lesson before transitioning
-- status to 'PUBLISHED' and setting published_at timestamp.
-- -----------------------------------------------------------------------------
-- WRITE
UPDATE courses
SET 
    status = 'PUBLISHED',
    published_at = CURRENT_TIMESTAMP,
    updated_at = CURRENT_TIMESTAMP
WHERE id = $1 
  AND trainer_id = $2 
  AND status = 'DRAFT'
  AND description IS NOT NULL AND LENGTH(BTRIM(description)) > 0
  AND subject IS NOT NULL AND LENGTH(BTRIM(subject)) > 0
  AND level IS NOT NULL
  AND EXISTS (SELECT 1 FROM lessons WHERE course_id = $1)
RETURNING id, title, status, published_at;


-- -----------------------------------------------------------------------------
-- 3.4 Archive Course
-- Retires a course from public catalog without deleting historical records.
-- -----------------------------------------------------------------------------
-- WRITE
UPDATE courses
SET 
    status = 'ARCHIVED',
    archived_at = CURRENT_TIMESTAMP,
    updated_at = CURRENT_TIMESTAMP
WHERE id = $1 AND trainer_id = $2 AND status = 'PUBLISHED'
RETURNING id, title, status, archived_at;


-- -----------------------------------------------------------------------------
-- 3.5 Trainer Authored Courses Dashboard
-- Aggregates course performance metrics for the authoring trainer.
-- -----------------------------------------------------------------------------
-- READ
SELECT 
    c.id AS course_id,
    c.title,
    c.subject,
    c.level,
    c.status,
    c.created_at,
    c.published_at,
    COUNT(DISTINCT l.id) AS total_lessons,
    COUNT(DISTINCT lr.id) AS total_resources,
    COUNT(DISTINCT a.id) AS total_assessments,
    COUNT(DISTINCT e.id) AS total_enrollments,
    COUNT(DISTINCT CASE WHEN e.status = 'COMPLETED' THEN e.id END) AS completed_enrollments,
    COALESCE(ROUND(AVG(fb.rating)::numeric, 2), 0.00) AS avg_rating
FROM courses c
LEFT JOIN lessons l ON c.id = l.course_id
LEFT JOIN learning_resources lr ON c.id = lr.course_id
LEFT JOIN assessments a ON c.id = a.course_id
LEFT JOIN enrollments e ON c.id = e.course_id
LEFT JOIN feedback fb ON c.id = fb.course_id
WHERE c.trainer_id = $1
GROUP BY c.id, c.title, c.subject, c.level, c.status, c.created_at, c.published_at
ORDER BY c.created_at DESC;


-- -----------------------------------------------------------------------------
-- 3.6 Public Course Catalogue Search & Discovery
-- Searches published courses with multi-faceted filtering, joining trainer profile,
-- aggregate rating, and total curriculum volume.
-- -----------------------------------------------------------------------------
-- READ
SELECT 
    c.id AS course_id,
    c.title,
    c.summary,
    c.subject,
    c.level,
    c.thumbnail_url,
    c.published_at,
    u.id AS trainer_id,
    u.full_name AS trainer_name,
    trp.headline AS trainer_headline,
    trp.organization AS trainer_organization,
    COUNT(DISTINCT l.id) AS total_lessons,
    COALESCE(SUM(l.estimated_duration_minutes), 0) AS total_duration_minutes,
    COUNT(DISTINCT e.id) AS active_learners_count,
    COALESCE(ROUND(AVG(fb.rating)::numeric, 2), 0.00) AS average_rating,
    COUNT(DISTINCT fb.id) AS total_reviews_count
FROM courses c
INNER JOIN users u ON c.trainer_id = u.id
INNER JOIN trainer_profiles trp ON u.id = trp.user_id
LEFT JOIN lessons l ON c.id = l.course_id
LEFT JOIN enrollments e ON c.id = e.course_id AND e.status = 'ACTIVE'
LEFT JOIN feedback fb ON c.id = fb.course_id
WHERE 
    c.status = 'PUBLISHED'
    AND ($1::VARCHAR IS NULL OR c.subject = $1)
    AND ($2::VARCHAR IS NULL OR c.level = $2)
    AND (
        $3::VARCHAR IS NULL 
        OR c.title ILIKE '%' || $3 || '%' 
        OR c.summary ILIKE '%' || $3 || '%'
        OR c.subject ILIKE '%' || $3 || '%'
    )
GROUP BY 
    c.id, c.title, c.summary, c.subject, c.level, c.thumbnail_url, c.published_at,
    u.id, u.full_name, trp.headline, trp.organization
ORDER BY 
    c.published_at DESC
LIMIT $4 OFFSET $5;


-- -----------------------------------------------------------------------------
-- 3.7 Detailed Single Course Curriculum & Syllabus Overview
-- Fetches full course metadata joined with trainer profile, lesson syllabus, and stats.
-- -----------------------------------------------------------------------------
-- READ
SELECT 
    c.id AS course_id,
    c.title,
    c.summary,
    c.description,
    c.subject,
    c.level,
    c.thumbnail_url,
    c.status,
    c.published_at,
    u.id AS trainer_id,
    u.full_name AS trainer_name,
    u.email AS trainer_email,
    trp.headline AS trainer_headline,
    trp.organization AS trainer_organization,
    trp.biography AS trainer_biography,
    trp.years_of_experience AS trainer_experience_years,
    COUNT(DISTINCT l.id) AS lesson_count,
    COALESCE(SUM(l.estimated_duration_minutes), 0) AS total_estimated_minutes,
    COUNT(DISTINCT a.id) AS assessment_count,
    COALESCE(ROUND(AVG(fb.rating)::numeric, 2), 0.00) AS avg_rating,
    COUNT(DISTINCT fb.id) AS total_feedback_count
FROM courses c
INNER JOIN users u ON c.trainer_id = u.id
INNER JOIN trainer_profiles trp ON u.id = trp.user_id
LEFT JOIN lessons l ON c.id = l.course_id
LEFT JOIN assessments a ON c.id = a.course_id AND a.status = 'PUBLISHED'
LEFT JOIN feedback fb ON c.id = fb.course_id
WHERE c.id = $1
GROUP BY 
    c.id, c.title, c.summary, c.description, c.subject, c.level, c.thumbnail_url,
    c.status, c.published_at, u.id, u.full_name, u.email,
    trp.headline, trp.organization, trp.biography, trp.years_of_experience;


-- -----------------------------------------------------------------------------
-- 3.8 Add Lesson to Course
-- Appends a structured lesson in a course with unique order constraint.
-- -----------------------------------------------------------------------------
-- WRITE
INSERT INTO lessons (
    course_id,
    title,
    content,
    lesson_order,
    estimated_duration_minutes
) VALUES (
    $1, -- course_id
    $2, -- title
    $3, -- content
    $4, -- lesson_order
    $5  -- estimated_duration_minutes
)
RETURNING id, course_id, title, lesson_order, estimated_duration_minutes, created_at;


-- -----------------------------------------------------------------------------
-- 3.9 Update Lesson Details
-- Modifies lesson content, title, duration, and sequence.
-- -----------------------------------------------------------------------------
-- WRITE
UPDATE lessons
SET 
    title = $3,
    content = $4,
    lesson_order = $5,
    estimated_duration_minutes = $6,
    updated_at = CURRENT_TIMESTAMP
WHERE id = $1 AND course_id = $2
RETURNING id, course_id, title, lesson_order, updated_at;


-- -----------------------------------------------------------------------------
-- 3.10 Delete Lesson
-- Deletes a lesson if no completed progress record depends on it.
-- -----------------------------------------------------------------------------
-- WRITE
DELETE FROM lessons
WHERE id = $1 AND course_id = $2
  AND NOT EXISTS (SELECT 1 FROM lesson_progress WHERE lesson_id = $1)
RETURNING id, course_id, title;


-- -----------------------------------------------------------------------------
-- 3.11 Fetch Ordered Lessons for Course with Resource Counts
-- Lists all lessons in sequential order joined with resource quantities.
-- -----------------------------------------------------------------------------
-- READ
SELECT 
    l.id AS lesson_id,
    l.course_id,
    l.title,
    l.lesson_order,
    l.estimated_duration_minutes,
    COUNT(DISTINCT lr.id) AS attached_resources_count
FROM lessons l
INNER JOIN courses c ON l.course_id = c.id
LEFT JOIN learning_resources lr ON l.id = lr.lesson_id
WHERE l.course_id = $1
GROUP BY l.id, l.course_id, l.title, l.lesson_order, l.estimated_duration_minutes
ORDER BY l.lesson_order ASC;


-- -----------------------------------------------------------------------------
-- 3.12 Fetch Single Lesson Content with Attached Learning Resources
-- Retrieves full lesson body and all associated multimedia/document attachments.
-- -----------------------------------------------------------------------------
-- READ
SELECT 
    l.id AS lesson_id,
    l.course_id,
    c.title AS course_title,
    l.title AS lesson_title,
    l.content AS lesson_content,
    l.lesson_order,
    l.estimated_duration_minutes,
    lr.id AS resource_id,
    lr.title AS resource_title,
    lr.resource_type,
    lr.storage_ref,
    lr.external_url,
    lr.original_filename,
    lr.file_size_bytes
FROM lessons l
INNER JOIN courses c ON l.course_id = c.id
LEFT JOIN learning_resources lr ON l.id = lr.lesson_id
WHERE l.id = $1 AND l.course_id = $2
ORDER BY lr.resource_order ASC;


-- -----------------------------------------------------------------------------
-- 3.13 Attach Learning Resource to Course / Lesson
-- Inserts metadata and reference for an educational resource.
-- -----------------------------------------------------------------------------
-- WRITE
INSERT INTO learning_resources (
    course_id,
    lesson_id,
    uploaded_by,
    title,
    description,
    resource_type,
    storage_ref,
    external_url,
    original_filename,
    mime_type,
    file_size_bytes,
    resource_order
) VALUES (
    $1,  -- course_id: BIGINT
    $2,  -- lesson_id: BIGINT NULL
    $3,  -- uploaded_by: BIGINT
    $4,  -- title: VARCHAR(200)
    $5,  -- description: TEXT NULL
    $6,  -- resource_type: 'VIDEO' | 'PRESENTATION' | 'DOCUMENT' | 'LINK' | 'OTHER'
    $7,  -- storage_ref: VARCHAR(2048) NULL
    $8,  -- external_url: VARCHAR(2048) NULL
    $9,  -- original_filename: VARCHAR(255) NULL
    $10, -- mime_type: VARCHAR(120) NULL
    $11, -- file_size_bytes: BIGINT NULL
    $12  -- resource_order: INTEGER
)
RETURNING id, course_id, lesson_id, title, resource_type, created_at;


-- -----------------------------------------------------------------------------
-- 3.14 Delete Learning Resource
-- Removes an attached resource reference.
-- -----------------------------------------------------------------------------
-- WRITE
DELETE FROM learning_resources
WHERE id = $1 AND course_id = $2
RETURNING id, course_id, title;


-- -----------------------------------------------------------------------------
-- 3.15 List All Course Learning Resources
-- Retrieves all resources mapped across a course joined with uploader details.
-- -----------------------------------------------------------------------------
-- READ
SELECT 
    lr.id AS resource_id,
    lr.course_id,
    lr.lesson_id,
    l.title AS lesson_title,
    lr.title AS resource_title,
    lr.resource_type,
    lr.storage_ref,
    lr.external_url,
    lr.original_filename,
    lr.mime_type,
    lr.file_size_bytes,
    u.full_name AS uploader_name,
    lr.created_at
FROM learning_resources lr
INNER JOIN courses c ON lr.course_id = c.id
LEFT JOIN lessons l ON lr.lesson_id = l.id
INNER JOIN users u ON lr.uploaded_by = u.id
WHERE lr.course_id = $1
ORDER BY COALESCE(l.lesson_order, 0) ASC, lr.resource_order ASC;



-- =============================================================================
-- MODULE 4: ENROLLMENTS & DYNAMIC PROGRESS TRACKING (MEMBERS 2 & 3)
-- Canonical Tables: enrollments, lesson_progress, lessons, courses
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 4.1 Enroll Trainee in Published Course
-- Creates an active enrollment record for a trainee in a verified published course.
-- -----------------------------------------------------------------------------
-- WRITE
INSERT INTO enrollments (
    trainee_id,
    course_id,
    status
)
SELECT 
    $1, -- trainee_id
    c.id,
    'ACTIVE'
FROM courses c
WHERE c.id = $2 AND c.status = 'PUBLISHED'
ON CONFLICT (trainee_id, course_id) DO NOTHING
RETURNING id, trainee_id, course_id, status, enrolled_at;


-- -----------------------------------------------------------------------------
-- 4.2 Cancel Active Enrollment
-- Cancels an enrollment and records cancellation timestamp.
-- -----------------------------------------------------------------------------
-- WRITE
UPDATE enrollments
SET 
    status = 'CANCELLED',
    cancelled_at = CURRENT_TIMESTAMP,
    updated_at = CURRENT_TIMESTAMP
WHERE id = $1 AND trainee_id = $2 AND status = 'ACTIVE'
RETURNING id, trainee_id, course_id, status, cancelled_at;


-- -----------------------------------------------------------------------------
-- 4.3 Trainee Enrolled Courses Dashboard with Dynamic Progress Calculation
-- Computes real-time progress percentage dynamically from lesson_progress and lessons
-- (PRD Section 6.6: never stored as a client-supplied percentage).
-- -----------------------------------------------------------------------------
-- READ
SELECT 
    e.id AS enrollment_id,
    e.course_id,
    c.title AS course_title,
    c.subject,
    c.level,
    c.thumbnail_url,
    trainer.full_name AS trainer_name,
    e.status AS enrollment_status,
    e.enrolled_at,
    e.completed_at,
    COUNT(DISTINCT l.id) AS total_lessons,
    COUNT(DISTINCT lp.lesson_id) AS completed_lessons,
    CASE 
        WHEN COUNT(DISTINCT l.id) = 0 THEN 0.00
        ELSE ROUND((COUNT(DISTINCT lp.lesson_id)::numeric / COUNT(DISTINCT l.id)::numeric) * 100.0, 2)
    END AS progress_percentage,
    cert.id AS certificate_id,
    cert.certificate_code
FROM enrollments e
INNER JOIN courses c ON e.course_id = c.id
INNER JOIN users trainer ON c.trainer_id = trainer.id
LEFT JOIN lessons l ON c.id = l.course_id
LEFT JOIN lesson_progress lp ON e.id = lp.enrollment_id AND l.id = lp.lesson_id
LEFT JOIN certificates cert ON e.trainee_id = cert.trainee_id AND e.course_id = cert.course_id AND cert.revoked_at IS NULL
WHERE e.trainee_id = $1
GROUP BY 
    e.id, e.course_id, c.title, c.subject, c.level, c.thumbnail_url,
    trainer.full_name, e.status, e.enrolled_at, e.completed_at,
    cert.id, cert.certificate_code
ORDER BY e.enrolled_at DESC;


-- -----------------------------------------------------------------------------
-- 4.4 Course Enrollment Roster for Trainer / Admin Inspection
-- Lists all enrolled trainees with their individual dynamic progress and profile bio.
-- -----------------------------------------------------------------------------
-- READ
SELECT 
    e.id AS enrollment_id,
    u.id AS trainee_id,
    u.full_name AS trainee_name,
    u.email AS trainee_email,
    tp.organization,
    e.status AS enrollment_status,
    e.enrolled_at,
    e.completed_at,
    COUNT(DISTINCT lp.lesson_id) AS completed_lessons,
    (SELECT COUNT(*) FROM lessons WHERE course_id = e.course_id) AS total_course_lessons,
    CASE 
        WHEN (SELECT COUNT(*) FROM lessons WHERE course_id = e.course_id) = 0 THEN 0.00
        ELSE ROUND(
            (COUNT(DISTINCT lp.lesson_id)::numeric / 
             (SELECT COUNT(*) FROM lessons WHERE course_id = e.course_id)::numeric) * 100.0, 2
        )
    END AS progress_percentage
FROM enrollments e
INNER JOIN users u ON e.trainee_id = u.id
INNER JOIN trainee_profiles tp ON u.id = tp.user_id
LEFT JOIN lesson_progress lp ON e.id = lp.enrollment_id
WHERE e.course_id = $1
GROUP BY 
    e.id, u.id, u.full_name, u.email, tp.organization,
    e.status, e.enrolled_at, e.completed_at, e.course_id
ORDER BY e.enrolled_at DESC;


-- -----------------------------------------------------------------------------
-- 4.5 Mark Lesson as Completed (Lesson Progress Ledger)
-- Records completion of a lesson under a verified active enrollment.
-- -----------------------------------------------------------------------------
-- WRITE
INSERT INTO lesson_progress (
    enrollment_id,
    course_id,
    lesson_id
)
SELECT 
    e.id,
    e.course_id,
    l.id
FROM enrollments e
INNER JOIN lessons l ON e.course_id = l.course_id
WHERE e.id = $1 
  AND e.trainee_id = $2 
  AND l.id = $3
  AND e.status = 'ACTIVE'
ON CONFLICT (enrollment_id, lesson_id) DO NOTHING
RETURNING id, enrollment_id, course_id, lesson_id, completed_at;


-- -----------------------------------------------------------------------------
-- 4.6 Fetch Trainee Lesson Completion Checklist for Course
-- Checks off completed lessons against full syllabus with completion timestamps.
-- -----------------------------------------------------------------------------
-- READ
SELECT 
    l.id AS lesson_id,
    l.course_id,
    l.title AS lesson_title,
    l.lesson_order,
    l.estimated_duration_minutes,
    CASE WHEN lp.id IS NOT NULL THEN TRUE ELSE FALSE END AS is_completed,
    lp.completed_at
FROM lessons l
INNER JOIN enrollments e ON l.course_id = e.course_id AND e.id = $1 AND e.trainee_id = $2
LEFT JOIN lesson_progress lp ON e.id = lp.enrollment_id AND l.id = lp.lesson_id
ORDER BY l.lesson_order ASC;


-- -----------------------------------------------------------------------------
-- 4.7 Complete Course Enrollment
-- Transitions active enrollment to 'COMPLETED' if 100% of course lessons are finished.
-- -----------------------------------------------------------------------------
-- WRITE
UPDATE enrollments e
SET 
    status = 'COMPLETED',
    completed_at = CURRENT_TIMESTAMP,
    updated_at = CURRENT_TIMESTAMP
WHERE e.id = $1 
  AND e.trainee_id = $2 
  AND e.status = 'ACTIVE'
  AND (
      -- Verification: total completed lessons equals total course lessons (minimum 1 lesson)
      SELECT COUNT(DISTINCT lp.lesson_id)
      FROM lesson_progress lp
      WHERE lp.enrollment_id = e.id
  ) = (
      SELECT COUNT(DISTINCT l.id)
      FROM lessons l
      WHERE l.course_id = e.course_id
  )
  AND EXISTS (SELECT 1 FROM lessons WHERE course_id = e.course_id)
RETURNING id, trainee_id, course_id, status, completed_at;



-- =============================================================================
-- MODULE 5: ASSESSMENTS, QUESTIONS & ATTEMPTS (MEMBER 3)
-- Canonical Tables: assessments, questions, assessment_attempts, attempt_answers
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 5.1 Create Assessment for Course
-- Authors a formal evaluation module tied to a course.
-- -----------------------------------------------------------------------------
-- WRITE
INSERT INTO assessments (
    course_id,
    title,
    instructions,
    deadline_at,
    duration_minutes,
    max_attempts,
    pass_percentage,
    is_required,
    status
) VALUES (
    $1,        -- course_id: BIGINT
    $2,        -- title: VARCHAR(200)
    $3,        -- instructions: TEXT
    $4,        -- deadline_at: TIMESTAMPTZ NULL
    $5,        -- duration_minutes: INTEGER NULL
    $6,        -- max_attempts: INTEGER DEFAULT 1
    $7,        -- pass_percentage: NUMERIC(5,2) DEFAULT 60.00
    $8,        -- is_required: BOOLEAN DEFAULT TRUE
    'DRAFT'    -- status
)
RETURNING id, course_id, title, pass_percentage, status, created_at;


-- -----------------------------------------------------------------------------
-- 5.2 Update Assessment Configuration
-- Modifies assessment timing, pass criteria, and instructions.
-- -----------------------------------------------------------------------------
-- WRITE
UPDATE assessments
SET 
    title = $2,
    instructions = $3,
    deadline_at = $4,
    duration_minutes = $5,
    max_attempts = $6,
    pass_percentage = $7,
    is_required = $8,
    updated_at = CURRENT_TIMESTAMP
WHERE id = $1 AND status = 'DRAFT'
RETURNING id, title, pass_percentage, duration_minutes, max_attempts;


-- -----------------------------------------------------------------------------
-- 5.3 Publish Assessment
-- Activates an assessment with at least one question into 'PUBLISHED' state.
-- -----------------------------------------------------------------------------
-- WRITE
UPDATE assessments
SET 
    status = 'PUBLISHED',
    published_at = CURRENT_TIMESTAMP,
    updated_at = CURRENT_TIMESTAMP
WHERE id = $1 
  AND status = 'DRAFT'
  AND EXISTS (SELECT 1 FROM questions WHERE assessment_id = $1)
RETURNING id, title, status, published_at;


-- -----------------------------------------------------------------------------
-- 5.4 Close Assessment
-- Closes an assessment, preventing further trainee attempts.
-- -----------------------------------------------------------------------------
-- WRITE
UPDATE assessments
SET 
    status = 'CLOSED',
    updated_at = CURRENT_TIMESTAMP
WHERE id = $1 AND status = 'PUBLISHED'
RETURNING id, title, status;


-- -----------------------------------------------------------------------------
-- 5.5 List Assessments for Course with Question Counts & Points
-- Retrieves all assessments configured for a course syllabus.
-- -----------------------------------------------------------------------------
-- READ
SELECT 
    a.id AS assessment_id,
    a.course_id,
    c.title AS course_title,
    a.title AS assessment_title,
    a.instructions,
    a.duration_minutes,
    a.deadline_at,
    a.max_attempts,
    a.pass_percentage,
    a.is_required,
    a.status,
    COUNT(q.id) AS total_questions,
    COALESCE(SUM(q.points), 0) AS total_possible_points
FROM assessments a
INNER JOIN courses c ON a.course_id = c.id
LEFT JOIN questions q ON a.id = q.assessment_id
WHERE a.course_id = $1
GROUP BY 
    a.id, a.course_id, c.title, a.title, a.instructions,
    a.duration_minutes, a.deadline_at, a.max_attempts,
    a.pass_percentage, a.is_required, a.status
ORDER BY a.created_at ASC;


-- -----------------------------------------------------------------------------
-- 5.6 Add MCQ Question to Assessment Bank
-- Adds a four-option question with points and explanation to the assessment.
-- -----------------------------------------------------------------------------
-- WRITE
INSERT INTO questions (
    assessment_id,
    question_order,
    question_text,
    option_a,
    option_b,
    option_c,
    option_d,
    correct_option,
    explanation,
    points
) VALUES (
    $1,  -- assessment_id: BIGINT
    $2,  -- question_order: INTEGER
    $3,  -- question_text: TEXT
    $4,  -- option_a: TEXT
    $5,  -- option_b: TEXT
    $6,  -- option_c: TEXT
    $7,  -- option_d: TEXT
    $8,  -- correct_option: CHAR(1) ('A', 'B', 'C', 'D')
    $9,  -- explanation: TEXT NULL
    $10  -- points: INTEGER DEFAULT 1
)
RETURNING id, assessment_id, question_order, points;


-- -----------------------------------------------------------------------------
-- 5.7 Update Question Details
-- Updates question text, options, answer key, or scoring weight.
-- -----------------------------------------------------------------------------
-- WRITE
UPDATE questions
SET 
    question_order = $3,
    question_text = $4,
    option_a = $5,
    option_b = $6,
    option_c = $7,
    option_d = $8,
    correct_option = $9,
    explanation = $10,
    points = $11,
    updated_at = CURRENT_TIMESTAMP
WHERE id = $1 AND assessment_id = $2
RETURNING id, assessment_id, question_order, points;


-- -----------------------------------------------------------------------------
-- 5.8 Delete Question from Assessment
-- Removes an item from the question bank if not locked by attempts.
-- -----------------------------------------------------------------------------
-- WRITE
DELETE FROM questions
WHERE id = $1 AND assessment_id = $2
  AND NOT EXISTS (SELECT 1 FROM attempt_answers WHERE question_id = $1)
RETURNING id, assessment_id;


-- -----------------------------------------------------------------------------
-- 5.9 Fetch Assessment Questions for Trainer / Admin Inspection
-- Retrieves all questions including correct answers and explanations.
-- -----------------------------------------------------------------------------
-- READ
SELECT 
    q.id AS question_id,
    q.assessment_id,
    a.title AS assessment_title,
    q.question_order,
    q.question_text,
    q.option_a,
    q.option_b,
    q.option_c,
    q.option_d,
    q.correct_option,
    q.explanation,
    q.points
FROM questions q
INNER JOIN assessments a ON q.assessment_id = a.id
WHERE q.assessment_id = $1
ORDER BY q.question_order ASC;


-- -----------------------------------------------------------------------------
-- 5.10 Check Assessment Attempt Eligibility for Trainee
-- Verifies enrollment, remaining attempts, and lack of active IN_PROGRESS attempts.
-- -----------------------------------------------------------------------------
-- READ
SELECT 
    a.id AS assessment_id,
    a.course_id,
    a.title,
    a.status,
    a.max_attempts,
    a.pass_percentage,
    COUNT(DISTINCT att.id) AS attempts_taken,
    MAX(att.score_percentage) AS best_score_percentage,
    BOOL_OR(COALESCE(att.is_passed, FALSE)) AS has_passed,
    COUNT(DISTINCT CASE WHEN att.status = 'IN_PROGRESS' THEN att.id END) AS active_in_progress_count,
    CASE 
        WHEN a.status <> 'PUBLISHED' THEN FALSE
        WHEN a.deadline_at IS NOT NULL AND a.deadline_at < CURRENT_TIMESTAMP THEN FALSE
        WHEN COUNT(DISTINCT att.id) >= a.max_attempts THEN FALSE
        WHEN COUNT(DISTINCT CASE WHEN att.status = 'IN_PROGRESS' THEN att.id END) > 0 THEN FALSE
        ELSE TRUE
    END AS is_eligible_to_start
FROM assessments a
INNER JOIN enrollments e ON a.course_id = e.course_id AND e.trainee_id = $1 AND e.status = 'ACTIVE'
LEFT JOIN assessment_attempts att ON a.id = att.assessment_id AND att.trainee_id = $1
WHERE a.id = $2
GROUP BY a.id, a.course_id, a.title, a.status, a.max_attempts, a.pass_percentage, a.deadline_at;


-- -----------------------------------------------------------------------------
-- 5.11 Start New Assessment Attempt
-- Inserts a new IN_PROGRESS attempt calculating sequential attempt number.
-- -----------------------------------------------------------------------------
-- WRITE
INSERT INTO assessment_attempts (
    assessment_id,
    trainee_id,
    attempt_number,
    status,
    started_at
)
SELECT 
    a.id,
    $1, -- trainee_id
    COALESCE(MAX(prev.attempt_number), 0) + 1,
    'IN_PROGRESS',
    CURRENT_TIMESTAMP
FROM assessments a
LEFT JOIN assessment_attempts prev ON a.id = prev.assessment_id AND prev.trainee_id = $1
WHERE a.id = $2 AND a.status = 'PUBLISHED'
GROUP BY a.id, a.max_attempts
HAVING COALESCE(MAX(prev.attempt_number), 0) < a.max_attempts
RETURNING id, assessment_id, trainee_id, attempt_number, status, started_at;


-- -----------------------------------------------------------------------------
-- 5.12 Fetch Active Question Paper for Trainee (Secure View)
-- Trainee view of questions during examination: hides correct_option and explanation.
-- -----------------------------------------------------------------------------
-- READ
SELECT 
    att.id AS attempt_id,
    att.assessment_id,
    att.started_at,
    a.duration_minutes,
    q.id AS question_id,
    q.question_order,
    q.question_text,
    q.option_a,
    q.option_b,
    q.option_c,
    q.option_d,
    q.points,
    ans.selected_option AS previously_selected_option
FROM assessment_attempts att
INNER JOIN assessments a ON att.assessment_id = a.id
INNER JOIN questions q ON a.id = q.assessment_id
LEFT JOIN attempt_answers ans ON att.id = ans.attempt_id AND q.id = ans.question_id
WHERE att.id = $1 AND att.trainee_id = $2 AND att.status = 'IN_PROGRESS'
ORDER BY q.question_order ASC;


-- -----------------------------------------------------------------------------
-- 5.13 Record Question Answer (with Auto-Scoring Comparison)
-- Upserts a trainee's selected option and computes points awarded immediately
-- based on questions.correct_option and questions.points.
-- -----------------------------------------------------------------------------
-- WRITE
INSERT INTO attempt_answers (
    attempt_id,
    assessment_id,
    question_id,
    selected_option,
    is_correct,
    points_awarded
)
SELECT 
    att.id,
    att.assessment_id,
    q.id,
    $3, -- selected_option: 'A' | 'B' | 'C' | 'D'
    ($3 = q.correct_option),
    CASE WHEN $3 = q.correct_option THEN q.points ELSE 0 END
FROM assessment_attempts att
INNER JOIN questions q ON att.assessment_id = q.assessment_id
WHERE att.id = $1 
  AND att.trainee_id = $2 
  AND q.id = $4 
  AND att.status = 'IN_PROGRESS'
ON CONFLICT (attempt_id, question_id)
DO UPDATE SET 
    selected_option = EXCLUDED.selected_option,
    is_correct = EXCLUDED.is_correct,
    points_awarded = EXCLUDED.points_awarded,
    answered_at = CURRENT_TIMESTAMP
RETURNING id, attempt_id, question_id, selected_option, is_correct, points_awarded;


-- -----------------------------------------------------------------------------
-- 5.14 Automated Assessment Submission & Final Grading
-- Server-side transactional calculation of total points, score percentage,
-- and pass/fail verdict (PRD Section 6.7).
-- -----------------------------------------------------------------------------
-- WRITE
WITH scoring_summary AS (
    SELECT 
        att.id AS attempt_id,
        COALESCE(SUM(ans.points_awarded), 0) AS calculated_earned_points,
        COALESCE((SELECT SUM(q.points) FROM questions q WHERE q.assessment_id = att.assessment_id), 0) AS calculated_total_points,
        CASE 
            WHEN COALESCE((SELECT SUM(q.points) FROM questions q WHERE q.assessment_id = att.assessment_id), 0) = 0 THEN 0.00
            ELSE ROUND(
                (COALESCE(SUM(ans.points_awarded), 0)::numeric / 
                 (SELECT SUM(q.points) FROM questions q WHERE q.assessment_id = att.assessment_id)::numeric) * 100.0, 2
            )
        END AS calculated_percentage
    FROM assessment_attempts att
    LEFT JOIN attempt_answers ans ON att.id = ans.attempt_id
    WHERE att.id = $1 AND att.trainee_id = $2 AND att.status = 'IN_PROGRESS'
    GROUP BY att.id, att.assessment_id
)
UPDATE assessment_attempts att
SET 
    status = 'GRADED',
    submitted_at = CURRENT_TIMESTAMP,
    graded_at = CURRENT_TIMESTAMP,
    earned_points = s.calculated_earned_points,
    total_points = s.calculated_total_points,
    score_percentage = s.calculated_percentage,
    is_passed = (s.calculated_percentage >= a.pass_percentage),
    updated_at = CURRENT_TIMESTAMP
FROM scoring_summary s
INNER JOIN assessments a ON s.attempt_id = $1 AND a.id = att.assessment_id
WHERE att.id = s.attempt_id
RETURNING 
    att.id, att.assessment_id, att.trainee_id, att.attempt_number,
    att.status, att.earned_points, att.total_points, att.score_percentage, att.is_passed;


-- -----------------------------------------------------------------------------
-- 5.15 Expire Timed-Out Attempt
-- Marks abandoned or overtime IN_PROGRESS attempt as EXPIRED.
-- -----------------------------------------------------------------------------
-- WRITE
UPDATE assessment_attempts
SET 
    status = 'EXPIRED',
    updated_at = CURRENT_TIMESTAMP
WHERE id = $1 AND status = 'IN_PROGRESS'
RETURNING id, assessment_id, trainee_id, status;


-- -----------------------------------------------------------------------------
-- 5.16 Trainee Detailed Attempt Result & Question Review
-- Post-grading review showing questions, student choices, correct answers, and explanations.
-- -----------------------------------------------------------------------------
-- READ
SELECT 
    att.id AS attempt_id,
    att.attempt_number,
    att.score_percentage,
    att.earned_points,
    att.total_points,
    att.is_passed,
    att.submitted_at,
    a.title AS assessment_title,
    a.pass_percentage,
    c.id AS course_id,
    c.title AS course_title,
    q.question_order,
    q.question_text,
    q.option_a,
    q.option_b,
    q.option_c,
    q.option_d,
    q.correct_option,
    q.explanation,
    q.points AS question_possible_points,
    ans.selected_option AS trainee_selected_option,
    ans.is_correct AS answer_is_correct,
    ans.points_awarded
FROM assessment_attempts att
INNER JOIN assessments a ON att.assessment_id = a.id
INNER JOIN courses c ON a.course_id = c.id
INNER JOIN questions q ON a.id = q.assessment_id
LEFT JOIN attempt_answers ans ON att.id = ans.attempt_id AND q.id = ans.question_id
WHERE att.id = $1 AND att.trainee_id = $2 AND att.status = 'GRADED'
ORDER BY q.question_order ASC;


-- -----------------------------------------------------------------------------
-- 5.17 Trainee Assessment Attempt History (GET /api/v1/attempts/me)
-- Trainee personal gradebook across all taken assessments.
-- -----------------------------------------------------------------------------
-- READ
SELECT 
    att.id AS attempt_id,
    att.assessment_id,
    a.title AS assessment_title,
    c.id AS course_id,
    c.title AS course_title,
    att.attempt_number,
    att.status,
    att.started_at,
    att.submitted_at,
    att.earned_points,
    att.total_points,
    att.score_percentage,
    att.is_passed
FROM assessment_attempts att
INNER JOIN assessments a ON att.assessment_id = a.id
INNER JOIN courses c ON a.course_id = c.id
WHERE att.trainee_id = $1
ORDER BY att.started_at DESC;


-- -----------------------------------------------------------------------------
-- 5.18 Trainer Assessment Performance & Item Analytics
-- Aggregates performance, pass rates, and per-question difficulty statistics.
-- -----------------------------------------------------------------------------
-- READ
SELECT 
    a.id AS assessment_id,
    a.title AS assessment_title,
    COUNT(DISTINCT att.id) AS total_graded_attempts,
    COUNT(DISTINCT att.trainee_id) AS distinct_trainees_tested,
    ROUND(AVG(att.score_percentage)::numeric, 2) AS avg_score_pct,
    COUNT(DISTINCT CASE WHEN att.is_passed = TRUE THEN att.id END) AS passed_attempts,
    ROUND(
        (COUNT(DISTINCT CASE WHEN att.is_passed = TRUE THEN att.id END)::numeric / 
         NULLIF(COUNT(DISTINCT att.id), 0)::numeric) * 100.0, 2
    ) AS pass_rate_percentage
FROM assessments a
INNER JOIN courses c ON a.course_id = c.id
LEFT JOIN assessment_attempts att ON a.id = att.assessment_id AND att.status = 'GRADED'
WHERE a.id = $1 AND c.trainer_id = $2
GROUP BY a.id, a.title;



-- =============================================================================
-- MODULE 6: COURSE FEEDBACK & REVIEWS (MEMBER 3)
-- Canonical Tables: feedback, courses, users, trainee_profiles
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 6.1 Submit or Update Course Feedback (Upsert)
-- Trainee submits or edits rating (1..5) and comments for an enrolled course.
-- -----------------------------------------------------------------------------
-- WRITE
INSERT INTO feedback (
    trainee_id,
    course_id,
    rating,
    comment
)
SELECT 
    $1, -- trainee_id
    $2, -- course_id
    $3, -- rating: 1..5
    $4  -- comment: VARCHAR(2000)
FROM enrollments e
WHERE e.trainee_id = $1 AND e.course_id = $2
ON CONFLICT (trainee_id, course_id)
DO UPDATE SET 
    rating = EXCLUDED.rating,
    comment = EXCLUDED.comment,
    updated_at = CURRENT_TIMESTAMP
RETURNING id, trainee_id, course_id, rating, comment, updated_at;


-- -----------------------------------------------------------------------------
-- 6.2 Delete Course Feedback
-- Trainee deletes previously submitted feedback.
-- -----------------------------------------------------------------------------
-- WRITE
DELETE FROM feedback
WHERE trainee_id = $1 AND course_id = $2
RETURNING id, trainee_id, course_id;


-- -----------------------------------------------------------------------------
-- 6.3 Fetch Course Feedback Reviews with Trainee Bio
-- Retrieves public feedback stream joined with reviewer credentials.
-- -----------------------------------------------------------------------------
-- READ
SELECT 
    fb.id AS feedback_id,
    fb.course_id,
    fb.rating,
    fb.comment,
    fb.created_at,
    u.full_name AS trainee_name,
    tp.organization AS trainee_organization,
    tp.headline AS trainee_headline
FROM feedback fb
INNER JOIN users u ON fb.trainee_id = u.id
INNER JOIN trainee_profiles tp ON u.id = tp.user_id
WHERE fb.course_id = $1
ORDER BY fb.created_at DESC
LIMIT $2 OFFSET $3;


-- -----------------------------------------------------------------------------
-- 6.4 Course Aggregate Rating & Star Distribution Summary
-- Computes average rating and frequency across star levels (1 to 5).
-- -----------------------------------------------------------------------------
-- READ
SELECT 
    c.id AS course_id,
    c.title AS course_title,
    COUNT(fb.id) AS total_ratings_count,
    COALESCE(ROUND(AVG(fb.rating)::numeric, 2), 0.00) AS average_rating,
    COUNT(CASE WHEN fb.rating = 5 THEN 1 END) AS count_5_star,
    COUNT(CASE WHEN fb.rating = 4 THEN 1 END) AS count_4_star,
    COUNT(CASE WHEN fb.rating = 3 THEN 1 END) AS count_3_star,
    COUNT(CASE WHEN fb.rating = 2 THEN 1 END) AS count_2_star,
    COUNT(CASE WHEN fb.rating = 1 THEN 1 END) AS count_1_star
FROM courses c
LEFT JOIN feedback fb ON c.id = fb.course_id
WHERE c.id = $1
GROUP BY c.id, c.title;



-- =============================================================================
-- MODULE 7: COMPLETION CERTIFICATES (MEMBER 4)
-- Canonical Tables: certificates, enrollments, courses, lessons, lesson_progress,
--                   assessments, assessment_attempts, users
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 7.1 Verify Certificate Eligibility
-- Evaluates completion prerequisites before issuing credential (PRD 6.6/6.7):
-- 1. 100% lessons completed (with >= 1 lesson in course)
-- 2. All required published assessments passed
-- -----------------------------------------------------------------------------
-- READ
SELECT 
    e.id AS enrollment_id,
    e.trainee_id,
    e.course_id,
    c.title AS course_title,
    (SELECT COUNT(*) FROM lessons WHERE course_id = c.id) AS total_lessons,
    (SELECT COUNT(*) FROM lesson_progress lp WHERE lp.enrollment_id = e.id) AS completed_lessons,
    (SELECT COUNT(*) FROM assessments a WHERE a.course_id = c.id AND a.status = 'PUBLISHED' AND a.is_required = TRUE) AS required_assessments,
    (
        SELECT COUNT(DISTINCT a.id)
        FROM assessments a
        INNER JOIN assessment_attempts att ON a.id = att.assessment_id AND att.trainee_id = e.trainee_id
        WHERE a.course_id = c.id AND a.status = 'PUBLISHED' AND a.is_required = TRUE AND att.is_passed = TRUE
    ) AS passed_required_assessments,
    CASE 
        WHEN (SELECT COUNT(*) FROM lessons WHERE course_id = c.id) = 0 THEN FALSE
        WHEN (SELECT COUNT(*) FROM lesson_progress lp WHERE lp.enrollment_id = e.id) < (SELECT COUNT(*) FROM lessons WHERE course_id = c.id) THEN FALSE
        WHEN (
            SELECT COUNT(DISTINCT a.id)
            FROM assessments a
            INNER JOIN assessment_attempts att ON a.id = att.assessment_id AND att.trainee_id = e.trainee_id
            WHERE a.course_id = c.id AND a.status = 'PUBLISHED' AND a.is_required = TRUE AND att.is_passed = TRUE
        ) < (SELECT COUNT(*) FROM assessments a WHERE a.course_id = c.id AND a.status = 'PUBLISHED' AND a.is_required = TRUE) THEN FALSE
        ELSE TRUE
    END AS is_eligible_for_certificate
FROM enrollments e
INNER JOIN courses c ON e.course_id = c.id
WHERE e.trainee_id = $1 AND e.course_id = $2 AND e.status IN ('ACTIVE', 'COMPLETED');


-- -----------------------------------------------------------------------------
-- 7.2 Issue Completion Certificate
-- Inserts credential record with unique verification code upon eligibility confirmation.
-- -----------------------------------------------------------------------------
-- WRITE
INSERT INTO certificates (
    trainee_id,
    course_id,
    certificate_code,
    issued_at
) VALUES (
    $1, -- trainee_id: BIGINT
    $2, -- course_id: BIGINT
    $3, -- certificate_code: VARCHAR(64) UNIQUE
    CURRENT_TIMESTAMP
)
ON CONFLICT (trainee_id, course_id) DO NOTHING
RETURNING id, trainee_id, course_id, certificate_code, issued_at;


-- -----------------------------------------------------------------------------
-- 7.3 Revoke Completion Certificate
-- Administrative invalidation of a credential for compliance violations.
-- -----------------------------------------------------------------------------
-- WRITE
UPDATE certificates
SET revoked_at = CURRENT_TIMESTAMP
WHERE id = $1 AND revoked_at IS NULL
RETURNING id, certificate_code, trainee_id, course_id, revoked_at;


-- -----------------------------------------------------------------------------
-- 7.4 Public Certificate Verification by Hash / Code
-- Public endpoint resolving validity, recipient name, course, trainer, and dates.
-- -----------------------------------------------------------------------------
-- READ
SELECT 
    cert.id AS certificate_id,
    cert.certificate_code,
    cert.issued_at,
    cert.revoked_at,
    CASE WHEN cert.revoked_at IS NULL THEN TRUE ELSE FALSE END AS is_valid,
    trainee.full_name AS recipient_name,
    tp.organization AS recipient_organization,
    c.id AS course_id,
    c.title AS course_title,
    c.subject AS course_subject,
    c.level AS course_level,
    trainer.full_name AS instructor_name,
    trp.headline AS instructor_headline
FROM certificates cert
INNER JOIN users trainee ON cert.trainee_id = trainee.id
INNER JOIN trainee_profiles tp ON trainee.id = tp.user_id
INNER JOIN courses c ON cert.course_id = c.id
INNER JOIN users trainer ON c.trainer_id = trainer.id
INNER JOIN trainer_profiles trp ON trainer.id = trp.user_id
WHERE cert.certificate_code = BTRIM($1);


-- -----------------------------------------------------------------------------
-- 7.5 Trainee Earned Certificates Portfolio
-- Trainee list of issued credentials with course metadata and direct verification codes.
-- -----------------------------------------------------------------------------
-- READ
SELECT 
    cert.id AS certificate_id,
    cert.certificate_code,
    cert.issued_at,
    cert.revoked_at,
    c.id AS course_id,
    c.title AS course_title,
    c.subject,
    c.level,
    trainer.full_name AS trainer_name
FROM certificates cert
INNER JOIN courses c ON cert.course_id = c.id
INNER JOIN users trainer ON c.trainer_id = trainer.id
WHERE cert.trainee_id = $1 AND cert.revoked_at IS NULL
ORDER BY cert.issued_at DESC;



-- =============================================================================
-- MODULE 8: HOMEPAGE ANNOUNCEMENTS & BROADCASTS (MEMBER 4)
-- Canonical Tables: announcements, users
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 8.1 Create System Announcement
-- Authors broadcast message for portal dashboard.
-- -----------------------------------------------------------------------------
-- WRITE
INSERT INTO announcements (
    creator_id,
    title,
    body,
    category,
    status,
    expires_at
) VALUES (
    $1,        -- creator_id: BIGINT
    $2,        -- title: VARCHAR(200)
    $3,        -- body: TEXT
    $4,        -- category: 'ANNOUNCEMENT' | 'ACHIEVEMENT' | 'NEW_CONTENT'
    'DRAFT',   -- status
    $5         -- expires_at: TIMESTAMPTZ NULL
)
RETURNING id, creator_id, title, category, status, created_at;


-- -----------------------------------------------------------------------------
-- 8.2 Update Announcement Content & Expiry
-- Modifies announcement draft parameters.
-- -----------------------------------------------------------------------------
-- WRITE
UPDATE announcements
SET 
    title = $3,
    body = $4,
    category = $5,
    expires_at = $6,
    updated_at = CURRENT_TIMESTAMP
WHERE id = $1 AND creator_id = $2
RETURNING id, title, category, expires_at, updated_at;


-- -----------------------------------------------------------------------------
-- 8.3 Publish Announcement
-- Makes announcement visible on the public feed.
-- -----------------------------------------------------------------------------
-- WRITE
UPDATE announcements
SET 
    status = 'PUBLISHED',
    published_at = CURRENT_TIMESTAMP,
    updated_at = CURRENT_TIMESTAMP
WHERE id = $1 AND status = 'DRAFT'
RETURNING id, title, status, published_at;


-- -----------------------------------------------------------------------------
-- 8.4 Archive Announcement
-- Retires broadcast from active feed.
-- -----------------------------------------------------------------------------
-- WRITE
UPDATE announcements
SET 
    status = 'ARCHIVED',
    updated_at = CURRENT_TIMESTAMP
WHERE id = $1 AND status = 'PUBLISHED'
RETURNING id, title, status;


-- -----------------------------------------------------------------------------
-- 8.5 Public Homepage Active Announcements Feed (PRD Section 6.10)
-- Retrieves currently active, non-expired published announcements.
-- -----------------------------------------------------------------------------
-- READ
SELECT 
    a.id AS announcement_id,
    a.title,
    a.body,
    a.category,
    a.published_at,
    a.expires_at,
    u.full_name AS creator_name,
    u.role AS creator_role
FROM announcements a
INNER JOIN users u ON a.creator_id = u.id
WHERE 
    a.status = 'PUBLISHED'
    AND (a.expires_at IS NULL OR a.expires_at > CURRENT_TIMESTAMP)
ORDER BY a.published_at DESC
LIMIT $1;



-- =============================================================================
-- MODULE 9: EXECUTIVE ADMIN DASHBOARDS & ANALYTICS (MEMBER 4)
-- Cross-table analytical aggregations across all 18 canonical tables.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 9.1 High-Level Platform KPIs Summary
-- Executive snapshot of platform capacity building metrics in a single row.
-- -----------------------------------------------------------------------------
-- READ
SELECT 
    (SELECT COUNT(*) FROM users WHERE status = 'ACTIVE') AS total_active_users,
    (SELECT COUNT(*) FROM users WHERE role = 'TRAINEE' AND status = 'ACTIVE') AS total_active_trainees,
    (SELECT COUNT(*) FROM users WHERE role = 'TRAINER' AND status = 'ACTIVE') AS total_active_trainers,
    (SELECT COUNT(*) FROM courses WHERE status = 'PUBLISHED') AS total_published_courses,
    (SELECT COUNT(*) FROM enrollments WHERE status = 'ACTIVE') AS total_active_enrollments,
    (SELECT COUNT(*) FROM enrollments WHERE status = 'COMPLETED') AS total_completed_enrollments,
    (SELECT COUNT(*) FROM certificates WHERE revoked_at IS NULL) AS total_certificates_issued,
    (SELECT COALESCE(ROUND(AVG(rating)::numeric, 2), 0.00) FROM feedback) AS platform_avg_rating;


-- -----------------------------------------------------------------------------
-- 9.2 Top Performing Courses Leaderboard
-- Ranks courses by enrollment, completion conversion rate, and trainee satisfaction.
-- -----------------------------------------------------------------------------
-- READ
SELECT 
    c.id AS course_id,
    c.title AS course_title,
    c.subject,
    c.level,
    trainer.full_name AS trainer_name,
    COUNT(DISTINCT e.id) AS total_enrollments,
    COUNT(DISTINCT CASE WHEN e.status = 'COMPLETED' THEN e.id END) AS completed_enrollments,
    ROUND(
        (COUNT(DISTINCT CASE WHEN e.status = 'COMPLETED' THEN e.id END)::numeric / 
         NULLIF(COUNT(DISTINCT e.id), 0)::numeric) * 100.0, 2
    ) AS completion_rate_percentage,
    COUNT(DISTINCT cert.id) AS certificates_awarded,
    COALESCE(ROUND(AVG(fb.rating)::numeric, 2), 0.00) AS avg_feedback_rating,
    COUNT(DISTINCT fb.id) AS feedback_count
FROM courses c
INNER JOIN users trainer ON c.trainer_id = trainer.id
LEFT JOIN enrollments e ON c.id = e.course_id
LEFT JOIN certificates cert ON c.id = cert.course_id AND cert.revoked_at IS NULL
LEFT JOIN feedback fb ON c.id = fb.course_id
WHERE c.status = 'PUBLISHED'
GROUP BY c.id, c.title, c.subject, c.level, trainer.full_name
ORDER BY total_enrollments DESC, avg_feedback_rating DESC
LIMIT $1;


-- -----------------------------------------------------------------------------
-- 9.3 Trainee Competency Growth & Skills Distribution Matrix
-- Evaluates organizational skill proficiency levels across departments/organizations.
-- -----------------------------------------------------------------------------
-- READ
SELECT 
    s.id AS skill_id,
    s.name AS skill_name,
    s.category AS skill_category,
    tp.organization,
    COUNT(DISTINCT ts.trainee_id) AS trainees_count,
    ROUND(AVG(ts.proficiency)::numeric, 2) AS avg_proficiency_level,
    COUNT(CASE WHEN ts.proficiency >= 3 THEN 1 END) AS advanced_or_expert_count
FROM skills s
INNER JOIN trainee_skills ts ON s.id = ts.skill_id
INNER JOIN users u ON ts.trainee_id = u.id AND u.status = 'ACTIVE'
INNER JOIN trainee_profiles tp ON u.id = tp.user_id
GROUP BY s.id, s.name, s.category, tp.organization
ORDER BY tp.organization ASC, trainees_count DESC;


-- -----------------------------------------------------------------------------
-- 9.4 Trainer Productivity & Impact Leaderboard
-- Evaluates trainer engagement, student reach, and overall instructional score.
-- -----------------------------------------------------------------------------
-- READ
SELECT 
    u.id AS trainer_id,
    u.full_name AS trainer_name,
    trp.subject_expertise,
    trp.organization,
    COUNT(DISTINCT c.id) AS published_courses_count,
    COUNT(DISTINCT e.id) AS total_trainees_enrolled,
    COUNT(DISTINCT cert.id) AS graduates_certified,
    COALESCE(ROUND(AVG(fb.rating)::numeric, 2), 0.00) AS overall_instructional_rating
FROM users u
INNER JOIN trainer_profiles trp ON u.id = trp.user_id
LEFT JOIN courses c ON u.id = c.trainer_id AND c.status = 'PUBLISHED'
LEFT JOIN enrollments e ON c.id = e.course_id
LEFT JOIN certificates cert ON c.id = cert.course_id AND cert.revoked_at IS NULL
LEFT JOIN feedback fb ON c.id = fb.course_id
WHERE u.role = 'TRAINER' AND u.status = 'ACTIVE'
GROUP BY u.id, u.full_name, trp.subject_expertise, trp.organization
ORDER BY total_trainees_enrolled DESC, overall_instructional_rating DESC
LIMIT $1;
