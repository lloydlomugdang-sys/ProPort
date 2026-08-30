import type { Connection } from 'mongoose';
import { REPORT_ANSWER_OPTIONS } from '../models/report-template.schema.js';
import { registerModels } from '../../infrastructure/database/model-registry.js';

export const COLLEGE_ENGAGEMENT_TEMPLATE_V1 = {
  key: 'college-engagement-v1',
  version: 1,
  title: 'The College Report',
  prompt: 'During the current school year, about how often have you done each of the following?',
  active: true,
  questions: [
    {
      key: 'contributed-to-class-discussions',
      text: 'Asked questions in class or contributed to class discussions',
      sortOrder: 10,
      options: [...REPORT_ANSWER_OPTIONS],
    },
    {
      key: 'made-class-presentation',
      text: 'Made a class presentation',
      sortOrder: 20,
      options: [...REPORT_ANSWER_OPTIONS],
    },
    {
      key: 'prepared-multiple-drafts',
      text: 'Prepared two or more drafts of a paper or assignment before turning it in',
      sortOrder: 30,
      options: [...REPORT_ANSWER_OPTIONS],
    },
    {
      key: 'integrated-multiple-sources',
      text: 'Worked on a paper or project that required integrating ideas or information from various sources',
      sortOrder: 40,
      options: [...REPORT_ANSWER_OPTIONS],
    },
    {
      key: 'unprepared-for-class',
      text: 'Came to class without completing readings or assignments',
      sortOrder: 50,
      options: [...REPORT_ANSWER_OPTIONS],
    },
    {
      key: 'worked-with-students-in-class',
      text: 'Worked with other students on projects during class',
      sortOrder: 60,
      options: [...REPORT_ANSWER_OPTIONS],
    },
  ],
} as const;

export async function seedReportTemplate(connection: Connection): Promise<void> {
  const { ReportTemplate } = registerModels(connection);
  await ReportTemplate.updateOne(
    {
      key: COLLEGE_ENGAGEMENT_TEMPLATE_V1.key,
      version: COLLEGE_ENGAGEMENT_TEMPLATE_V1.version,
    },
    { $setOnInsert: COLLEGE_ENGAGEMENT_TEMPLATE_V1 },
    { upsert: true },
  );
}
