# StayFix Job Messaging + VPS Media Skill

## Goal
This document explains the current StayFix Job messaging/media architecture so Codex can rebuild the same logic with another UI design without breaking the storage model.

## 1. Current architecture

### Chat data
- Firestore stores conversation metadata and message documents.
- VPS stores the actual binary media files:
  - profile photos
  - chat images
  - chat audio / voice notes
- Firestore stores only the media URLs, file IDs, waveform data, delivery state, and message metadata.

### Main Flutter files
- `lib/screens/manager_chat_thread_screen.dart`
- `lib/screens/manager_messages_screen.dart`
- `lib/services/manager_worker_contact_service.dart`
- `lib/services/vps_media_service.dart`
- `lib/screens/condu_profile_screen.dart`
- `lib/screens/villa_profile_screen.dart`

### VPS backend file
- `vps_media_server/src/server.js`

## 2. VPS media API

### Upload endpoint
- `POST /api/media/upload`

### Delete endpoint
- `POST /api/media/delete-many`

### Public files
- `GET /media/<folder>/<file>`

### Categories already used
- `profile-photo`
- `chat-image`
- `chat-audio`

### Current VPS response shape
```json
{
  "media": {
    "fileId": "uuid",
    "url": "http://159.89.98.134:8080/media/chat-image/xxx.jpg",
    "mimeType": "image/jpeg",
    "sizeBytes": 12345,
    "durationMs": 3200,
    "kind": "chat-audio"
  }
}
```

### Flutter normalization rule
- The app normalizes VPS URLs to the public host in `VpsMediaService`.
- Use `VpsMediaService.normalizeMediaUrlSync(...)` or `normalizeMediaUrl(...)`.

## 3. Firestore conversation model

### Collection
- `conversations`

### Conversation document fields
- `type`
- `title`
- `subtitle`
- `participants`
- `workerId`
- `managerId`
- `lastMessage`
- `lastMessageAt`
- `unreadBy`
- `createdAt`
- `createdBy`
- `isActive`
- `blockedBy`
- `mutedBy`
- `typingBy`
- `photoUrl`
- `systemBannerText`
- `systemBannerAt`

### Message subcollection
- `conversations/{conversationId}/messages`

### Message document fields
- `senderId`
- `text`
- `type`
- `createdAt`
- `fileIds`
- `imageUrl`
- `imageBase64`
- `imageMimeType`
- `imageWidth`
- `imageHeight`
- `imageSizeBytes`
- `imageName`
- `audioUrl`
- `audioDurationMs`
- `audioWaveform`
- `audioMimeType`
- `address`
- `latitude`
- `longitude`
- `deliveredTo`
- `seenBy`
- `seenAt`
- `reaction`
- `reactionByUserId`
- `reactionUpdatedAt`

## 4. Voice note logic

### Recording
- Record locally in Flutter.
- While recording, capture amplitude samples every ~90ms.
- Convert samples into small normalized waveform bars.
- Store those bars in `audioWaveform` on the message document.

### Sending
1. Record audio locally.
2. Upload the file to VPS using category `chat-audio`.
3. Save returned `fileId`, `url`, `mimeType`, `durationMs`.
4. Save message doc in Firestore with:
   - `audioUrl`
   - `audioDurationMs`
   - `audioWaveform`
   - `fileIds: [fileId]`

### Playback
- Prefer downloading the audio from VPS to a local temporary file first.
- Then play from local file with `DeviceFileSource`.
- This is more stable than streaming some Android emulator/device combinations directly from remote `.m4a`.
- Scrubbing uses the waveform tap position and converts it to target milliseconds.

## 5. Image message logic

### Sending
1. Pick image from camera or gallery.
2. Upload to VPS with category `chat-image`.
3. Save Firestore message with:
   - `imageUrl`
   - `imageMimeType`
   - `imageWidth`
   - `imageHeight`
   - `imageSizeBytes`
   - `imageName`
   - `fileIds`

### Display
- Always prefer `imageUrl`.
- Use `imageBase64` only as old fallback if legacy data still exists.

## 6. Profile photo logic

### Upload
- Upload profile images to VPS with category `profile-photo`.

### Save on Firestore user/profile docs
- `photoUrl`
- delete old base64 fields when possible:
  - `photoBase64`
  - `profilePhotoBase64`
  - `imageBase64`

### Display priority
Always resolve avatar display in this order:
1. `photoUrl`
2. `photoURL`
3. `profileImageUrl`
4. `profileImage`
5. `avatarUrl`
6. `avatar`
7. `imageUrl`
8. fallback base64
9. fallback initials

### Current helper
- `VpsMediaService.resolveProfileImageUrl(Map<String, dynamic> data)`

## 7. Realtime chat behaviors

### Typing
- Store typing state in conversation doc:
```json
{
  "typingBy": {
    "uidA": true,
    "uidB": false
  }
}
```

### Delivered / seen
- On send:
  - sender goes into `deliveredTo`
  - sender goes into `seenBy`
- When receiver opens thread:
  - add receiver UID to `deliveredTo`
  - add receiver UID to `seenBy`
  - set `seenAt`

### Reactions
- Store per message:
  - `reaction`
  - `reactionByUserId`
  - `reactionUpdatedAt`

Supported values:
- `thumbs_up`
- `heart`
- `check`
- `clap`
- `fire`
- `pin`

## 8. Clear chat logic

### Current behavior
1. Read all message docs in the conversation.
2. Collect all `fileIds`.
3. Delete all message docs in a Firestore batch.
4. Call VPS `delete-many` with collected `fileIds`.
5. Update conversation doc:
   - `lastMessage: ''`
   - `systemBannerText: 'History was cleared'`
   - `systemBannerAt: server timestamp`

## 9. Worker conversation opening logic

### Current file
- `lib/services/manager_worker_contact_service.dart`

### Rules
- Reuse an existing manager-worker conversation if found.
- If `blockedBy` contains manager UID, the worker is considered blocked.
- If manager unblocks:
  - remove manager UID from `blockedBy`
- If manager chooses a worker:
  - update conversation title/subtitle/photo
  - optionally show `systemBannerText`

## 10. Story system spec for StayFix Job

This part is for the future story feature.

### VPS folders
Create separate story folders:
- `story-image`
- `story-video`

### Firestore collection
- `stories`

### Story document fields
- `storyId`
- `ownerUid`
- `ownerName`
- `ownerPhotoUrl`
- `mediaUrl`
- `mediaMimeType`
- `fileId`
- `caption`
- `createdAt`
- `expiresAt`
- `viewedBy`
- `kind`
- `isActive`

Example:
```json
{
  "ownerUid": "worker_uid",
  "ownerName": "Symbol 2nf",
  "ownerPhotoUrl": "http://159.89.98.134/media/profile-photo/xxx.jpg",
  "mediaUrl": "http://159.89.98.134/media/story-image/xxx.jpg",
  "mediaMimeType": "image/jpeg",
  "fileId": "uuid",
  "caption": "",
  "createdAt": "server timestamp",
  "expiresAt": "server timestamp + 24h",
  "viewedBy": [],
  "kind": "story-image",
  "isActive": true
}
```

### TTL rule
- Story lifetime must be exactly 24 hours from creation.

### Expiration behavior
After 24 hours:
1. delete file from VPS
2. delete story metadata from Firestore, or mark inactive and remove later

### Recommended cleanup job on VPS
Run a scheduled cleanup every 5 or 10 minutes:
- scan Firestore stories where `expiresAt <= now`
- collect `fileId`
- delete binary files using same VPS delete flow
- delete the Firestore story docs

### Recommended implementation
- Add a Node cleanup job in `server.js` or a separate worker:
  - `cleanupExpiredStories()`
- Trigger with `setInterval(...)` on VPS
- Better option in production:
  - use `pm2` cron process or separate scheduled worker

## 11. Story upload flow

1. pick image/video
2. upload to VPS under `story-image` or `story-video`
3. create Firestore story doc with:
   - `mediaUrl`
   - `fileId`
   - `createdAt`
   - `expiresAt = now + 24h`
4. when loading stories in app:
   - only query active stories with `expiresAt > now`
   - sort by `createdAt desc`

## 12. Rules for a redesign

If Codex builds a completely different UI, keep these logic rules unchanged:
- media binaries stay on VPS
- message metadata stays in Firestore
- voice notes keep `audioWaveform`
- reactions remain on the message doc
- delivery/seen stay array-based
- worker profile images must prefer VPS `photoUrl`
- stories expire after 24 hours and are physically removed from VPS

## 13. Recommended next backend additions

### Add new categories in `server.js`
- `story-image`
- `story-video`

### Add validation
- story-image must be image mime
- story-video must be video mime

### Add metadata
- width / height for images
- duration for audio and videos

### Add cleanup endpoint or worker
- expired story sweep

## 14. Recommended app helper functions

### Media URL helpers
- keep using `VpsMediaService.normalizeMediaUrlSync`
- keep using `VpsMediaService.resolveProfileImageUrl`

### Avatar rendering helper
Codex should create a shared widget eventually:
- `StayFixAvatar`

Priority:
1. VPS URL
2. base64
3. initials

## 15. Do not break

- Do not move chat binaries back into Firestore base64.
- Do not use base64 for stories.
- Do not keep expired story files on VPS.
- Do not stream remote audio only if local caching playback is more stable.
- Do not rewrite whole conversation collections for reactions or read receipts.
- Update only the affected conversation or message document.
