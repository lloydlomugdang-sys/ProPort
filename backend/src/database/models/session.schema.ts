import { Schema, type Types } from 'mongoose';

export interface Session {
  userId: Types.ObjectId;
  familyId: string;
  refreshTokenHash: string;
  deviceId?: string;
  deviceName?: string;
  userAgent?: string;
  expiresAt: Date;
  lastUsedAt?: Date;
  revokedAt?: Date;
  revokeReason?: string;
  replacedBySessionId?: Types.ObjectId;
  createdAt: Date;
  updatedAt: Date;
}

export const sessionSchema = new Schema<Session>(
  {
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    familyId: { type: String, required: true, trim: true, maxlength: 128 },
    refreshTokenHash: { type: String, required: true, select: false, maxlength: 128 },
    deviceId: { type: String, trim: true, maxlength: 200 },
    deviceName: { type: String, trim: true, maxlength: 200 },
    userAgent: { type: String, trim: true, maxlength: 1000 },
    expiresAt: { type: Date, required: true },
    lastUsedAt: { type: Date },
    revokedAt: { type: Date },
    revokeReason: { type: String, trim: true, maxlength: 100 },
    replacedBySessionId: { type: Schema.Types.ObjectId, ref: 'Session' },
  },
  { strict: 'throw', timestamps: true, versionKey: false },
);

sessionSchema.index(
  { refreshTokenHash: 1 },
  { unique: true, name: 'uniq_sessions_refresh_token_hash' },
);
sessionSchema.index({ userId: 1, revokedAt: 1 }, { name: 'idx_sessions_user_revoked' });
sessionSchema.index({ familyId: 1 }, { name: 'idx_sessions_family' });
sessionSchema.index({ expiresAt: 1 }, { expireAfterSeconds: 0, name: 'ttl_sessions_expires_at' });
