# StayFix iOS Resubmission Checklist

## Code changes in this build

- Raised Flutter/iOS build number to `1.0.0+16`.
- Enabled the iOS target for both `iPhone` and `iPad`.
- Added default support contact values in `.env`.
- Added a support page at `support/index.html`.

## Manual checks still required outside the repo

### Sign in with Apple

The App Review screenshot shows the Firebase-side Apple credential exchange failing after Apple authentication starts.
That usually means one of these settings is still wrong outside the app code:

1. In Apple Developer, confirm the app ID used by `com.rezzaky.stayfix` has `Sign In with Apple` enabled.
2. In App Store Connect, confirm the uploaded app uses the same bundle ID: `com.rezzaky.stayfix`.
3. In Firebase Authentication, confirm the `Apple` provider is enabled.
4. In Firebase Authentication, confirm the Apple provider has the correct:
   - Service ID
   - Team ID
   - Key ID
   - Private key `.p8`
5. In Apple Developer, confirm the Service ID return URL matches Firebase's Apple callback URL.
6. Test on a real iPad with a fresh Apple ID path:
   - uninstall old build
   - install the new build
   - open registration
   - tap `Continuer avec Apple`
   - verify both first-time and returning Apple sign-in

### App Store Connect Support URL

Apple rejected the current Support URL because it points to an account deletion page instead of a support/help page.

Update the Support URL in App Store Connect to a page that includes:

- support email
- help/contact wording
- account help / sign-in help information

Suggested URL after deployment:

- `https://stayfix-accountdeletion.netlify.app/support/`

Only use that URL if the support page is actually deployed and publicly reachable.
