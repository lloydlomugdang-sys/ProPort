// Central catalog consumed by PATCH validation and returned to the Flutter UI.
// Only programs evidenced in the existing GradPort code/requirements are listed.
export const PROFILE_OPTIONS = Object.freeze({
  programs: ['Bachelor of Science in Information Technology', 'Bachelor of Science in Computer Science'],
  yearLevels: ['1st Year', '2nd Year', '3rd Year', '4th Year'],
  school: 'New Era University',
});

export const profileOptionsSchema = {
  type: 'object', required: ['programs', 'yearLevels', 'school'], additionalProperties: false,
  properties: {
    programs: { type: 'array', items: { type: 'string' } },
    yearLevels: { type: 'array', items: { type: 'string' } },
    school: { type: 'string' },
  },
} as const;
