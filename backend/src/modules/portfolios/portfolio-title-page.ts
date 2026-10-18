import type { PortfolioExportInfo } from './portfolio-generator.service.js';

/** Replace this small presentation component when an approved school sample is supplied.
 * No inferred institutional header, seal, or student information belongs here.
 */
export function standardTitlePage(info: PortfolioExportInfo): readonly string[] {
  return [
    'ACADEMIC PORTFOLIO', 'Standard Title Page', '',
    'Full Name', info.fullName, '',
    'Year & Section', info.yearAndSection,
    'Schedule', info.schedule,
    "Instructor's Name", info.instructorName,
    'Course', info.course ?? '',
    'Course Code', info.courseCode ?? '',
    'Semester & Academic Year', info.semesterAndYear ?? '',
  ];
}
