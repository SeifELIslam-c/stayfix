# StayFix Job Worker App Documentation

## Purpose
This app is the worker-side application for StayFix Job, built for hotel and property workers to create a profile, upload a CV, declare availability, and prepare their account to be reviewed later by employers or managers.

This file is documentation, not a prompt.

## Product Summary
- App name: `StayFix Job`
- Tech stack: Flutter mobile app + Firebase Auth + Cloud Firestore
- Secondary backend: Node/Express API for password reset email sending
- Main audience: workers / agents looking to be hired
- Future companion app: a manager/employer app that should browse and hire these workers

## Core Business Idea
Workers create a structured hiring profile. The profile is richer than a normal simple account and should be usable by a future manager-facing application.

Managers must be able to view at least:
- full name
- email
- phone
- address
- date of birth
- profile photo
- department
- specialties / roles
- years of experience
- CV PDF
- availability status
- weekly availability slots
- spoken languages
- work authorization
- criminal record answer
- referral status
- current work post information

## Current App Scope
The current app is mainly for workers. It includes:
- authentication
- terms acceptance
- role and specialty selection
- CV upload and privacy authorization
- personal profile editing
- address picker
- availability management
- absence toggle
- punch in / punch out history
- basic current-post info

Not fully implemented yet:
- offers section
- messages section
- manager hiring flow

## User Journey
1. User opens splash screen.
2. If not authenticated, user goes to auth.
3. If authenticated, device lock gate may require device authentication.
4. On first account creation, a `profiles/{uid}` document is created.
5. User must accept terms.
6. User must select a department and specialties.
7. User can complete profile details, upload CV, set address, set availability, and manage absence.

## Roles / Departments
The worker chooses one main department, then one or more specialties inside it.

### Departments currently defined
- Maintenance generale
- Main-d'oeuvre qualifiee
- Prepose aux chambres
- Houseman
- Concierge
- Menage

### Default specialties by department
`Maintenance generale`
- Bricolage
- Aide generale
- Jardinage / Jardinage paysager
- Peinture generale

`Main-d'oeuvre qualifiee`
- Plomberie professionnelle
- Electricite avancee
- Climatisation & chauffage
- Maconnerie professionnelle
- Menuiserie generale / Menuiserie
- Peinture decorative / Peinture professionnelle
- Soudure industrielle

`Prepose aux chambres`
- Nettoyage des chambres
- Gestion du linge
- Remise en etat des chambres

`Houseman`
- Transport bagages
- Entretien couloirs
- Soutien Housekeeping

`Concierge`
- Accueil clients
- Service information
- Gestion des bagages
- Reservations & services
- Assistance VIP

`Menage`
- Nettoyage des chambres
- Nettoyage espaces communs
- Gestion du linge
- Desinfection & hygiene
- Remise en etat des chambres

### Role rules
- One main department per worker
- Multiple specialties are allowed in most departments
- For `Main-d'oeuvre qualifiee`, the UI behaves like a single-skill path
- Workers can request a new custom role/specialty
- Custom roles go into `role_requests` and must be approved

## Firestore Data Model
The main database is Cloud Firestore.

### Collection: `profiles`
Document id = Firebase Auth `uid`

This is the main worker profile record and should be treated as the source of truth for the future manager app.

### `profiles` fields
| Field | Type | Meaning |
|---|---|---|
| `id` | string | user uid |
| `username` | string | worker full name / display name |
| `email` | string | account email |
| `phone` | string | full phone number, usually with country code |
| `phoneNational` | string | local phone number without full international formatting |
| `phoneCountryIso` | string | country ISO used in phone picker |
| `phoneDialCode` | string | country dialing code |
| `department` | string | main department |
| `specialties` | string[] | selected worker roles / specialties |
| `departmentExperienceYears` | number | years of experience for main department |
| `specialtyExperienceYears` | map<string, number> | reserved map for experience per specialty |
| `createdAt` | timestamp | account creation time |
| `termsAccepted` | bool | whether terms were accepted |
| `termsAcceptedAt` | timestamp | terms acceptance time |
| `termsAcceptedLanguage` | string | `fr` or `en` |
| `cvBase64` | string | uploaded PDF file stored directly in profile as base64 |
| `cvFileName` | string | CV filename |
| `cvReviewAuthorization` | bool | explicit authorization for CV review |
| `cvQuestionnaire` | map | answers linked to CV/privacy/work eligibility |
| `photoBase64` | string | profile photo stored as base64 |
| `address` | string | worker address |
| `dob` | string | date of birth, formatted for display |
| `speaksFrench` | bool | language flag |
| `speaksEnglish` | bool | language flag |
| `availableWeekDays` | number[] | weekdays the worker is available |
| `availabilitySlots` | object[] | detailed weekly availability |
| `permanentWorkDays` | number[] | legacy/alternative work-day storage, still read by app |
| `libreDays` | timestamp[] | free days / off days, legacy support in profile/calendar |
| `isAvailable` | bool | general absence toggle; true means available |
| `punches` | object[] | time clock history |
| `jobLocation` | string | current work location |
| `jobAddress` | string | current work address |
| `jobStartDate` | string | current work start date |

### Nested object: `cvQuestionnaire`
Known keys currently used:
- `privacyAccepted` : bool
- `submittedAt` : timestamp
- `referredByEmployee` : bool
- `referralEmployeeId` : string
- `authorizedToWorkCanada` : bool
- `isAdult` : bool
- `noCriminalRecord` : bool

This object is important for the future manager app because it contains hiring-related screening answers.

### Nested array: `availabilitySlots`
Each item represents one weekday rule.

Possible structure:
| Field | Type | Meaning |
|---|---|---|
| `weekday` | number | 1 to 7 |
| `allDay` | bool | true if available all day |
| `label` | string | display label |
| `fromHour` | number | 12-hour start hour |
| `fromMinute` | number | start minute |
| `fromPeriod` | string | `AM` or `PM` |
| `toHour` | number | 12-hour end hour |
| `toMinute` | number | end minute |
| `toPeriod` | string | `AM` or `PM` |

### Nested array: `punches`
Each item:
| Field | Type | Meaning |
|---|---|---|
| `type` | string | usually `Arrivee` or `Depart` |
| `time` | timestamp | time of punch |

### Collection: `role_requests`
Used when a worker asks admins to add a new role/specialty.

Fields observed:
| Field | Type | Meaning |
|---|---|---|
| `userId` | string | worker uid |
| `department` | string | department where the new role belongs |
| `requestedRole` | string | role name requested by worker |
| `status` | string | `pending`, `approved`, or `declined` |
| `createdAt` | timestamp | request creation date |
| `finalRole` | string | admin-approved final role label |
| `notified` | bool | whether worker was already notified in app |

## Authentication and Account Rules
- Firebase Auth is used
- Email/password signup and login are supported
- Google Sign-In is supported
- If a Google account has no password provider linked, the app creates and links a fallback password credential
- Password reset is handled by a custom backend endpoint

## Password Reset Backend
Node/Express server endpoint:
- `POST /api/password-reset`

Purpose:
- generate Firebase password reset link using Admin SDK
- send branded reset email through Resend

Required environment variables:
- `RESEND_API_KEY`
- `EMAIL_FROM`
- `FIREBASE_PROJECT_ID`
- `FIREBASE_CLIENT_EMAIL`
- `FIREBASE_PRIVATE_KEY`
- optional: `PASSWORD_RESET_CONTINUE_URL`
- optional: `ALLOWED_ORIGIN`

## Device Security
If the device supports local authentication, the app uses a device lock gate before reopening the remembered session.

Implication:
- session persistence exists on device
- unlocking may use biometrics, PIN, or device passcode

## Address and Location Handling
- Address selection uses Google Places / Geocoding
- API key is loaded from `.env` through `AppEnv`
- key name: `GOOGLE_MAPS_API_KEY`

Addresses are stored as plain text in:
- `address`
- `jobAddress`

## Important Product Rules for a Future Manager App
The future manager app should treat `profiles` as the candidate directory.

### Candidate card minimum fields
- `username`
- `photoBase64`
- `department`
- `specialties`
- `departmentExperienceYears`
- `address`
- `isAvailable`
- quick availability summary

### Candidate detail page minimum fields
- all candidate card fields
- `email`
- `phone`
- `dob`
- `cvFileName`
- `cvBase64`
- `cvReviewAuthorization`
- `cvQuestionnaire`
- `speaksFrench`
- `speaksEnglish`
- `jobLocation`
- `jobAddress`
- `jobStartDate`
- `punches` if operational history matters

### Useful manager filters
- department
- specialty
- years of experience
- address / city / region
- available now (`isAvailable`)
- available on weekday (`availableWeekDays`)
- has CV
- speaks French
- speaks English
- authorized to work in Canada
- no criminal record
- referred by employee

## Functional Screens in Current Worker App
- `AuthScreen`: login, register, Google sign-in, forgot password
- `TermsScreen`: terms acceptance in French or English
- `RoleSelectionScreen`: first-time department and specialty selection
- `HomeScreen`: main worker dashboard and current post summary
- `ProfileScreen`: main worker profile editor and viewer
- `CvPrivacyScreen`: CV upload + privacy authorization
- `SettingsScreen`: personal info, language flags, questionnaire answers
- `AvailabilityScreen`: weekly availability configuration
- `CalendarScreen`: calendar-oriented availability reading
- `AbsenceScreen`: toggle available vs on leave/travel
- `ClockScreen`: punch in / punch out history
- `OffersScreen`: placeholder / maintenance
- `MessagesScreen`: placeholder / maintenance

## Data Storage Notes
- Firestore is the main database
- CV files are not stored in Firebase Storage; they are stored directly inside Firestore as base64
- profile photos are also stored as base64
- this is simple but may become heavy at scale

## Known Architecture Limitations
- candidate documents are profile-centric and denormalized
- CV and photo storage inside Firestore documents may become expensive and large
- offers and messages are not ready
- there is no dedicated manager collection or hiring workflow yet
- specialty experience map exists but is not yet fully exploited in the current UI

## If Building the Future Manager App
Recommended interpretation:
- one `profiles` document = one hireable worker profile
- only show workers with accepted terms and a non-empty department
- prefer workers with CV, address, specialties, and experience completed
- support pending/approved custom roles from `role_requests`

Recommended next entities for the future manager app:
- `manager_accounts`
- `companies` or `hotels`
- `job_posts`
- `applications`
- `shortlists`
- `interviews`
- `messages`
- `hiring_decisions`

## Short AI Memory Summary
StayFix Job is a worker-profile app for hotel/property staffing. The core record is Firestore `profiles/{uid}`. Each worker has identity info, phone, address, DOB, department, specialties, department experience, CV, privacy/work-eligibility questionnaire, weekly availability, absence status, photo, and optional current job post data. New custom roles are requested through `role_requests`. The future manager app should read these worker profiles as candidate records for hiring.
