-- CAPSERA schema baseline (PostgreSQL 15+).

-- Consolidated from the application repository database/migrations/001-005.

-- Run against an empty database; this script creates the 18 canonical tables.


-- Source: 001_create_users_and_profiles.sql

-- =============================================================================
-- CAPSERA Migration 001: Users and Professional Profiles
-- Primary Module Owner: Member 1 (Identity, Profiles, and User Governance)
-- Status: Proposed under CP-02 (Pending Formal Team Approval — see ADR-004)
-- Database: PostgreSQL 15+ (capsera_db)
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. users (Canonical Entity: User)
-- -----------------------------------------------------------------------------
CREATE TABLE users (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    full_name VARCHAR(150) NOT NULL,
    email VARCHAR(255) NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role VARCHAR(20) NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'PENDING',
    approved_by BIGINT NULL,
    approved_at TIMESTAMPTZ NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_users_approved_by
        FOREIGN KEY (approved_by) REFERENCES users (id) ON DELETE SET NULL,
    CONSTRAINT chk_users_full_name_non_empty
        CHECK (LENGTH(BTRIM(full_name)) > 0),
    CONSTRAINT chk_users_email_trimmed
        CHECK (email = BTRIM(email) AND LENGTH(email) > 3),
    CONSTRAINT chk_users_password_hash_non_empty
        CHECK (LENGTH(BTRIM(password_hash)) > 0),
    CONSTRAINT chk_users_role
        CHECK (role IN ('TRAINEE', 'TRAINER', 'ADMIN')),
    CONSTRAINT chk_users_status
        CHECK (status IN ('PENDING', 'ACTIVE', 'REJECTED', 'SUSPENDED'))
);

-- Single unique index enforcing both exact and case-insensitive email uniqueness
-- (e.g. Alice@Example.com vs alice@example.com); login queries must use LOWER(email) = LOWER($1)
CREATE UNIQUE INDEX uq_users_email_ci ON users (LOWER(email));

-- Support Admin user governance filters (GET /api/v1/admin/users) & dashboard counts
CREATE INDEX idx_users_role_status ON users (role, status);

-- Index self-referencing foreign key
CREATE INDEX idx_users_approved_by ON users (approved_by);

-- -----------------------------------------------------------------------------
-- 2. trainee_profiles (Canonical Entity: TraineeProfile)
-- -----------------------------------------------------------------------------
CREATE TABLE trainee_profiles (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id BIGINT NOT NULL,
    headline VARCHAR(200) NULL,
    organization VARCHAR(200) NULL,
    biography TEXT NULL,
    qualifications TEXT NULL,
    work_experience TEXT NULL,
    interests TEXT NULL,
    external_certifications TEXT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_trainee_profiles_user_id UNIQUE (user_id),
    CONSTRAINT fk_trainee_profiles_user
        FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE RESTRICT
);

-- Note: uq_trainee_profiles_user_id automatically indexes user_id.

-- -----------------------------------------------------------------------------
-- 3. trainer_profiles (Canonical Entity: TrainerProfile)
-- -----------------------------------------------------------------------------
CREATE TABLE trainer_profiles (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id BIGINT NOT NULL,
    headline VARCHAR(200) NULL,
    organization VARCHAR(200) NULL,
    biography TEXT NULL,
    qualifications TEXT NULL,
    work_experience TEXT NULL,
    subject_expertise VARCHAR(255) NULL,
    years_of_experience NUMERIC(4,1) NOT NULL DEFAULT 0.0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_trainer_profiles_user_id UNIQUE (user_id),
    CONSTRAINT fk_trainer_profiles_user
        FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE RESTRICT,
    CONSTRAINT chk_trainer_profiles_experience
        CHECK (years_of_experience >= 0 AND years_of_experience <= 80.0)
);

-- Note: uq_trainer_profiles_user_id automatically indexes user_id.

COMMIT;


-- Source: 002_create_skills_and_competency.sql

-- =============================================================================
-- CAPSERA Migration 002: Canonical Skill Catalogue and Competency Mapping
-- Primary Module Owner: Member 4 (Competency, Recommendations, Certificates, Admin)
-- Status: Proposed under CP-02 (Pending Formal Team Approval — see ADR-004)
-- Dependencies: 001_create_users_and_profiles.sql (users)
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 4. skills (Canonical Entity: Skill)
-- -----------------------------------------------------------------------------
CREATE TABLE skills (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name VARCHAR(120) NOT NULL,
    category VARCHAR(120) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_skills_name_trimmed
        CHECK (name = BTRIM(name) AND LENGTH(name) > 0),
    CONSTRAINT chk_skills_category_non_empty
        CHECK (LENGTH(BTRIM(category)) > 0)
);

-- Enforce exact & case-insensitive unique skill names (e.g. 'Python' vs 'python').
-- Uses LOWER(name) directly (chk_skills_name_trimmed already guarantees trimmed storage)
-- so WHERE LOWER(name) = LOWER($1) uses this index cleanly in the PostgreSQL planner.
CREATE UNIQUE INDEX uq_skills_name_ci ON skills (LOWER(name));

-- Support skill catalogue category filtering (GET /api/v1/skills)
CREATE INDEX idx_skills_category ON skills (category);

-- -----------------------------------------------------------------------------
-- 5. trainee_skills (Canonical Entity: TraineeSkill)
-- -----------------------------------------------------------------------------
CREATE TABLE trainee_skills (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    trainee_id BIGINT NOT NULL,
    skill_id BIGINT NOT NULL,
    proficiency SMALLINT NOT NULL,

    CONSTRAINT uq_trainee_skills_trainee_skill UNIQUE (trainee_id, skill_id),
    CONSTRAINT fk_trainee_skills_trainee
        FOREIGN KEY (trainee_id) REFERENCES users (id) ON DELETE RESTRICT,
    CONSTRAINT fk_trainee_skills_skill
        FOREIGN KEY (skill_id) REFERENCES skills (id) ON DELETE RESTRICT,
    CONSTRAINT chk_trainee_skills_proficiency
        CHECK (proficiency BETWEEN 1 AND 4)
);

-- uq_trainee_skills_trainee_skill indexes leading column trainee_id; index skill_id FK explicitly
CREATE INDEX idx_trainee_skills_skill_id ON trainee_skills (skill_id);

-- -----------------------------------------------------------------------------
-- 6. trainer_skills (Canonical Entity: TrainerSkill)
-- -----------------------------------------------------------------------------
CREATE TABLE trainer_skills (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    trainer_id BIGINT NOT NULL,
    skill_id BIGINT NOT NULL,
    proficiency SMALLINT NOT NULL,
    years_of_experience NUMERIC(4,1) NOT NULL DEFAULT 0.0,

    CONSTRAINT uq_trainer_skills_trainer_skill UNIQUE (trainer_id, skill_id),
    CONSTRAINT fk_trainer_skills_trainer
        FOREIGN KEY (trainer_id) REFERENCES users (id) ON DELETE RESTRICT,
    CONSTRAINT fk_trainer_skills_skill
        FOREIGN KEY (skill_id) REFERENCES skills (id) ON DELETE RESTRICT,
    CONSTRAINT chk_trainer_skills_proficiency
        CHECK (proficiency BETWEEN 1 AND 4),
    CONSTRAINT chk_trainer_skills_experience
        CHECK (years_of_experience >= 0 AND years_of_experience <= 80.0)
);

-- Composite index covers skill_id FK AND deterministic recommendation ranking (PRD Section 6.8):
-- 1. Exact skill match (skill_id) -> 2. Higher proficiency -> 3. More relevant experience
CREATE INDEX idx_trainer_skills_recommendation
    ON trainer_skills (skill_id, proficiency DESC, years_of_experience DESC);

COMMIT;


-- Source: 003_create_courses_lessons_and_enrollments.sql

-- =============================================================================
-- CAPSERA Migration 003: Courses, Lessons, Learning Resources, Enrollments & Progress
-- Primary Module Owner: Member 2 (Courses and Learning Resources)
-- Status: Proposed under CP-02 (Pending Formal Team Approval — see ADR-004)
-- Dependencies: 001_create_users_and_profiles.sql (users)
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 7. courses (Canonical Entity: Course)
-- -----------------------------------------------------------------------------
CREATE TABLE courses (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    trainer_id BIGINT NOT NULL,
    title VARCHAR(200) NOT NULL,
    summary VARCHAR(500) NULL,
    description TEXT NULL,
    subject VARCHAR(120) NULL,
    level VARCHAR(30) NULL,
    thumbnail_url VARCHAR(2048) NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'DRAFT',
    published_at TIMESTAMPTZ NULL,
    archived_at TIMESTAMPTZ NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_courses_trainer
        FOREIGN KEY (trainer_id) REFERENCES users (id) ON DELETE RESTRICT,
    CONSTRAINT chk_courses_title_non_empty
        CHECK (LENGTH(BTRIM(title)) > 0),
    CONSTRAINT chk_courses_level
        CHECK (level IS NULL OR level IN ('BEGINNER', 'INTERMEDIATE', 'ADVANCED')),
    CONSTRAINT chk_courses_status
        CHECK (status IN ('DRAFT', 'PUBLISHED', 'ARCHIVED')),
    CONSTRAINT chk_courses_published_fields
        CHECK (
            status <> 'PUBLISHED'
            OR (
                description IS NOT NULL AND LENGTH(BTRIM(description)) > 0
                AND subject IS NOT NULL AND LENGTH(BTRIM(subject)) > 0
                AND level IS NOT NULL
            )
        ),
    CONSTRAINT chk_courses_lifecycle_timestamps
        CHECK (
            (status <> 'PUBLISHED' OR (published_at IS NOT NULL AND archived_at IS NULL))
            AND (status <> 'ARCHIVED' OR archived_at IS NOT NULL)
            AND (status = 'ARCHIVED' OR archived_at IS NULL)
            AND (published_at IS NULL OR archived_at IS NULL OR archived_at >= published_at)
        )
);

CREATE INDEX idx_courses_trainer_id ON courses (trainer_id);
CREATE INDEX idx_courses_status_subject ON courses (status, subject);
CREATE INDEX idx_courses_status_level ON courses (status, level);

-- -----------------------------------------------------------------------------
-- 8. lessons (Canonical Entity: Lesson)
-- -----------------------------------------------------------------------------
CREATE TABLE lessons (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    course_id BIGINT NOT NULL,
    title VARCHAR(200) NOT NULL,
    content TEXT NULL,
    lesson_order INTEGER NOT NULL,
    estimated_duration_minutes INTEGER NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- Non-deferrable by default so PostgreSQL INSERT ... ON CONFLICT (course_id, lesson_order) works
    CONSTRAINT uq_lessons_course_order
        UNIQUE (course_id, lesson_order),
    -- Ordered (course_id, id) to support composite child FKs without duplicating lessons_pkey (id)
    CONSTRAINT uq_lessons_course_id_id
        UNIQUE (course_id, id),
    CONSTRAINT fk_lessons_course
        FOREIGN KEY (course_id) REFERENCES courses (id) ON DELETE RESTRICT,
    CONSTRAINT chk_lessons_title_non_empty
        CHECK (LENGTH(BTRIM(title)) > 0),
    CONSTRAINT chk_lessons_order_positive
        CHECK (lesson_order >= 1),
    CONSTRAINT chk_lessons_duration_positive
        CHECK (estimated_duration_minutes IS NULL OR estimated_duration_minutes > 0)
);

-- Note: uq_lessons_course_order and uq_lessons_course_id_id index leading column course_id.

-- -----------------------------------------------------------------------------
-- 9. learning_resources (Canonical Entity: LearningResource)
-- Stores metadata and storage/link references only (never binary payloads — PRD 6.4/8.4).
-- -----------------------------------------------------------------------------
CREATE TABLE learning_resources (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    course_id BIGINT NOT NULL,
    lesson_id BIGINT NULL,
    uploaded_by BIGINT NOT NULL,
    title VARCHAR(200) NOT NULL,
    description TEXT NULL,
    resource_type VARCHAR(20) NOT NULL,
    storage_ref VARCHAR(2048) NULL,
    external_url VARCHAR(2048) NULL,
    original_filename VARCHAR(255) NULL,
    mime_type VARCHAR(120) NULL,
    file_size_bytes BIGINT NULL,
    resource_order INTEGER NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_learning_resources_course
        FOREIGN KEY (course_id) REFERENCES courses (id) ON DELETE RESTRICT,
    CONSTRAINT fk_learning_resources_lesson_course
        FOREIGN KEY (course_id, lesson_id) REFERENCES lessons (course_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_learning_resources_uploaded_by
        FOREIGN KEY (uploaded_by) REFERENCES users (id) ON DELETE RESTRICT,
    CONSTRAINT chk_learning_resources_title_non_empty
        CHECK (LENGTH(BTRIM(title)) > 0),
    CONSTRAINT chk_learning_resources_type
        CHECK (resource_type IN ('VIDEO', 'PRESENTATION', 'DOCUMENT', 'LINK', 'OTHER')),
    CONSTRAINT chk_learning_resources_location
        CHECK (
            (storage_ref IS NOT NULL AND LENGTH(BTRIM(storage_ref)) > 0)
            OR (external_url IS NOT NULL AND LENGTH(BTRIM(external_url)) > 0)
        ),
    CONSTRAINT chk_learning_resources_link_url
        CHECK (
            resource_type <> 'LINK'
            OR (external_url IS NOT NULL AND LENGTH(BTRIM(external_url)) > 0)
        ),
    CONSTRAINT chk_learning_resources_file_size
        CHECK (file_size_bytes IS NULL OR file_size_bytes >= 0),
    CONSTRAINT chk_learning_resources_order_positive
        CHECK (resource_order >= 1)
);

CREATE INDEX idx_learning_resources_course_order ON learning_resources (course_id, resource_order);
CREATE INDEX idx_learning_resources_lesson_id ON learning_resources (lesson_id);
CREATE INDEX idx_learning_resources_uploaded_by ON learning_resources (uploaded_by);

-- -----------------------------------------------------------------------------
-- 10. enrollments (Canonical Entity: Enrollment)
-- Course progress percentage is derived dynamically from lesson_progress & lessons,
-- never stored as a client-supplied percentage (PRD Section 6.6).
-- -----------------------------------------------------------------------------
CREATE TABLE enrollments (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    trainee_id BIGINT NOT NULL,
    course_id BIGINT NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
    enrolled_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMPTZ NULL,
    cancelled_at TIMESTAMPTZ NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_enrollments_trainee_course UNIQUE (trainee_id, course_id),
    CONSTRAINT uq_enrollments_course_id_id UNIQUE (course_id, id),
    CONSTRAINT fk_enrollments_trainee
        FOREIGN KEY (trainee_id) REFERENCES users (id) ON DELETE RESTRICT,
    CONSTRAINT fk_enrollments_course
        FOREIGN KEY (course_id) REFERENCES courses (id) ON DELETE RESTRICT,
    CONSTRAINT chk_enrollments_status
        CHECK (status IN ('ACTIVE', 'COMPLETED', 'CANCELLED')),
    CONSTRAINT chk_enrollments_status_timestamps
        CHECK (
            (status = 'ACTIVE' AND completed_at IS NULL AND cancelled_at IS NULL)
            OR (status = 'COMPLETED' AND completed_at IS NOT NULL AND cancelled_at IS NULL)
            OR (status = 'CANCELLED' AND cancelled_at IS NOT NULL AND completed_at IS NULL)
        ),
    CONSTRAINT chk_enrollments_chronology
        CHECK (
            (completed_at IS NULL OR completed_at >= enrolled_at)
            AND (cancelled_at IS NULL OR cancelled_at >= enrolled_at)
        )
);

-- uq_enrollments_trainee_course indexes trainee_id; uq_enrollments_course_id_id &
-- idx_enrollments_course_status index course_id & status filters
CREATE INDEX idx_enrollments_course_status ON enrollments (course_id, status);
CREATE INDEX idx_enrollments_status ON enrollments (status);

-- -----------------------------------------------------------------------------
-- 11. lesson_progress (Canonical Entity: LessonProgress)
-- Composite FKs guarantee completed lesson belongs to the exact same course_id
-- as the referenced enrollment.
-- -----------------------------------------------------------------------------
CREATE TABLE lesson_progress (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    enrollment_id BIGINT NOT NULL,
    course_id BIGINT NOT NULL,
    lesson_id BIGINT NOT NULL,
    completed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_lesson_progress_enrollment_lesson UNIQUE (enrollment_id, lesson_id),
    CONSTRAINT fk_lesson_progress_enrollment_course
        FOREIGN KEY (course_id, enrollment_id)
        REFERENCES enrollments (course_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_lesson_progress_lesson_course
        FOREIGN KEY (course_id, lesson_id)
        REFERENCES lessons (course_id, id) ON DELETE RESTRICT
);

-- uq_lesson_progress_enrollment_lesson indexes enrollment_id; composite index covers
-- fk_lesson_progress_lesson_course (course_id, lesson_id) and course-scoped progress queries
CREATE INDEX idx_lesson_progress_course_lesson ON lesson_progress (course_id, lesson_id);

COMMIT;


-- Source: 004_create_assessments_attempts_and_feedback.sql

-- =============================================================================
-- CAPSERA Migration 004: Assessments, Questions, Attempts, Answers & Feedback
-- Primary Module Owner: Member 3 (Assessments, Results, Progress, and Feedback)
-- Status: Proposed under CP-02 (Pending Formal Team Approval — see ADR-004)
-- Dependencies:
--   - 001_create_users_and_profiles.sql (users)
--   - 003_create_courses_lessons_and_enrollments.sql (courses)
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 12. assessments (Canonical Entity: Assessment)
-- -----------------------------------------------------------------------------
CREATE TABLE assessments (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    course_id BIGINT NOT NULL,
    title VARCHAR(200) NOT NULL,
    instructions TEXT NULL,
    deadline_at TIMESTAMPTZ NULL,
    duration_minutes INTEGER NULL,
    max_attempts INTEGER NOT NULL DEFAULT 1,
    pass_percentage NUMERIC(5,2) NOT NULL DEFAULT 60.00,
    is_required BOOLEAN NOT NULL DEFAULT TRUE,
    status VARCHAR(20) NOT NULL DEFAULT 'DRAFT',
    published_at TIMESTAMPTZ NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_assessments_course
        FOREIGN KEY (course_id) REFERENCES courses (id) ON DELETE RESTRICT,
    CONSTRAINT chk_assessments_title_non_empty
        CHECK (LENGTH(BTRIM(title)) > 0),
    CONSTRAINT chk_assessments_duration_positive
        CHECK (duration_minutes IS NULL OR duration_minutes > 0),
    CONSTRAINT chk_assessments_max_attempts
        CHECK (max_attempts >= 1),
    CONSTRAINT chk_assessments_pass_percentage
        CHECK (pass_percentage > 0 AND pass_percentage <= 100.00),
    CONSTRAINT chk_assessments_status
        CHECK (status IN ('DRAFT', 'PUBLISHED', 'CLOSED')),
    CONSTRAINT chk_assessments_published_timestamp
        CHECK (status <> 'PUBLISHED' OR published_at IS NOT NULL)
);

CREATE INDEX idx_assessments_course_status ON assessments (course_id, status);
CREATE INDEX idx_assessments_status_deadline ON assessments (status, deadline_at);

-- -----------------------------------------------------------------------------
-- 13. questions (Canonical Entity: Question)
-- Four-option MCQ with exactly one correct option ('A'..'D'), points, and explanation.
-- -----------------------------------------------------------------------------
CREATE TABLE questions (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    assessment_id BIGINT NOT NULL,
    question_order INTEGER NOT NULL,
    question_text TEXT NOT NULL,
    option_a TEXT NOT NULL,
    option_b TEXT NOT NULL,
    option_c TEXT NOT NULL,
    option_d TEXT NOT NULL,
    correct_option CHAR(1) NOT NULL,
    explanation TEXT NULL,
    points INTEGER NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- Non-deferrable by default so PostgreSQL INSERT ... ON CONFLICT (assessment_id, question_order) works
    CONSTRAINT uq_questions_assessment_order
        UNIQUE (assessment_id, question_order),
    -- Ordered (assessment_id, id) to support composite FK from attempt_answers without duplicating pkey
    CONSTRAINT uq_questions_assessment_id_id
        UNIQUE (assessment_id, id),
    CONSTRAINT fk_questions_assessment
        FOREIGN KEY (assessment_id) REFERENCES assessments (id) ON DELETE RESTRICT,
    CONSTRAINT chk_questions_order_positive
        CHECK (question_order >= 1),
    CONSTRAINT chk_questions_text_non_empty
        CHECK (LENGTH(BTRIM(question_text)) > 0),
    CONSTRAINT chk_questions_options_non_empty
        CHECK (
            LENGTH(BTRIM(option_a)) > 0
            AND LENGTH(BTRIM(option_b)) > 0
            AND LENGTH(BTRIM(option_c)) > 0
            AND LENGTH(BTRIM(option_d)) > 0
        ),
    CONSTRAINT chk_questions_correct_option
        CHECK (correct_option IN ('A', 'B', 'C', 'D')),
    CONSTRAINT chk_questions_points_positive
        CHECK (points > 0)
);

-- Note: uq_questions_assessment_order and uq_questions_assessment_id_id index assessment_id.

-- -----------------------------------------------------------------------------
-- 14. assessment_attempts (Canonical Entity: AssessmentAttempt)
-- Scoring columns are computed exclusively on the server inside a transaction.
-- -----------------------------------------------------------------------------
CREATE TABLE assessment_attempts (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    assessment_id BIGINT NOT NULL,
    trainee_id BIGINT NOT NULL,
    attempt_number INTEGER NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'IN_PROGRESS',
    started_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    submitted_at TIMESTAMPTZ NULL,
    graded_at TIMESTAMPTZ NULL,
    earned_points INTEGER NULL,
    total_points INTEGER NULL,
    score_percentage NUMERIC(5,2) NULL,
    is_passed BOOLEAN NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_assessment_attempts_number
        UNIQUE (assessment_id, trainee_id, attempt_number),
    CONSTRAINT uq_assessment_attempts_assessment_id_id
        UNIQUE (assessment_id, id),
    CONSTRAINT fk_assessment_attempts_assessment
        FOREIGN KEY (assessment_id) REFERENCES assessments (id) ON DELETE RESTRICT,
    CONSTRAINT fk_assessment_attempts_trainee
        FOREIGN KEY (trainee_id) REFERENCES users (id) ON DELETE RESTRICT,
    CONSTRAINT chk_assessment_attempts_number_positive
        CHECK (attempt_number >= 1),
    CONSTRAINT chk_assessment_attempts_status
        CHECK (status IN ('IN_PROGRESS', 'SUBMITTED', 'GRADED', 'EXPIRED')),
    CONSTRAINT chk_assessment_attempts_points
        CHECK (
            (earned_points IS NULL OR earned_points >= 0)
            AND (total_points IS NULL OR total_points > 0)
            AND (earned_points IS NULL OR total_points IS NULL OR earned_points <= total_points)
        ),
    CONSTRAINT chk_assessment_attempts_percentage
        CHECK (score_percentage IS NULL OR (score_percentage >= 0 AND score_percentage <= 100.00)),
    CONSTRAINT chk_assessment_attempts_submission_timestamps
        CHECK (
            (status IN ('SUBMITTED', 'GRADED') AND submitted_at IS NOT NULL AND submitted_at >= started_at)
            OR (status IN ('IN_PROGRESS', 'EXPIRED') AND submitted_at IS NULL)
        ),
    CONSTRAINT chk_assessment_attempts_graded_fields
        CHECK (
            (
                status = 'GRADED'
                AND graded_at IS NOT NULL
                AND graded_at >= submitted_at
                AND earned_points IS NOT NULL
                AND total_points IS NOT NULL
                AND score_percentage IS NOT NULL
                AND is_passed IS NOT NULL
            )
            OR (
                status <> 'GRADED'
                AND graded_at IS NULL
                AND earned_points IS NULL
                AND total_points IS NULL
                AND score_percentage IS NULL
                AND is_passed IS NULL
            )
        )
);

-- Prevent concurrent active (IN_PROGRESS) attempts by the same trainee on the same assessment.
-- Backend must expire timed-out IN_PROGRESS attempts before inserting a permitted retry.
CREATE UNIQUE INDEX uq_assessment_attempts_one_in_progress
    ON assessment_attempts (assessment_id, trainee_id)
    WHERE status = 'IN_PROGRESS';

-- Support trainee attempt history (GET /api/v1/attempts/me) & FK lookup on trainee_id
CREATE INDEX idx_assessment_attempts_trainee_history
    ON assessment_attempts (trainee_id, started_at DESC);

-- Support course/admin dashboard assessment performance aggregations without duplicating
-- the (assessment_id, trainee_id) prefix already covered by uq_assessment_attempts_number
CREATE INDEX idx_assessment_attempts_assessment_status_pass
    ON assessment_attempts (assessment_id, status, is_passed);

-- -----------------------------------------------------------------------------
-- 15. attempt_answers (Canonical Entity: AttemptAnswer)
-- Composite FKs guarantee that question_id belongs to the exact same assessment_id
-- as the parent attempt_id.
-- -----------------------------------------------------------------------------
CREATE TABLE attempt_answers (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    attempt_id BIGINT NOT NULL,
    assessment_id BIGINT NOT NULL,
    question_id BIGINT NOT NULL,
    selected_option CHAR(1) NULL,
    is_correct BOOLEAN NOT NULL,
    points_awarded INTEGER NOT NULL DEFAULT 0,
    answered_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_attempt_answers_attempt_question
        UNIQUE (attempt_id, question_id),
    CONSTRAINT fk_attempt_answers_attempt_assessment
        FOREIGN KEY (assessment_id, attempt_id)
        REFERENCES assessment_attempts (assessment_id, id) ON DELETE RESTRICT,
    CONSTRAINT fk_attempt_answers_question_assessment
        FOREIGN KEY (assessment_id, question_id)
        REFERENCES questions (assessment_id, id) ON DELETE RESTRICT,
    CONSTRAINT chk_attempt_answers_selected_option
        CHECK (selected_option IS NULL OR selected_option IN ('A', 'B', 'C', 'D')),
    CONSTRAINT chk_attempt_answers_points_awarded
        CHECK (points_awarded >= 0 AND (is_correct = TRUE OR points_awarded = 0))
);

-- uq_attempt_answers_attempt_question indexes attempt_id; composite index covers
-- fk_attempt_answers_question_assessment (assessment_id, question_id) and per-question analytics
CREATE INDEX idx_attempt_answers_assessment_question
    ON attempt_answers (assessment_id, question_id);

-- -----------------------------------------------------------------------------
-- 16. feedback (Canonical Entity: Feedback)
-- One current feedback record per trainee and course (supports upsert/edit — PRD 6.9).
-- -----------------------------------------------------------------------------
CREATE TABLE feedback (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    trainee_id BIGINT NOT NULL,
    course_id BIGINT NOT NULL,
    rating SMALLINT NOT NULL,
    comment VARCHAR(2000) NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_feedback_trainee_course UNIQUE (trainee_id, course_id),
    CONSTRAINT fk_feedback_trainee
        FOREIGN KEY (trainee_id) REFERENCES users (id) ON DELETE RESTRICT,
    CONSTRAINT fk_feedback_course
        FOREIGN KEY (course_id) REFERENCES courses (id) ON DELETE RESTRICT,
    CONSTRAINT chk_feedback_rating
        CHECK (rating BETWEEN 1 AND 5),
    CONSTRAINT chk_feedback_comment_non_blank
        CHECK (comment IS NULL OR LENGTH(BTRIM(comment)) > 0)
);

-- uq_feedback_trainee_course indexes trainee_id; index course_id explicitly
CREATE INDEX idx_feedback_course_id ON feedback (course_id, created_at DESC);

COMMIT;


-- Source: 005_create_certificates_and_announcements.sql

-- =============================================================================
-- CAPSERA Migration 005: Completion Certificates and Homepage Announcements
-- Primary Module Owner: Member 4 (Competency, Recommendations, Certificates, Admin)
-- Status: Proposed under CP-02 (Pending Formal Team Approval — see ADR-004)
-- Dependencies:
--   - 001_create_users_and_profiles.sql (users)
--   - 003_create_courses_lessons_and_enrollments.sql (courses)
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 17. certificates (Canonical Entity: Certificate)
-- Eligibility (100% lessons completed with >= 1 lesson + required published assessments
-- passed) is enforced transactionally by backend business logic before INSERT (PRD 6.6/6.7).
-- -----------------------------------------------------------------------------
CREATE TABLE certificates (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    trainee_id BIGINT NOT NULL,
    course_id BIGINT NOT NULL,
    certificate_code VARCHAR(64) NOT NULL,
    issued_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    revoked_at TIMESTAMPTZ NULL,

    CONSTRAINT uq_certificates_code UNIQUE (certificate_code),
    CONSTRAINT uq_certificates_trainee_course UNIQUE (trainee_id, course_id),
    CONSTRAINT fk_certificates_trainee
        FOREIGN KEY (trainee_id) REFERENCES users (id) ON DELETE RESTRICT,
    CONSTRAINT fk_certificates_course
        FOREIGN KEY (course_id) REFERENCES courses (id) ON DELETE RESTRICT,
    CONSTRAINT chk_certificates_code_non_empty
        CHECK (certificate_code = BTRIM(certificate_code) AND LENGTH(certificate_code) > 0),
    CONSTRAINT chk_certificates_revoked_after_issued
        CHECK (revoked_at IS NULL OR revoked_at >= issued_at)
);

-- uq_certificates_trainee_course indexes trainee_id; uq_certificates_code indexes certificate_code;
-- index course_id FK explicitly
CREATE INDEX idx_certificates_course_id ON certificates (course_id);

-- -----------------------------------------------------------------------------
-- 18. announcements (Canonical Entity: Announcement)
-- Public homepage feed shows only PUBLISHED, non-expired announcements (PRD 6.10).
-- -----------------------------------------------------------------------------
CREATE TABLE announcements (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    creator_id BIGINT NOT NULL,
    title VARCHAR(200) NOT NULL,
    body TEXT NOT NULL,
    category VARCHAR(30) NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'DRAFT',
    published_at TIMESTAMPTZ NULL,
    expires_at TIMESTAMPTZ NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_announcements_creator
        FOREIGN KEY (creator_id) REFERENCES users (id) ON DELETE RESTRICT,
    CONSTRAINT chk_announcements_title_non_empty
        CHECK (LENGTH(BTRIM(title)) > 0),
    CONSTRAINT chk_announcements_body_non_empty
        CHECK (LENGTH(BTRIM(body)) > 0),
    CONSTRAINT chk_announcements_category
        CHECK (category IN ('ANNOUNCEMENT', 'ACHIEVEMENT', 'NEW_CONTENT')),
    CONSTRAINT chk_announcements_status
        CHECK (status IN ('DRAFT', 'PUBLISHED', 'ARCHIVED')),
    CONSTRAINT chk_announcements_published_timestamp
        CHECK (status <> 'PUBLISHED' OR published_at IS NOT NULL),
    CONSTRAINT chk_announcements_expiry_order
        CHECK (expires_at IS NULL OR published_at IS NULL OR expires_at > published_at)
);

CREATE INDEX idx_announcements_creator_id ON announcements (creator_id);
CREATE INDEX idx_announcements_public_feed
    ON announcements (status, published_at DESC, expires_at);

COMMIT;


