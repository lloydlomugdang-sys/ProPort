import type { Connection } from 'mongoose';
import { registerModels } from '../../infrastructure/database/model-registry.js';

interface FolderSeed {
  readonly key: string;
  readonly name: string;
  readonly sortOrder: number;
  readonly active: true;
}

interface CategorySeed {
  readonly key: string;
  readonly name: string;
  readonly sortOrder: number;
  readonly active: true;
  readonly folders: readonly FolderSeed[];
}

export const CATEGORY_SEEDS: readonly CategorySeed[] = [
  {
    key: 'curriculum-vitae',
    name: 'Curriculum Vitae',
    sortOrder: 10,
    active: true,
    folders: [
      { key: 'creative-title', name: 'Creative Title', sortOrder: 10, active: true },
      { key: 'curriculum-vitae', name: 'Curriculum Vitae', sortOrder: 20, active: true },
    ],
  },
  {
    key: 'scholastic-record',
    name: 'Scholastic Record',
    sortOrder: 20,
    active: true,
    folders: [
      { key: 'creative-title', name: 'Creative Title', sortOrder: 10, active: true },
      {
        key: 'unofficial-tor-with-reflections',
        name: 'Unofficial TOR with Reflections',
        sortOrder: 20,
        active: true,
      },
    ],
  },
  {
    key: 'certificates',
    name: 'Certificates',
    sortOrder: 30,
    active: true,
    folders: [
      { key: 'creative-title', name: 'Creative Title', sortOrder: 10, active: true },
      { key: 'seminars', name: 'Seminars', sortOrder: 20, active: true },
      { key: 'other-seminars', name: 'Other Seminars', sortOrder: 30, active: true },
      { key: 'trainings', name: 'Trainings', sortOrder: 40, active: true },
    ],
  },
  {
    key: 'accomplishments',
    name: 'Accomplishments',
    sortOrder: 40,
    active: true,
    folders: [
      { key: 'creative-title', name: 'Creative Title', sortOrder: 10, active: true },
      { key: 'thesis-capstone', name: 'Thesis/Capstone', sortOrder: 20, active: true },
      { key: 'case-studies', name: 'Case Studies', sortOrder: 30, active: true },
      { key: 'projects', name: 'Projects', sortOrder: 40, active: true },
      { key: 'assessments', name: 'Assessments', sortOrder: 50, active: true },
    ],
  },
  {
    key: 'other-achievements',
    name: 'Other Achievements',
    sortOrder: 50,
    active: true,
    folders: [
      { key: 'creative-title', name: 'Creative Title', sortOrder: 10, active: true },
      { key: 'projects', name: 'Projects', sortOrder: 20, active: true },
    ],
  },
  {
    key: 'college-report',
    name: 'College Report',
    sortOrder: 60,
    active: true,
    folders: [{ key: 'college-report', name: 'College Report', sortOrder: 10, active: true }],
  },
] as const;

export async function seedDocumentCategories(connection: Connection): Promise<void> {
  const { DocumentCategory } = registerModels(connection);
  await DocumentCategory.bulkWrite(
    CATEGORY_SEEDS.map((category) => ({
      updateOne: {
        filter: { key: category.key },
        update: {
          $setOnInsert: {
            ...category,
            folders: category.folders.map((folder) => ({ ...folder })),
          },
        },
        upsert: true,
      },
    })),
    { ordered: true },
  );
}
