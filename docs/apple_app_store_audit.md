# Stayfix iOS App Store Audit

Reviewed against the Apple App Review Guidelines the user supplied on February 6, 2026.

## Must Fix Before Submission

- `4.8 Login Services`
  - Added `Sign in with Apple` alongside Google sign-in for primary account access.
- `5.1.1(v) Account Sign-In`
  - Added an in-app privacy policy page and direct in-settings account deletion actions.
- `2.5.2 / 1.6 Data Security`
  - Hardened iOS media transport so App Store builds require HTTPS media endpoints.
- `1.2 / 1.5 / 5.1`
  - Added a chat abuse-report flow that sends conversation reports to Firestore for review.

## Still Risky / Requires Product Decision

- `1.6 Data Security`
  - Some account-creation flows still depend on temporary passwords and legacy password handling.
  - This was left intact to preserve the existing role-creation and email-delivery behavior requested by the user.
- `5.1.1(i) Privacy Policy`
  - The app now exposes an in-app policy page. Production support contact values should still be configured through environment values:
    - `STAYFIX_SUPPORT_URL`
    - `STAYFIX_SUPPORT_EMAIL`
- `2.1 App Completeness`
  - App Review demo credentials and review notes still need to be prepared in App Store Connect.

## Files Changed For Compliance

- `lib/providers/hotel_provider.dart`
- `lib/screens/auth_screen.dart`
- `lib/screens/privacy_account_center_screen.dart`
- `lib/screens/profile_screen.dart`
- `lib/screens/villa_profile_screen.dart`
- `lib/screens/immeuble_profile_screen.dart`
- `lib/screens/condu_profile_screen.dart`
- `lib/services/vps_media_service.dart`
- `ios/Runner/Runner.entitlements`
- `ios/Runner.xcodeproj/project.pbxproj`

## Verification Goal

These changes are intended to reduce App Review risk without changing the existing role-creation workflow or the current post-creation email behavior.
