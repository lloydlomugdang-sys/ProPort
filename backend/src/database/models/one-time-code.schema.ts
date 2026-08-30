import { Schema, type Types } from 'mongoose';

export const ONE_TIME_CODE_TYPES = [
  'emailVerification',
  'passwordReset',
  'emailChange',
  'passwordResetGrant',
] as const;
export type OneTimeCodeType = (typeof ONE_TIME_CODE_TYPES)[number];

export interface OneTimeCode {
  userId: Types.ObjectId;
  type: OneTimeCodeType;
  targetEmail?: string;
  codeHash: string;
  attempts: number;
  expiresAt: Date;
  consumedAt?: Date;
  createdAt: Date;
  updatedAt: Date;
}

export const oneTimeCodeSchema = new Schema<OneTimeCode>(
  {
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    type: { type: String, enum: ONE_TIME_CODE_TYPES, required: true },
    targetEmail: { type: String, lowercase: true, trim: true, maxlength: 320 },
    codeHash: { type: String, required: true, select: false, maxlength: 128 },
    attempts: { type: Number, required: true, default: 0, min: 0, max: 100 },
    expiresAt: { type: Date, required: true },
    consumedAt: { type: Date },
  },
  { strict: 'throw', timestamps: true, versionKey: false },
);

oneTimeCodeSchema.index(
  { userId: 1, type: 1, consumedAt: 1 },
  { name: 'idx_one_time_codes_user_type_consumed' },
);
oneTimeCodeSchema.index(
  { expiresAt: 1 },
  { expireAfterSeconds: 0, name: 'ttl_one_time_codes_expires_at' },
);
