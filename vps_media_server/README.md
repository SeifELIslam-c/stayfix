# Stayfix Media Server

Uploads and serves chat images, voice notes, and manager profile photos for Stayfix apps.

## Endpoints

- `GET /health`
- `POST /api/media/upload`
- `POST /api/media/delete-many`
- `GET /media/<folder>/<file>`
- `POST /api/email/invite`

## Auth

The Flutter app sends the Firebase ID token in `Authorization: Bearer <token>`.

Backend verifies it with `firebase-admin`. For quick testing only, you can set:

```bash
ALLOW_UNVERIFIED_UPLOADS=true
```

## Categories

- `profile-photo`
- `chat-image`
- `chat-audio`

## Storage

- files: `storage/media/...`
- metadata: `storage/meta/<fileId>.json`

This metadata is what lets you delete uploaded files later when a chat is deleted.

## Invite emails

The Flutter app already posts account-invite requests to a webhook. This server
can now send those emails through your cPanel mailbox.

### Required environment variables

```bash
INVITE_WEBHOOK_TOKEN=replace-with-a-long-random-token
SMTP_HOST=mail.stayfix.co
SMTP_PORT=465
SMTP_SECURE=true
SMTP_USER=_mainaccount@stayfix.co
SMTP_PASS=your-mailbox-password
SMTP_FROM="Stayfix <_mainaccount@stayfix.co>"
```

### Endpoint

`POST /api/email/invite`

Headers:

```bash
Authorization: Bearer <INVITE_WEBHOOK_TOKEN>
Content-Type: application/json
```

Body:

```json
{
  "queueDocId": "firestore-doc-id",
  "email": "manager@example.com",
  "fullName": "Manager Name",
  "username": "manager.login",
  "password": "temporary-password",
  "accountType": "manager",
  "propertyNames": ["Condo A", "Condo B"]
}
```

When Firebase Admin is configured, the server also updates
`outbound_emails/<queueDocId>` with `sent` or `failed` status.
