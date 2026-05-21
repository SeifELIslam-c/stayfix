# Stayfix Media Server

Uploads and serves chat images, voice notes, and manager profile photos for Stayfix apps.

## Endpoints

- `GET /health`
- `POST /api/media/upload`
- `POST /api/media/delete-many`
- `GET /media/<folder>/<file>`

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
