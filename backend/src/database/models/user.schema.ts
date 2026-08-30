import { Schema } from 'mongoose';

export const USER_STATUSES = ['pendingVerification', 'active', 'disabled'] as const;
export type UserStatus = (typeof USER_STATUSES)[number];

export interface User {
  email: string;
  passwordHash: string;
  firstName: string;
  lastName: string;
  program: string;
  yearLevel: string;
  school: string;
  avatarObjectKey?: string;
  avatarMimeType?: string;
  status: UserStatus;
  emailVerifiedAt?: Date;
  lastLoginAt?: Date;
  createdAt: Date;
  updatedAt: Date;
}

export const userSchema = new Schema<User>(
  {
    email: { type: String, required: true, lowercase: true, trim: true, maxlength: 320 },
    passwordHash: { type: String, required: true, select: false },
    firstName: { type: String, required: true, trim: true, minlength: 2, maxlength: 100 },
    lastName: { type: String, required: true, trim: true, minlength: 2, maxlength: 100 },
    program: { type: String, default: '', trim: true, maxlength: 200 },
    yearLevel: { type: String, default: '', trim: true, maxlength: 50 },
    school: { type: String, default: '', trim: true, maxlength: 200 },
    avatarObjectKey: { type: String, trim: true, maxlength: 1024 },
    avatarMimeType: { type: String, trim: true, maxlength: 100 },
    status: { type: String, enum: USER_STATUSES, default: 'pendingVerification', required: true },
    emailVerifiedAt: { type: Date },
    lastLoginAt: { type: Date },
  },
  { strict: 'throw', timestamps: true, versionKey: false },
);

userSchema.index({ email: 1 }, { unique: true, name: 'uniq_users_email' });
