# CAPSERA — Database Normalization Specification (1NF → 2NF → 3NF → BCNF)

**Course:** Database Management Systems (DBMS) & Advanced Programming (AP)  
**System:** CAPSERA — Digital Capacity Building and Learning Management Portal  
**Document:** `dbms/01_normalization.md`  
**Checkpoint:** CP1 — Schema Design & Normalization  
**Database Engine:** PostgreSQL 15+ (`capsera_db`)  

---

## 1. Executive Summary & Domain Scope

CAPSERA is an enterprise digital capacity building and competency tracking portal designed for structured workforce upskilling. Its operational ecosystem coordinates role-based identity management (`TRAINEE`, `TRAINER`, `ADMIN`), organizational competency mapping (skills & proficiency ratings), self-paced modular curricula (courses, lessons, learning resources), continuous evaluation (MCQ assessments, attempts, question-level answer scoring), structured feedback, automated completion certification, and administrative audit logging.

To guarantee ACID properties, avoid update/insert/delete anomalies, ensure referential integrity, and minimize redundant storage overhead, the underlying relational database has been systematically designed from an initial unnormalized business universe through **First Normal Form (1NF)**, **Second Normal Form (2NF)**, **Third Normal Form (3NF)**, and **Boyce-Codd Normal Form (BCNF)**.

---

## 2. Phase 0: The Unnormalized Form (UNF)

In a naive flat-file or unnormalized operational spreadsheet, all data points related to a trainee's organizational capacity building journey are stored in a single monolithic relation: `UNF_TRAINEE_RECORD`.

### 2.1 The Unnormalized Record Structure
```text
UNF_TRAINEE_RECORD (
    user_id, full_name, email, password_hash, role, status, approved_by_admin_id, approved_at,
    trainee_headline, organization, biography, qualifications, work_experience, interests,
    { skill_id, skill_name, skill_category, proficiency_level, verified_by_trainer_id },
    { course_id, course_title, course_description, course_level, trainer_id, trainer_name,
      enrollment_date, enrollment_status, course_progress_pct,
      { lesson_id, lesson_title, lesson_order, is_completed, completed_at, resource_id, resource_title, resource_url } },
    { assessment_id, assessment_title, passing_score, attempt_id, attempt_score, is_passed,
      { question_id, question_text, selected_option, is_correct, question_points } },
    { feedback_id, rating, feedback_comment, feedback_date },
    { certificate_id, certificate_number, issue_date, cert_course_title, verification_hash }
)
```

### 2.2 Anomalies Inherent in the Unnormalized Form

1. **Insertion Anomalies:**
   - A new organizational skill (e.g., "PostgreSQL Database Tuning") cannot be registered in the system unless at least one trainee is enrolled with that skill.
   - A trainer cannot author a new course curriculum or draft lessons until a trainee enrolls in it.
   - An assessment question bank cannot be created without being tied to a specific trainee's attempt.

2. **Deletion Anomalies:**
   - If the sole trainee enrolled in a specialized course (e.g., "AI Governance") unenrolls or has their account deleted, the entire course curriculum, its lesson metadata, and study resources are permanently destroyed.
   - If an employee leaves the organization, deleting their user row inadvertently deletes the audit record of who approved their profile and the trainer skills they possessed.

3. **Update / Modification Anomalies:**
   - If a course title changes from "Advanced SQL" to "Advanced SQL & Query Optimization", this value must be updated across hundreds of thousands of individual trainee enrollment records. If any row is missed, data becomes inconsistent.
   - If a trainer updates their profile biography or full name, redundant copies stored across all course records become desynchronized.

---

## 3. Phase 1: First Normal Form (1NF)

### 3.1 Axiom of 1NF
> A relation $R$ is in **First Normal Form (1NF)** if and only if all underlying attribute domains contain only **atomic (indivisible)** values, and there are no **repeating groups** or multi-valued arrays. Every table must have a designated primary key.

### 3.2 Transformation from UNF to 1NF
To achieve 1NF:
1. All nested repeating groups (`{skills}`, `{courses}`, `{lessons}`, `{assessments}`, `{questions}`, `{certificates}`) are extracted into independent relations.
2. Multi-valued fields (e.g., comma-delimited interests, arrays) are atomized.
3. Every resulting relation is assigned a distinct composite or candidate primary key.

### 3.3 Resulting 1NF Relations & Functional Dependencies

#### Relation 1: `R1_USER_PROFILES` (Users & Combined Profiles)
- **Attributes:** `(user_id, full_name, email, password_hash, role, status, approved_by, approved_at, headline, organization, biography, qualifications, work_experience, interests)`
- **Primary Key:** `{user_id}`
- **Functional Dependencies:**
  - $FD_1: \text{user\_id} \to \text{full\_name}, \text{email}, \text{password\_hash}, \text{role}, \text{status}, \text{approved\_by}, \text{approved\_at}, \text{headline}, \text{organization}, \text{biography}, \text{qualifications}, \text{work\_experience}, \text{interests}$
  - $FD_2: \text{email} \to \text{user\_id}, \text{full\_name}, \dots$

#### Relation 2: `R2_USER_SKILLS` (Skills Flattened)
- **Attributes:** `(user_id, skill_id, skill_name, skill_category, proficiency_level, verified_by)`
- **Primary Key:** `{(user_id, skill_id)}`
- **Functional Dependencies:**
  - $FD_1: \text{user\_id}, \text{skill\_id} \to \text{proficiency\_level}, \text{verified\_by}$
  - $FD_2: \text{skill\_id} \to \text{skill\_name}, \text{skill\_category}$ *(Partial Dependency)*

#### Relation 3: `R3_ENROLLMENTS_FLAT` (Courses & Enrollments Flattened)
- **Attributes:** `(user_id, course_id, course_title, course_description, course_level, trainer_id, trainer_name, enrolled_at, enrollment_status, progress_pct)`
- **Primary Key:** `{(user_id, course_id)}`
- **Functional Dependencies:**
  - $FD_1: \text{user\_id}, \text{course\_id} \to \text{enrolled\_at}, \text{enrollment\_status}, \text{progress\_pct}$
  - $FD_2: \text{course\_id} \to \text{course\_title}, \text{course\_description}, \text{course\_level}, \text{trainer\_id}$ *(Partial Dependency)*
  - $FD_3: \text{trainer\_id} \to \text{trainer\_name}$ *(Transitive Dependency)*

#### Relation 4: `R4_LESSON_PROGRESS_FLAT` (Lessons & Progress Flattened)
- **Attributes:** `(user_id, course_id, lesson_id, lesson_title, lesson_order, is_completed, completed_at, resource_id, resource_title, resource_url)`
- **Primary Key:** `{(user_id, lesson_id)}`
- **Functional Dependencies:**
  - $FD_1: \text{user\_id}, \text{lesson\_id} \to \text{is\_completed}, \text{completed\_at}$
  - $FD_2: \text{lesson\_id} \to \text{course\_id}, \text{lesson\_title}, \text{lesson\_order}$ *(Partial Dependency)*
  - $FD_3: \text{resource\_id} \to \text{resource\_title}, \text{resource\_url}$

#### Relation 5: `R5_ATTEMPTS_ANSWERS_FLAT` (Assessments, Attempts & Question Answers Flattened)
- **Attributes:** `(attempt_id, user_id, assessment_id, assessment_title, passing_score, question_id, question_text, selected_option, is_correct, score, attempted_at)`
- **Primary Key:** `{(attempt_id, question_id)}`
- **Functional Dependencies:**
  - $FD_1: \text{attempt\_id}, \text{question\_id} \to \text{selected\_option}, \text{is\_correct}$
  - $FD_2: \text{attempt\_id} \to \text{user\_id}, \text{assessment\_id}, \text{score}, \text{attempted\_at}$ *(Partial Dependency)*
  - $FD_3: \text{assessment\_id} \to \text{assessment\_title}, \text{passing\_score}$ *(Transitive Dependency)*
  - $FD_4: \text{question\_id} \to \text{question\_text}$ *(Partial Dependency)*

### 3.4 Remaining Flaws in 1NF
While repeating groups are removed, relations `R2_USER_SKILLS`, `R3_ENROLLMENTS_FLAT`, `R4_LESSON_PROGRESS_FLAT`, and `R5_ATTEMPTS_ANSWERS_FLAT` violate **Second Normal Form (2NF)** because non-prime attributes depend on only a **proper subset** of composite primary keys (Partial Functional Dependencies).

---

## 4. Phase 2: Second Normal Form (2NF)

### 4.1 Axiom of 2NF
> A relation $R$ is in **Second Normal Form (2NF)** if and only if it is in 1NF and **every non-prime attribute is fully functionally dependent on every candidate key of $R$**. No non-prime attribute may depend on a proper subset of any candidate key.

### 4.2 Elimination of Partial Dependencies
To reach 2NF, each composite-keyed table with partial dependencies is decomposed:
1. From `R2_USER_SKILLS`: Extract `{skill_id} -> {skill_name, skill_category}` into `skills`. Leave `trainee_skills` and `trainer_skills` with fully dependent attributes `{proficiency_level}`.
2. From `R3_ENROLLMENTS_FLAT`: Extract `{course_id} -> {course_title, course_description, course_level, trainer_id}` into `courses`. Leave `enrollments` with `{enrolled_at, enrollment_status, progress_pct}`.
3. From `R4_LESSON_PROGRESS_FLAT`: Extract `{lesson_id} -> {course_id, lesson_title, lesson_order}` into `lessons`, and `{resource_id} -> {resource_title, resource_url}` into `learning_resources`. Leave `lesson_progress` dependent strictly on `(enrollment_id, lesson_id)` or `(user_id, lesson_id)`.
4. From `R5_ATTEMPTS_ANSWERS_FLAT`: Extract `{assessment_id} -> {title, passing_score}` into `assessments`, `{question_id} -> {question_text}` into `questions`, `{attempt_id} -> {user_id, assessment_id, score}` into `assessment_attempts`. Leave `attempt_answers` dependent strictly on `(attempt_id, question_id)`.

### 4.3 Resulting 2NF Relations & Functional Dependencies

| 2NF Relation | Primary Key | Determinant $\to$ Non-Prime Attributes | Partial Dependencies Eliminated |
|---|---|---|---|
| `skills` | `{id}` | $\text{id} \to \text{name}, \text{category}, \text{description}$ | Isolated from user-skill junction |
| `trainee_skills` | `{(user_id, skill_id)}` | $\text{user\_id}, \text{skill\_id} \to \text{proficiency\_level}$ | Fully dependent on composite key |
| `trainer_skills` | `{(user_id, skill_id)}` | $\text{user\_id}, \text{skill\_id} \to \text{certified\_at}$ | Fully dependent on composite key |
| `courses` | `{id}` | $\text{id} \to \text{title}, \text{description}, \text{level}, \text{trainer\_id}$ | Isolated from enrollment record |
| `lessons` | `{id}` | $\text{id} \to \text{course\_id}, \text{title}, \text{lesson\_order}$ | Isolated from progress tracking |
| `learning_resources` | `{id}` | $\text{id} \to \text{course\_id}, \text{lesson\_id}, \text{title}, \text{resource\_url}$ | Isolated from curriculum |
| `enrollments` | `{(user_id, course_id)}` | $\text{user\_id}, \text{course\_id} \to \text{status}, \text{enrolled\_at}$ | Fully dependent on composite key |
| `lesson_progress` | `{(user_id, lesson_id)}` | $\text{user\_id}, \text{lesson\_id} \to \text{is\_completed}, \text{completed\_at}$ | Fully dependent on composite key |
| `assessments` | `{id}` | $\text{id} \to \text{course\_id}, \text{title}, \text{passing\_score}$ | Isolated from attempt records |
| `questions` | `{id}` | $\text{id} \to \text{assessment\_id}, \text{question\_text}, \text{points}$ | Isolated from attempt answers |
| `assessment_attempts` | `{id}` | $\text{id} \to \text{user\_id}, \text{assessment\_id}, \text{score}, \text{attempted\_at}$ | Isolated from individual answers |
| `attempt_answers` | `{(attempt_id, question_id)}` | $\text{attempt\_id}, \text{question\_id} \to \text{selected\_option}, \text{is\_correct}$ | Fully dependent on composite key |

### 4.4 Remaining Flaws in 2NF
While partial dependencies are resolved, 2NF relations still harbor **Transitive Dependencies** ($X \to Y \to Z$ where $Z$ is not a primary or candidate key):
- In `R1_USER_PROFILES`: A user has role-specific profile fields (e.g. Trainees have `organization`, `interests`; Trainers have `biography`, `qualifications`). A trainee row has null trainer fields and vice versa. Furthermore, profile updates depend transitively on user identification.
- In `enrollments` and `lesson_progress`: Progress percentage or lesson progress can transitively reference course scope.
- In `certificates` and `feedback`: Course metadata and trainee identities transitively cascade.

---

## 5. Phase 3: Third Normal Form (3NF)

### 5.1 Axiom of 3NF
> A relation $R$ is in **Third Normal Form (3NF)** if and only if it is in 2NF and **no non-prime attribute is transitively dependent on any candidate key**.  
> Formally, for every non-trivial functional dependency $X \to A$ in $R$:
> 1. $X$ is a **superkey** of $R$, OR
> 2. $A$ is a **prime attribute** (member of some candidate key) of $R$.

### 5.2 Elimination of Transitive Dependencies
1. **Decoupling User Identity and Profiles:**
   `users` retains core authentication and governance (`id`, `full_name`, `email`, `password_hash`, `role`, `status`, `approved_by`). Role-specific profiles are decoupled into 1:1 extension tables:
   - `trainee_profiles`: keyed by `user_id` (foreign key to `users.id` with `UNIQUE` constraint).
   - `trainer_profiles`: keyed by `user_id` (foreign key to `users.id` with `UNIQUE` constraint).
2. **Decoupling Progress and Enrollment Scopes:**
   `lesson_progress` is scoped directly to `(enrollment_id, lesson_id)`, eliminating duplicate user-course transitivities.
3. **Decoupling Evaluation & Recognition Entities:**
   - `feedback` depends strictly on `(user_id, course_id)` with its own primary key.
   - `certificates` depends strictly on `certificate_number` / `(user_id, course_id)` with its own primary key.
   - `announcements` and `audit_logs` are isolated into independent administrative relations.

### 5.3 Complete 3NF Table Registry (The 18 Canonical Tables)

Below is the formal specification of all 18 normalized relations in CAPSERA:

#### 1. `users`
- **Candidate Keys:** `{id}`, `{email}`
- **Primary Key:** `{id}`
- **Functional Dependencies:**
  - $\text{id} \to \text{full\_name}, \text{email}, \text{password\_hash}, \text{role}, \text{status}, \text{approved\_by}, \text{approved\_at}, \text{created\_at}, \text{updated\_at}$
  - $\text{email} \to \text{id}, \text{full\_name}, \dots$
- **3NF Verification:** All determinants are candidate keys.

#### 2. `trainee_profiles`
- **Candidate Keys:** `{id}`, `{user_id}`
- **Primary Key:** `{id}`
- **Foreign Key:** `user_id REFERENCES users(id) ON DELETE CASCADE`
- **Functional Dependencies:**
  - $\text{id} \to \text{user\_id}, \text{headline}, \text{organization}, \text{biography}, \text{qualifications}, \text{work\_experience}, \text{interests}, \text{created\_at}, \text{updated\_at}$
  - $\text{user\_id} \to \text{id}, \text{headline}, \dots$
- **3NF Verification:** Both `{id}` and `{user_id}` are superkeys.

#### 3. `trainer_profiles`
- **Candidate Keys:** `{id}`, `{user_id}`
- **Primary Key:** `{id}`
- **Foreign Key:** `user_id REFERENCES users(id) ON DELETE CASCADE`
- **Functional Dependencies:**
  - $\text{id} \to \text{user\_id}, \text{headline}, \text{organization}, \text{biography}, \text{qualifications}, \text{work\_experience}, \text{created\_at}, \text{updated\_at}$
  - $\text{user\_id} \to \text{id}, \dots$
- **3NF Verification:** Both `{id}` and `{user_id}` are superkeys.

#### 4. `skills`
- **Candidate Keys:** `{id}`, `{name}`
- **Primary Key:** `{id}`
- **Functional Dependencies:**
  - $\text{id} \to \text{name}, \text{category}, \text{description}, \text{created\_at}, \text{updated\_at}$
  - $\text{name} \to \text{id}, \text{category}, \dots$
- **3NF Verification:** Both `{id}` and `{name}` are superkeys.

#### 5. `trainee_skills`
- **Candidate Keys:** `{id}`, `{(user_id, skill_id)}`
- **Primary Key:** `{id}`
- **Functional Dependencies:**
  - $\text{id} \to \text{user\_id}, \text{skill\_id}, \text{proficiency\_level}, \text{created\_at}, \text{updated\_at}$
  - $\text{user\_id}, \text{skill\_id} \to \text{id}, \text{proficiency\_level}, \dots$
- **3NF Verification:** All determinants are superkeys.

#### 6. `trainer_skills`
- **Candidate Keys:** `{id}`, `{(user_id, skill_id)}`
- **Primary Key:** `{id}`
- **Functional Dependencies:**
  - $\text{id} \to \text{user\_id}, \text{skill\_id}, \text{created\_at}, \text{updated\_at}$
  - $\text{user\_id}, \text{skill\_id} \to \text{id}, \dots$
- **3NF Verification:** All determinants are superkeys.

#### 7. `courses`
- **Candidate Keys:** `{id}`
- **Primary Key:** `{id}`
- **Functional Dependencies:**
  - $\text{id} \to \text{trainer\_id}, \text{title}, \text{description}, \text{level}, \text{status}, \text{thumbnail\_url}, \text{created\_at}, \text{updated\_at}$
- **3NF Verification:** Determinant `{id}` is the primary superkey.

#### 8. `lessons`
- **Candidate Keys:** `{id}`, `{(course_id, lesson_order)}`
- **Primary Key:** `{id}`
- **Functional Dependencies:**
  - $\text{id} \to \text{course\_id}, \text{title}, \text{content}, \text{lesson\_order}, \text{created\_at}, \text{updated\_at}$
  - $\text{course\_id}, \text{lesson\_order} \to \text{id}, \text{title}, \dots$
- **3NF Verification:** All determinants are candidate keys.

#### 9. `learning_resources`
- **Candidate Keys:** `{id}`
- **Primary Key:** `{id}`
- **Functional Dependencies:**
  - $\text{id} \to \text{course\_id}, \text{lesson\_id}, \text{uploaded_by}, \text{title}, \text{resource\_type}, \text{resource\_url}, \text{file\_size\_bytes}, \text{created\_at}$
- **3NF Verification:** Determinant `{id}` is a superkey.

#### 10. `enrollments`
- **Candidate Keys:** `{id}`, `{(user_id, course_id)}`
- **Primary Key:** `{id}`
- **Functional Dependencies:**
  - $\text{id} \to \text{user\_id}, \text{course\_id}, \text{status}, \text{enrolled\_at}, \text{completed\_at}, \text{progress\_pct}, \text{created\_at}, \text{updated\_at}$
  - $\text{user\_id}, \text{course\_id} \to \text{id}, \text{status}, \dots$
- **3NF Verification:** All determinants are superkeys.

#### 11. `lesson_progress`
- **Candidate Keys:** `{id}`, `{(enrollment_id, lesson_id)}`
- **Primary Key:** `{id}`
- **Functional Dependencies:**
  - $\text{id} \to \text{enrollment\_id}, \text{lesson\_id}, \text{course\_id}, \text{is\_completed}, \text{completed\_at}, \text{created\_at}, \text{updated\_at}$
  - $\text{enrollment\_id}, \text{lesson\_id} \to \text{id}, \text{course\_id}, \dots$
- **3NF Verification:** All determinants are superkeys.

#### 12. `assessments`
- **Candidate Keys:** `{id}`, `{(course_id, title)}`
- **Primary Key:** `{id}`
- **Functional Dependencies:**
  - $\text{id} \to \text{course\_id}, \text{title}, \text{description}, \text{passing\_score}, \text{time\_limit\_minutes}, \text{is\_active}, \text{created\_at}, \text{updated\_at}$
- **3NF Verification:** All determinants are superkeys.

#### 13. `questions`
- **Candidate Keys:** `{id}`, `{(assessment_id, question_order)}`
- **Primary Key:** `{id}`
- **Functional Dependencies:**
  - $\text{id} \to \text{assessment\_id}, \text{question\_text}, \text{options}, \text{correct\_answer}, \text{points}, \text{question\_order}, \text{created\_at}, \text{updated\_at}$
- **3NF Verification:** All determinants are superkeys.

#### 14. `assessment_attempts`
- **Candidate Keys:** `{id}`
- **Primary Key:** `{id}`
- **Functional Dependencies:**
  - $\text{id} \to \text{assessment\_id}, \text{user\_id}, \text{status}, \text{score}, \text{total\_points}, \text{is\_passed}, \text{started\_at}, \text{submitted\_at}, \text{created\_at}, \text{updated\_at}$
- **3NF Verification:** Determinant `{id}` is a superkey.

#### 15. `attempt_answers`
- **Candidate Keys:** `{id}`, `{(attempt_id, question_id)}`
- **Primary Key:** `{id}`
- **Functional Dependencies:**
  - $\text{id} \to \text{attempt\_id}, \text{question\_id}, \text{assessment\_id}, \text{selected\_option}, \text{is\_correct}, \text{points\_awarded}, \text{created\_at}, \text{updated\_at}$
  - $\text{attempt\_id}, \text{question\_id} \to \text{id}, \text{selected\_option}, \dots$
- **3NF Verification:** All determinants are superkeys.

#### 16. `feedback`
- **Candidate Keys:** `{id}`, `{(user_id, course_id)}`
- **Primary Key:** `{id}`
- **Functional Dependencies:**
  - $\text{id} \to \text{user\_id}, \text{course\_id}, \text{rating}, \text{comments}, \text{created\_at}, \text{updated\_at}$
  - $\text{user\_id}, \text{course\_id} \to \text{id}, \text{rating}, \dots$
- **3NF Verification:** All determinants are superkeys.

#### 17. `certificates`
- **Candidate Keys:** `{id}`, `{certificate_number}`, `{(user_id, course_id)}`
- **Primary Key:** `{id}`
- **Functional Dependencies:**
  - $\text{id} \to \text{certificate\_number}, \text{user\_id}, \text{course\_id}, \text{issued\_at}, \text{verification\_hash}, \text{created\_at}, \text{updated\_at}$
  - $\text{certificate\_number} \to \text{id}, \text{user\_id}, \dots$
  - $\text{user\_id}, \text{course\_id} \to \text{id}, \text{certificate\_number}, \dots$
- **3NF Verification:** All determinants are superkeys.

#### 18. `announcements`
- **Candidate Keys:** `{id}`
- **Primary Key:** `{id}`
- **Functional Dependencies:**
  - $\text{id} \to \text{created\_by}, \text{title}, \text{content}, \text{target\_role}, \text{created\_at}, \text{updated\_at}$
- **3NF Verification:** Determinant `{id}` is a superkey.

---

## 6. Phase 4: Boyce-Codd Normal Form (BCNF) Analysis

### 6.1 Axiom of BCNF
> A relation $R$ is in **Boyce-Codd Normal Form (BCNF)** if and only if for every non-trivial functional dependency $X \to Y$ defined on $R$, **$X$ is a superkey of $R$**.  
> BCNF is stricter than 3NF because 3NF permits $X$ not to be a superkey if $Y$ consists of prime attributes; BCNF admits no such exception.

### 6.2 Rigorous BCNF Proof for CAPSERA Tables

To demonstrate that the CAPSERA schema strictly satisfies BCNF, we evaluate every relation possessing multiple overlapping candidate keys:

#### Case 1: `users`
- **Candidate Keys:** $K_1 = \{\text{id}\}$, $K_2 = \{\text{email}\}$
- **Dependencies:**
  - $\text{id} \to \text{Attributes} \setminus \{\text{id}\}$ (Valid: $\{\text{id}\}$ is a superkey)
  - $\text{email} \to \text{Attributes} \setminus \{\text{email}\}$ (Valid: $\{\text{email}\}$ is a superkey)
- **Conclusion:** No dependency exists where the left-hand determinant is not a superkey. **Holds in BCNF.**

#### Case 2: `trainee_profiles` & `trainer_profiles`
- **Candidate Keys:** $K_1 = \{\text{id}\}$, $K_2 = \{\text{user\_id}\}$
- **Dependencies:**
  - $\text{id} \to \text{Attributes}$ (Valid: $\{\text{id}\}$ is a superkey)
  - $\text{user\_id} \to \text{Attributes}$ (Valid: $\{\text{user\_id}\}$ has a `UNIQUE` constraint, making it a superkey)
- **Conclusion:** Both determinants are superkeys. **Holds in BCNF.**

#### Case 3: Associative Entities (`enrollments`, `trainee_skills`, `trainer_skills`, `feedback`)
- Consider `enrollments`:
  - $K_1 = \{\text{id}\}$ (Surrogate Identity Primary Key)
  - $K_2 = \{(\text{user\_id}, \text{course\_id})\}$ (Domain Candidate Key enforced via `UNIQUE (user_id, course_id)`)
- **Dependencies:**
  - $\text{id} \to \text{user\_id}, \text{course\_id}, \text{status}, \dots$
  - $\text{user\_id}, \text{course\_id} \to \text{id}, \text{status}, \dots$
- **Analysis:** Since both $\{\text{id}\}$ and $\{(\text{user\_id}, \text{course\_id})\}$ are candidate keys, every functional determinant in the relation is a superkey. No partial or non-superkey dependencies exist.
- **Conclusion:** **Holds in BCNF.**

#### Case 4: `certificates`
- **Candidate Keys:**
  - $K_1 = \{\text{id}\}$
  - $K_2 = \{\text{certificate\_number}\}$
  - $K_3 = \{(\text{user\_id}, \text{course\_id})\}$
- **Dependencies:**
  - $\text{id} \to \text{certificate\_number}, \text{user\_id}, \text{course\_id}, \text{issued\_at}, \dots$
  - $\text{certificate\_number} \to \text{id}, \text{user\_id}, \dots$
  - $\text{user\_id}, \text{course\_id} \to \text{id}, \text{certificate\_number}, \dots$
- **Analysis:** Every functional determinant is a superkey that uniquely identifies the certificate tuple.
- **Conclusion:** **Holds in BCNF.**

#### Case 5: `questions` & `lessons`
- In `lessons`:
  - $K_1 = \{\text{id}\}$
  - $K_2 = \{(\text{course\_id}, \text{lesson\_order})\}$ (Enforced via `UNIQUE (course_id, lesson_order)`)
- Determinants: Both $\{\text{id}\}$ and $\{(\text{course\_id}, \text{lesson\_order})\}$ uniquely determine all attributes.
- **Conclusion:** **Holds in BCNF.**

### 6.3 Theorem & Final Normal Form Finding
> **Theorem:** Because every relation in the CAPSERA schema has been decomposed such that all non-trivial functional dependencies have a candidate key (or superkey) on their left-hand side, **the entire 18-table schema is strictly in Boyce-Codd Normal Form (BCNF)** with **zero loss of functional dependencies** and **guaranteed lossless join decomposition**.

---

## 7. Summary Master Matrix

| # | Table Name | Canonical Domain Entity | Primary Key | Candidate Keys | Achieved Normal Form | Key Constraints & Invariants |
|---|---|---|---|---|:---:|---|
| 1 | `users` | User Identity | `id` | `{id}`, `{email}` | **BCNF** | `chk_users_role`, `chk_users_status`, `uq_users_email_ci` |
| 2 | `trainee_profiles` | Trainee Professional Details | `id` | `{id}`, `{user_id}` | **BCNF** | `UNIQUE(user_id)`, `FK -> users.id` |
| 3 | `trainer_profiles` | Trainer Expertise Details | `id` | `{id}`, `{user_id}` | **BCNF** | `UNIQUE(user_id)`, `FK -> users.id` |
| 4 | `skills` | Competency Skill Master | `id` | `{id}`, `{name}` | **BCNF** | `UNIQUE(name)` |
| 5 | `trainee_skills` | Trainee Skill Mapping | `id` | `{id}`, `{(user_id, skill_id)}` | **BCNF** | `UNIQUE(user_id, skill_id)`, `1 <= level <= 5` |
| 6 | `trainer_skills` | Trainer Skill Mapping | `id` | `{id}`, `{(user_id, skill_id)}` | **BCNF** | `UNIQUE(user_id, skill_id)` |
| 7 | `courses` | Course Master | `id` | `{id}` | **BCNF** | `FK -> users(trainer_id)`, `chk_courses_level` |
| 8 | `lessons` | Modular Course Lessons | `id` | `{id}`, `{(course_id, lesson_order)}` | **BCNF** | `UNIQUE(course_id, lesson_order)` |
| 9 | `learning_resources` | Study Media & Material | `id` | `{id}` | **BCNF** | `FK -> courses(id)`, `FK -> lessons(id)` |
| 10 | `enrollments` | Trainee Course Enrollment | `id` | `{id}`, `{(user_id, course_id)}` | **BCNF** | `UNIQUE(user_id, course_id)`, `0 <= progress <= 100` |
| 11 | `lesson_progress` | Lesson Completion Ledger | `id` | `{id}`, `{(enrollment_id, lesson_id)}` | **BCNF** | `UNIQUE(enrollment_id, lesson_id)` |
| 12 | `assessments` | MCQ Assessment Master | `id` | `{id}`, `{(course_id, title)}` | **BCNF** | `UNIQUE(course_id, title)`, `0 <= passing_score <= 100` |
| 13 | `questions` | Assessment Question Bank | `id` | `{id}`, `{(assessment_id, question_order)}` | **BCNF** | `UNIQUE(assessment_id, question_order)`, `points > 0` |
| 14 | `assessment_attempts` | Trainee Exam Attempt | `id` | `{id}` | **BCNF** | `FK -> assessments(id)`, `FK -> users(id)` |
| 15 | `attempt_answers` | Graded Question Answer | `id` | `{id}`, `{(attempt_id, question_id)}` | **BCNF** | `UNIQUE(attempt_id, question_id)` |
| 16 | `feedback` | Course Feedback Survey | `id` | `{id}`, `{(user_id, course_id)}` | **BCNF** | `UNIQUE(user_id, course_id)`, `1 <= rating <= 5` |
| 17 | `certificates` | Completion Credential | `id` | `{id}`, `{certificate_number}`, `{(user_id, course_id)}`| **BCNF** | `UNIQUE(certificate_number)`, `UNIQUE(user_id, course_id)` |
| 18 | `announcements` | System & Role Broadcasts | `id` | `{id}` | **BCNF** | `FK -> users(created_by)` |

---

## 8. Decomposition Proofs & Lossless Join Guarantee

### 8.1 Lossless Join Property
For any decomposed relation $R$ into $R_1$ and $R_2$, the decomposition is a **lossless join** if and only if:
$$R_1 \cap R_2 \to R_1 \quad \text{OR} \quad R_1 \cap R_2 \to R_2$$
In every decomposition performed above (e.g., separating `courses` and `enrollments`):
$$\text{courses} \cap \text{enrollments} = \{\text{course\_id}\}$$
Since $\text{course\_id}$ is the primary key of `courses`, $\text{course\_id} \to \text{courses}$ holds. Therefore, joining `courses` and `enrollments` on `course_id` reconstructs the original relation with **zero spurious tuples**.

### 8.2 Dependency Preservation
All functional dependencies identified in the initial business domain are enforced either directly within a single relation through `PRIMARY KEY` and `UNIQUE` constraints or across relations via `FOREIGN KEY` constraints. No inter-relational functional dependencies were lost during decomposition.
