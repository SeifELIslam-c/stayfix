require('dotenv').config();

const cors = require('cors');
const express = require('express');
const fs = require('fs');
const fsp = require('fs/promises');
const helmet = require('helmet');
const morgan = require('morgan');
const multer = require('multer');
const path = require('path');
const crypto = require('crypto');
const admin = require('firebase-admin');

const app = express();
const port = Number(process.env.PORT || 8080);
const baseUrl = (process.env.BASE_URL || `http://159.89.98.134:${port}`).replace(/\/$/, '');
const allowUnverifiedUploads = process.env.ALLOW_UNVERIFIED_UPLOADS === 'true';
const serviceAccountPath = process.env.FIREBASE_SERVICE_ACCOUNT_PATH || './firebase-service-account.json';
const maxImageBytes = Number(process.env.MAX_IMAGE_MB || 15) * 1024 * 1024;
const maxAudioBytes = Number(process.env.MAX_AUDIO_MB || 20) * 1024 * 1024;

const rootDir = path.resolve(__dirname, '..');
const storageDir = path.join(rootDir, 'storage');
const mediaDir = path.join(storageDir, 'media');
const metaDir = path.join(storageDir, 'meta');

for (const dir of [storageDir, mediaDir, metaDir]) {
  fs.mkdirSync(dir, { recursive: true });
}

const serviceAccountFile = path.resolve(rootDir, serviceAccountPath);
if (fs.existsSync(serviceAccountFile)) {
  const serviceAccount = require(serviceAccountFile);
  if (!admin.apps.length) {
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
    });
  }
} else if (!allowUnverifiedUploads) {
  console.warn(`Firebase service account not found at ${serviceAccountFile}`);
}

app.use(helmet({
  crossOriginResourcePolicy: false,
}));
app.use(cors());
app.use(express.json({ limit: '2mb' }));
app.use(morgan('combined'));
app.use('/media', express.static(mediaDir, {
  maxAge: '7d',
  etag: true,
}));

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: Math.max(maxImageBytes, maxAudioBytes) },
});

async function verifyAuth(req, res, next) {
  if (allowUnverifiedUploads) {
    req.auth = { uid: req.header('X-User-Id') || 'dev-user' };
    return next();
  }

  if (!admin.apps.length) {
    return res.status(500).json({ error: 'firebase-admin not configured' });
  }

  const authHeader = req.header('Authorization') || '';
  const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : '';
  if (!token) {
    return res.status(401).json({ error: 'missing bearer token' });
  }

  try {
    const decoded = await admin.auth().verifyIdToken(token);
    req.auth = decoded;
    return next();
  } catch (error) {
    return res.status(401).json({ error: 'invalid token' });
  }
}

function safeFileName(originalName) {
  const ext = path.extname(originalName || '').toLowerCase();
  return `${Date.now()}_${crypto.randomUUID().replace(/-/g, '')}${ext}`;
}

function categoryFolder(category) {
  switch (category) {
    case 'profile-photo':
      return 'profile-photo';
    case 'chat-image':
      return 'chat-image';
    case 'chat-audio':
      return 'chat-audio';
    default:
      return 'misc';
  }
}

function validateUpload(category, file) {
  const mimeType = file.mimetype || 'application/octet-stream';
  const extension = path.extname(file.originalname || '').toLowerCase();
  const looksLikeImage = mimeType.startsWith('image/') ||
    ['.jpg', '.jpeg', '.png', '.webp', '.heic', '.heif'].includes(extension);
  const looksLikeAudio = mimeType.startsWith('audio/') ||
    ['.m4a', '.mp4', '.aac', '.wav', '.mp3', '.ogg', '.opus'].includes(extension);
  if (category === 'profile-photo' || category === 'chat-image') {
    if (!looksLikeImage) {
      throw new Error('Only image uploads are allowed for this category.');
    }
    if (file.size > maxImageBytes) {
      throw new Error(`Image exceeds ${process.env.MAX_IMAGE_MB || 15} MB limit.`);
    }
  }
  if (category === 'chat-audio') {
    if (!looksLikeAudio) {
      throw new Error('Only audio uploads are allowed for voice messages.');
    }
    if (file.size > maxAudioBytes) {
      throw new Error(`Audio exceeds ${process.env.MAX_AUDIO_MB || 20} MB limit.`);
    }
  }
}

async function writeMeta(fileId, meta) {
  await fsp.writeFile(
    path.join(metaDir, `${fileId}.json`),
    JSON.stringify(meta, null, 2),
    'utf8',
  );
}

async function readMeta(fileId) {
  const filePath = path.join(metaDir, `${fileId}.json`);
  const raw = await fsp.readFile(filePath, 'utf8');
  return JSON.parse(raw);
}

app.get('/health', (_, res) => {
  res.json({
    ok: true,
    service: 'stayfix-media-server',
    time: new Date().toISOString(),
  });
});

app.post('/api/media/upload', verifyAuth, upload.single('file'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ error: 'file is required' });
    }

    const category = `${req.body.category || 'misc'}`.trim();
    validateUpload(category, req.file);

    const fileId = crypto.randomUUID();
    const folder = categoryFolder(category);
    const folderPath = path.join(mediaDir, folder);
    await fsp.mkdir(folderPath, { recursive: true });

    const storedName = safeFileName(req.file.originalname);
    const absolutePath = path.join(folderPath, storedName);
    await fsp.writeFile(absolutePath, req.file.buffer);

    const relativePath = `${folder}/${storedName}`.replace(/\\/g, '/');
    const url = `${baseUrl}/media/${relativePath}`;
    const media = {
      fileId,
      url,
      mimeType: req.file.mimetype,
      sizeBytes: req.file.size,
      durationMs: req.body.durationMs ? Number(req.body.durationMs) : null,
      kind: category,
    };

    await writeMeta(fileId, {
      ...media,
      ownerUid: req.auth.uid,
      conversationId: req.body.conversationId || null,
      relativePath,
      createdAt: new Date().toISOString(),
    });

    return res.status(201).json({ media });
  } catch (error) {
    return res.status(400).json({ error: error.message || 'upload failed' });
  }
});

app.post('/api/media/delete-many', verifyAuth, async (req, res) => {
  const incoming = Array.isArray(req.body?.fileIds) ? req.body.fileIds : [];
  const fileIds = incoming
    .map((value) => `${value || ''}`.trim())
    .filter(Boolean);

  const deleted = [];
  const missing = [];
  const failed = [];

  for (const fileId of fileIds) {
    try {
      const meta = await readMeta(fileId);
      const absolutePath = path.join(mediaDir, meta.relativePath);
      await fsp.rm(absolutePath, { force: true });
      await fsp.rm(path.join(metaDir, `${fileId}.json`), { force: true });
      deleted.push(fileId);
    } catch (error) {
      if (error.code === 'ENOENT') {
        missing.push(fileId);
      } else {
        failed.push({ fileId, error: error.message || 'delete failed' });
      }
    }
  }

  res.json({ deleted, missing, failed });
});

app.listen(port, () => {
  console.log(`stayfix-media-server listening on ${baseUrl}`);
});
