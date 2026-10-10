/** Immutable transcription of Portfolio_LO-Questionnaire (1).pdf (all five pages).
 * IDs identify positions, not the source's irregular printed letters. Never edit
 * a released version in place; publish a new version for future revisions.
 */
export type ReportResponseType = 'choice' | 'range' | 'rating' | 'text';
export type OfficialAnswerValue = string | number | null;
export interface ReportOption { readonly value: string | number; readonly label: string }
export interface OfficialQuestion { readonly key: string; readonly label: string; readonly text: string }
export interface OfficialSection {
  readonly id: string; readonly label: string; readonly prompt: string;
  readonly responseType: ReportResponseType; readonly options: readonly ReportOption[];
  readonly questions: readonly OfficialQuestion[]; readonly note?: string;
}

const choices = (...entries: readonly (readonly [string | number, string])[]): ReportOption[] =>
  entries.map(([value, label]) => ({ value, label }));
const frequency = choices(['very_often', 'Very Often'], ['often', 'Often'], ['sometimes', 'Sometimes'], ['never', 'Never']);
const extent = choices(['very_much', 'Very much'], ['quite_a_bit', 'Quite a bit'], ['some', 'Some'], ['very_little', 'Very little']);
function section(
  number: number, prompt: string, responseType: ReportResponseType, options: readonly ReportOption[],
  questions: readonly (readonly [string, string])[], note?: string,
): OfficialSection {
  const id = `s${String(number).padStart(2, '0')}`;
  return { id, label: `${number}.`, prompt, responseType, options,
    questions: questions.map(([label, text], index) => ({ key: `${id}-q${String(index + 1).padStart(2, '0')}`, label, text })),
    ...(note === undefined ? {} : { note }),
  };
}

const examination = 'Mark the box that best represents the extent to which your examinations during the current school year have challenged you to do your best work.';
const experience = 'How would you evaluate your entire educational experience at this institution?';
const institution = 'If you could start over again, would you go to the same institution you are now attending?';

export const OFFICIAL_COLLEGE_REPORT = {
  key: 'college-report', version: 2, title: 'The College Report',
  instructions: 'Check your answers in the boxes.',
  source: 'Portfolio_LO-Questionnaire (1).pdf',
  reference: 'The College Student Report 2001. From the Carnegie Foundation for the Advancement of Teaching and Pew Forum on Undergraduate Education (2002).',
  sections: [
    section(1, 'During the current school year, about how often have you done each of the following?', 'choice', frequency, [
      ['a.', 'Asked questions in class or contributed to class discussions'],
      ['b.', 'Made a class presentation'],
      ['c.', 'Prepared two or more drafts of a paper or assignment before turning it in'],
      ['d.', 'Worked on a paper or project that required integrating ideas or information from various sources'],
      ['e.', 'Came to class without completing readings or assignments'],
      ['f.', 'Worked with other students on projects during class'],
      ['g.', 'Worked with classmates outside of class to prepare class assignments'],
      ['h.', 'Tutored or taught other students (paid or voluntary)'],
      ['i.', 'Participated in a community-based project as part of a regular course'],
      ['j.', 'Used an electronic medium (list-serv, chat group, Internet, etc.) to discuss or complete an assignment'],
      ['k.', 'Used e-mail to communicate with an instructor'],
      ['l.', 'Discussed grades or assignments with an instructor'],
      ['m', 'Talked about career plans with a faculty member or advisor'],
      ['n.', 'Discussed ideas from your reading or classes with faculty members outside of class'],
      ['o.', 'Received prompt feedback from faculty on your academic performance (written or oral)'],
      ['p.', "Worked harder than you thought you could to meet an instructor's standards or expectations Worked with faculty members on activities other than coursework (committees, orientation, student life activities, etc.)"],
      ['q.', 'Discussed ideas from your readings or classes with others outside of class (students, family members, coworkers, etc.'],
      ['r.', 'Had serious conversations with students of a different race or ethnicity than your own'],
      ['s.', 'Had serious conversations with students who differ from you in terms of their religious beliefs, political opinions, or personal values'],
    ]),
    section(2, 'During the current academic year, to what extent has your coursework emphasized the following mental activities?', 'choice',
      [...frequency.slice(0, 3), { value: 'once', label: 'Once' }], [
        ['a.', 'Memorizing facts, ideas, or methods from your courses and readings so you can repeat them in pretty much the same form'],
        ['b.', 'Analyzing the basic elements of an idea, experience, or theory such as examining a particular case or situation in depth and considering its components'],
        ['c.', 'Synthesizing and organizing ideas, information, or experiences into new, more complex interpretations and relationships'],
        ['d.', 'Making judgments about the value of information, arguments, or methods such as examining how others gathered and interpreted data and assessing the soundness of their conclusions'],
        ['e.', 'Applying theories or concepts to practical problems or in new situations'],
      ]),
    section(3, 'During the current academic year, about how much reading and writing have you done?', 'range',
      choices(['none', 'None'], ['1_4', '1 – 4'], ['5_10', '5 – 10'], ['11_20', '11–20'], ['over_20', '> 20']), [
        ['a.', 'Number of assigned textbooks, books, or book-length packs of course readings'],
        ['b.', 'Number of books read on your own (not assigned) for personal enjoyment or academic enrichment'],
        ['c.', 'Number of written papers or reports of 20 pages or more'],
        ['d.', 'Number of written papers or reports between 5 and 19 pages'],
        ['e.', 'Number of written papers or reports of fewer than 5 pages'],
      ]),
    section(4, examination, 'rating', [7, 6, 5, 4, 3, 2, 1].map((value) => ({ value, label: String(value) })), [['', examination]], '7: Very much; 1: Very little'),
    section(5, 'Which of the following have you done or you plan to do before you graduate from your institution?', 'choice',
      choices(['yes', 'Yes'], ['no', 'No'], ['undecided', 'Undecided']), [
        ['a.', 'Practicum, internship, field experience, co-op experience, or clinical assignment'],
        ['b.', 'Community service or volunteer work'],
        ['c.', 'Work on a research project with a faculty member outside of course or program requirements'],
        ['d.', 'Foreign language coursework'], ['e.', 'Study abroad'],
        ['f.', 'Independent study or self-designed major'],
        ['g.', 'Culminating senior experience (comprehensive exam, capstone course, thesis, project, etc.)'],
      ]),
    section(6, 'About how many hours do you spend in a typical 7-day week doing each of the following?', 'range',
      choices(['0', '0'], ['1_5', '1 – 5'], ['6_10', '6 – 10'], ['11_15', '11 – 15'], ['16_20', '16 – 20'], ['21_25', '21 – 25'], ['26_30', '26 – 30'], ['over_30', '>30']), [
        ['a.', 'Preparing for class (studying, reading, writing, rehearsing, and other activities related to your academic program)'],
        ['b.', 'Participating in co-curricular activities (organizations, campus publications, student government, social fraternity or sorority, intercollegiate or intramural sports, etc.)'],
        ['c.', 'Relaxing and socializing (watching TV, partying, exercising, playing computer and other games, etc.)'],
        ['d.', 'Providing care for dependents living with you (parents, children, spouse, etc.)'],
      ], 'No. of hours per week'),
    section(7, 'To what extent has your institution experience contributed to your knowledge, skills, and personal development in the following areas?', 'choice', extent, [
      ['a.', 'Acquiring a broad general education'], ['b.', 'Acquiring job or work-related knowledge and skills'],
      ['c.', 'Writing clearly and effectively'], ['d.', 'Speaking clearly and effectively'],
      ['e.', 'Thinking critically and analytically'], ['f.', 'Analyzing quantitative problems'],
      ['g.', 'Using computing and information technology'], ['h.', 'Working effectively with others'],
      ['i.', 'Voting in local, state, or national elections'], ['j.', 'Learning effectively on your own'],
      ['k.', 'Understanding yourself'], ['m', 'Understanding people of other racial and ethnic backgrounds'],
      ['n.', 'Developing a personal code of values and ethics'], ['o.', 'Contributing to the welfare of your community'],
    ]),
    section(8, 'To what extent does your institution emphasize each of the following?', 'choice', extent, [
      ['a.', 'Spending significant amounts of time studying and on academic work'],
      ['b.', 'Providing the support you need to help you succeed academicall'],
      ['c.', 'Encouraging contact among students from different economic, social, and racial or ethnic backgrounds'],
      ['d.', 'Helping you cope with your non-academic responsibilities (work, family, etc.)'],
      ['e.', 'Providing the support you need to thrive socially'],
    ]),
    section(9, experience, 'text', [], [['', experience]], 'The source provides blank response space, without a choice scale. Written response is optional.'),
    section(10, institution, 'text', [], [['', institution]], 'The source provides blank response space, without a choice scale. Written response is optional.'),
  ],
} as const;

export const OFFICIAL_QUESTIONS = OFFICIAL_COLLEGE_REPORT.sections.flatMap((section) =>
  section.questions.map((question) => ({ ...question, section })));
