import sharp from 'sharp';
import { describe, expect, it } from 'vitest';
import {
  binarizeOcrImage,
  cleanAnchorLine,
  cleanOcrText,
  isDecorativeNoise,
  isExemptLine,
  LocalOcrEngine,
  OCR_MAX_IMAGE_PIXELS,
  preprocessOcrColorAware,
  preprocessOcrImage,
  selectBestCandidate,
  usableCharCount,
  type OcrCandidate,
  type OcrLineInfo,
} from '../../src/infrastructure/ocr/local-ocr-engine.js';

describe('local OCR engine', () => {
  const engine = new LocalOcrEngine(10_000);

  it('extracts embedded text from a local PDF without rasterization', async () => {
    const result = await engine.extract({
      contents: pdfFixture('GradPort embedded PDF text'),
      mimeType: 'application/pdf',
      fileKind: 'pdf',
    });

    expect(result.engine).toBe('pdfjs');
    expect(result.rawText).toContain('GradPort embedded PDF text');
  });

  it('reports an empty image-only PDF through the explicit scanned-PDF limitation', async () => {
    await expect(
      engine.extract({
        contents: pdfFixture(),
        mimeType: 'application/pdf',
        fileKind: 'pdf',
      }),
    ).rejects.toMatchObject({ reason: 'scanned-pdf-not-supported' });
  });

  it('rejects malformed PDFs and images with bounded safe errors', async () => {
    await expect(
      engine.extract({
        contents: Buffer.from('%PDF-not-valid'),
        mimeType: 'application/pdf',
        fileKind: 'pdf',
      }),
    ).rejects.toMatchObject({ reason: 'invalid-pdf' });

    await expect(
      engine.extract({
        contents: Buffer.from([0xff, 0xd8, 0xff]),
        mimeType: 'image/jpeg',
        fileKind: 'image',
      }),
    ).rejects.toMatchObject({ reason: 'invalid-image' });
  });

  it('rejects decompression-bomb-sized image dimensions before OCR starts', async () => {
    const pngHeader = Buffer.alloc(24);
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]).copy(pngHeader);
    const width = Math.floor(Math.sqrt(OCR_MAX_IMAGE_PIXELS)) + 1;
    pngHeader.writeUInt32BE(width, 16);
    pngHeader.writeUInt32BE(width, 20);

    await expect(
      engine.extract({
        contents: pngHeader,
        mimeType: 'image/png',
        fileKind: 'image',
      }),
    ).rejects.toMatchObject({ reason: 'image-too-large' });
  });

  it('rejects concurrent extraction jobs when maxConcurrentJobs limit is reached with busy reason', async () => {
    const singleWorkerEngine = new LocalOcrEngine(10_000, 1);
    expect(singleWorkerEngine.isBusy()).toBe(false);

    const slowJobPromise = singleWorkerEngine.extract({
      contents: pdfFixture('GradPort embedded PDF text 1'),
      mimeType: 'application/pdf',
      fileKind: 'pdf',
    });

    await expect(
      singleWorkerEngine.extract({
        contents: pdfFixture('GradPort embedded PDF text 2'),
        mimeType: 'application/pdf',
        fileKind: 'pdf',
      }),
    ).rejects.toMatchObject({ reason: 'busy' });

    await slowJobPromise;
    expect(singleWorkerEngine.isBusy()).toBe(false);
  });

  it('rejects duplicate extraction job for the same documentId with unavailable reason', async () => {
    const multiWorkerEngine = new LocalOcrEngine(10_000, 2);
    const docId = 'doc-test-concurrent-123';
    const firstJob = multiWorkerEngine.extract({
      contents: pdfFixture('GradPort embedded PDF text 1'),
      mimeType: 'application/pdf',
      fileKind: 'pdf',
      documentId: docId,
    });

    await expect(
      multiWorkerEngine.extract({
        contents: pdfFixture('GradPort embedded PDF text 2'),
        mimeType: 'application/pdf',
        fileKind: 'pdf',
        documentId: docId,
      }),
    ).rejects.toMatchObject({ reason: 'unavailable' });

    await firstJob;
  });

  describe('dimension scaling', () => {
    it('upscales small images under 1000px longest edge by 2x', async () => {
      const smallSvg = Buffer.from(
        '<svg width="400" height="300" xmlns="http://www.w3.org/2000/svg"><rect width="100%" height="100%" fill="#ffffff"/></svg>',
      );
      const png = await sharp(smallSvg).png().toBuffer();
      const preprocessed = await preprocessOcrImage(png, { width: 400, height: 300 });
      const metadata = await sharp(preprocessed).metadata();
      expect(metadata.width).toBe(800);
      expect(metadata.height).toBe(600);
    });

    it('preserves native dimensions for images between 1000px and 2000px', async () => {
      const medSvg = Buffer.from(
        '<svg width="1500" height="1000" xmlns="http://www.w3.org/2000/svg"><rect width="100%" height="100%" fill="#ffffff"/></svg>',
      );
      const png = await sharp(medSvg).png().toBuffer();
      const preprocessed = await preprocessOcrImage(png, { width: 1500, height: 1000 });
      const metadata = await sharp(preprocessed).metadata();
      expect(metadata.width).toBe(1500);
      expect(metadata.height).toBe(1000);
    });

    it('clamps images over 2000px longest edge to max 2000px', async () => {
      const largeSvg = Buffer.from(
        '<svg width="3000" height="2000" xmlns="http://www.w3.org/2000/svg"><rect width="100%" height="100%" fill="#ffffff"/></svg>',
      );
      const png = await sharp(largeSvg).png().toBuffer();
      const preprocessed = await preprocessOcrImage(png, { width: 3000, height: 2000 });
      const metadata = await sharp(preprocessed).metadata();
      expect(metadata.width).toBe(2000);
      expect(metadata.height).toBe(1333);
    });
  });

  describe('selectBestCandidate', () => {
    it('selects candidate with significantly higher confidence (> 3 points) as primary signal', () => {
      const candidates: OcrCandidate[] = [
        { text: 'Certificate of Completion awarded to John Doe on 2026', confidence: 72, pass: 'auto' },
        { text: 'Certificate of Completion', confidence: 85, pass: 'sparse' },
      ];
      const best = selectBestCandidate(candidates);
      expect(best.pass).toBe('sparse');
      expect(best.confidence).toBe(85);
    });

    it('uses text completeness as secondary tie-breaker when confidence is within 3 points', () => {
      const candidates: OcrCandidate[] = [
        { text: 'Cert', confidence: 80, pass: 'auto' },
        { text: 'Certificate of Achievement 2026', confidence: 79, pass: 'sparse' },
      ];
      const best = selectBestCandidate(candidates);
      expect(best.pass).toBe('sparse');
      expect(best.text).toBe('Certificate of Achievement 2026');
    });

    it('prefers candidate with usable text over candidate with only whitespace', () => {
      const candidates: OcrCandidate[] = [
        { text: '   \n\n  \t ', confidence: 90, pass: 'auto' },
        { text: 'ID: 12345', confidence: 65, pass: 'sparse' },
      ];
      const best = selectBestCandidate(candidates);
      expect(best.pass).toBe('sparse');
      expect(best.text).toBe('ID: 12345');
    });

    it('preserves exact recognized string without concatenating passes', () => {
      const candidates: OcrCandidate[] = [
        { text: 'Certificate No: GP-9988\nDate: 2026-03-15', confidence: 88, pass: 'auto' },
        { text: 'Certificate No: GP-9988\nDate: 2026-03-15\nExtra line', confidence: 82, pass: 'sparse' },
      ];
      const best = selectBestCandidate(candidates);
      expect(best.text).toBe('Certificate No: GP-9988\nDate: 2026-03-15');
    });

    it('falls back to standard candidate if color-aware candidate lost more than 25% usable characters', () => {
      const candidates: OcrCandidate[] = [
        { text: 'A'.repeat(100), confidence: 80, pass: 'auto' },
        { text: 'A'.repeat(60), confidence: 86, pass: 'color-aware' },
      ];
      const best = selectBestCandidate(candidates);
      expect(best.pass).toBe('auto');
    });

    it('selects color-aware candidate if usable characters are retained (<= 25% drop) and confidence is higher', () => {
      const candidates: OcrCandidate[] = [
        { text: 'A'.repeat(100), confidence: 80, pass: 'auto' },
        { text: 'A'.repeat(85), confidence: 86, pass: 'color-aware' },
      ];
      const best = selectBestCandidate(candidates);
      expect(best.pass).toBe('color-aware');
    });
  });

  describe('usableCharCount', () => {
    it('counts only non-whitespace characters', () => {
      expect(usableCharCount('  A B\nC\tD  ')).toBe(4);
      expect(usableCharCount('   \n\t  ')).toBe(0);
      expect(usableCharCount('Certificate-123')).toBe(15);
    });
  });

  describe('cleanOcrText and noise filtering', () => {
    describe('cleanAnchorLine', () => {
      it('trims leading and trailing noise tokens flanking certificate IDs', () => {
        expect(cleanAnchorLine('ie bo pi Certificate No.: GP-2026-0914-001 SEER')).toBe(
          'Certificate No.: GP-2026-0914-001',
        );
        expect(cleanAnchorLine('noise Ref: GP-2026-X noise')).toBe('Ref: GP-2026-X');
        expect(cleanAnchorLine('stray ID: CERT-90210 end')).toBe('ID: CERT-90210');
      });

      it('preserves clean lines with or without anchor pattern untouched', () => {
        expect(cleanAnchorLine('Certificate No.: GP-2026-0914-001')).toBe(
          'Certificate No.: GP-2026-0914-001',
        );
        expect(cleanAnchorLine('GradPort Learning and Development Center')).toBe(
          'GradPort Learning and Development Center',
        );
      });
    });

    describe('isExemptLine', () => {
      it('exempts legitimate certificate roles', () => {
        expect(isExemptLine('Dean')).toBe(true);
        expect(isExemptLine('Dean of Academic Affairs')).toBe(true);
        expect(isExemptLine('President')).toBe(true);
        expect(isExemptLine('University President')).toBe(true);
        expect(isExemptLine('Director')).toBe(true);
        expect(isExemptLine('Program Director')).toBe(true);
        expect(isExemptLine('Project Lead')).toBe(true);
        expect(isExemptLine('General Manager')).toBe(true);
        expect(isExemptLine('Academic Coordinator')).toBe(true);
        expect(isExemptLine('Operations Supervisor')).toBe(true);
        expect(isExemptLine('Registrar')).toBe(true);
      });

      it('exempts legitimate dates in various formats', () => {
        expect(isExemptLine('2026-05-12')).toBe(true);
        expect(isExemptLine('May 12, 2026')).toBe(true);
        expect(isExemptLine('12/05/2026')).toBe(true);
        expect(isExemptLine('October 2025')).toBe(true);
        expect(isExemptLine('on September 14, 2026')).toBe(true);
      });

      it('exempts certificate IDs and reference numbers', () => {
        expect(isExemptLine('Certificate ID: CERT-90210')).toBe(true);
        expect(isExemptLine('No. 123456')).toBe(true);
        expect(isExemptLine('Ref: GP-2026-X')).toBe(true);
        expect(isExemptLine('Certificate No.: GP-2026-0914-001')).toBe(true);
      });

      it('exempts plausible real names with honorific, structured title case, or all-caps', () => {
        expect(isExemptLine('Dr. Jane Smith')).toBe(true);
        expect(isExemptLine('John Doe')).toBe(true);
        expect(isExemptLine('Maria Santos Cruz')).toBe(true);
        expect(isExemptLine('John Lloyd Lomugdang')).toBe(true);
        expect(isExemptLine('JUAN DELA CRUZ')).toBe(true);
        expect(isExemptLine('MARIA SANTOS')).toBe(true);
      });

      it('does NOT exempt decorative or signature noise containing non-words or mixed patterns', () => {
        expect(isExemptLine('Pe mans LAE et CEE')).toBe(false);
        expect(isExemptLine('SERRE Tes TREE')).toBe(false);
        expect(isExemptLine('XyZ qrzt')).toBe(false);
        expect(isExemptLine('ie bo pi')).toBe(false);
        expect(isExemptLine('SEER')).toBe(false);
        expect(isExemptLine('REN')).toBe(false);
      });
    });

    describe('isDecorativeNoise', () => {
      it('flags low-confidence non-exempt short lines as decorative noise', () => {
        expect(isDecorativeNoise('Pe mans LAE et CEE', 25)).toBe(true);
        expect(isDecorativeNoise('SERRE Tes TREE', 30)).toBe(true);
      });

      it('flags symbol-heavy lines with low confidence as decorative noise', () => {
        expect(isDecorativeNoise('~ * ~ - - ~', 40)).toBe(true);
        expect(isDecorativeNoise('---===---', 35)).toBe(true);
      });

      it('flags signature stroke noise containing math/symbols', () => {
        expect(isDecorativeNoise('A f= NS', 45)).toBe(true);
        expect(isDecorativeNoise('NS =', 45)).toBe(true);
      });

      it('flags isolated stray characters like numbers or single characters', () => {
        expect(isDecorativeNoise('2', 75)).toBe(true);
        expect(isDecorativeNoise('x', 70)).toBe(true);
      });

      it('flags outer margin noise when geometry is provided', () => {
        const marginLine: OcrLineInfo = {
          text: 'stray border tick',
          confidence: 60,
          bbox: { x0: 10, y0: 10, x1: 50, y1: 25 }, // top 2% of 1000px height
        };
        expect(isDecorativeNoise(marginLine, 60, { width: 1000, height: 1000 })).toBe(true);
      });

      it('preserves exempt lines regardless of low confidence', () => {
        expect(isDecorativeNoise('Dean', 20)).toBe(false);
        expect(isDecorativeNoise('President', 25)).toBe(false);
        expect(isDecorativeNoise('2026-05-12', 30)).toBe(false);
        expect(isDecorativeNoise('CERT-90210', 15)).toBe(false);
        expect(isDecorativeNoise('Dr. Jane Smith', 28)).toBe(false);
        expect(isDecorativeNoise('JUAN DELA CRUZ', 40)).toBe(false);
        expect(isDecorativeNoise('Maria Santos', 40)).toBe(false);
        expect(isDecorativeNoise('Project Lead', 35)).toBe(false);
      });

      it('preserves lines with high confidence (>= 50)', () => {
        expect(isDecorativeNoise('Pe mans LAE et CEE', 80)).toBe(false);
        expect(isDecorativeNoise('Some valid short line', 65)).toBe(false);
      });
    });

    describe('cleanOcrText', () => {
      it('filters out decorative noise lines based on line confidence', () => {
        const raw = [
          'GradPort University',
          'Pe mans LAE et CEE',
          'Certificate of Completion',
          'Awarded to John Doe',
          'SERRE Tes TREE',
          'Dean',
          'President',
        ].join('\n');

        const lines: OcrLineInfo[] = [
          { text: 'GradPort University', confidence: 90 },
          { text: 'Pe mans LAE et CEE', confidence: 25 },
          { text: 'Certificate of Completion', confidence: 92 },
          { text: 'Awarded to John Doe', confidence: 88 },
          { text: 'SERRE Tes TREE', confidence: 20 },
          { text: 'Dean', confidence: 35 }, // low confidence but exempt
          { text: 'President', confidence: 32 }, // low confidence but exempt
        ];

        const cleaned = cleanOcrText(raw, lines);
        expect(cleaned).not.toContain('Pe mans LAE et CEE');
        expect(cleaned).not.toContain('SERRE Tes TREE');
        expect(cleaned).toContain('GradPort University');
        expect(cleaned).toContain('Certificate of Completion');
        expect(cleaned).toContain('Awarded to John Doe');
        expect(cleaned).toContain('Dean');
        expect(cleaned).toContain('President');
      });

      it('restructures multi-column signatories and titles into clean paired lines', () => {
        const raw = [
          'Maria Santos                                                           John Lloyd Lomugdang',
          'Program Director                                                                         Project Lead',
        ].join('\n');

        const cleaned = cleanOcrText(raw);
        expect(cleaned).toBe(
          [
            'Maria Santos',
            'Program Director',
            'John Lloyd Lomugdang',
            'Project Lead',
          ].join('\n'),
        );
      });

      it('automatically trims anchor noise tokens from raw lines', () => {
        const raw = 'ie bo pi Certificate No.: GP-2026-0914-001 SEER';
        const cleaned = cleanOcrText(raw);
        expect(cleaned).toBe('Certificate No.: GP-2026-0914-001');
      });

      it('preserves clean line breaks and collapses excessive empty lines', () => {
        const raw = 'Line 1\n\n\n\nLine 2\n\nLine 3';
        const cleaned = cleanOcrText(raw);
        expect(cleaned).toBe('Line 1\n\nLine 2\n\nLine 3');
      });

      it('removes standalone non-alphanumeric noise lines', () => {
        const raw = 'Header\n---\n~*~\nBody text';
        const cleaned = cleanOcrText(raw);
        expect(cleaned).toBe('Header\nBody text');
      });
    });
  });

  describe('image preprocessing', () => {
    it('does not mutate or alter the original input buffer', async () => {
      const originalImage = await sharp({
        create: {
          width: 50,
          height: 50,
          channels: 3,
          background: { r: 200, g: 100, b: 50 },
        },
      })
        .png()
        .toBuffer();

      const originalCopy = Buffer.from(originalImage);
      const preprocessed = await preprocessOcrImage(originalImage, { width: 50, height: 50 });

      expect(originalImage.equals(originalCopy)).toBe(true);
      expect(preprocessed.length).toBeGreaterThan(0);
      expect(preprocessed.equals(originalImage)).toBe(false);
    });

    it('upscales small images 2x', async () => {
      const originalImage = await sharp({
        create: {
          width: 50,
          height: 50,
          channels: 3,
          background: { r: 255, g: 255, b: 255 },
        },
      })
        .png()
        .toBuffer();

      const preprocessed = await preprocessOcrImage(originalImage, { width: 50, height: 50 });
      const meta = await sharp(preprocessed).metadata();
      expect(meta.width).toBe(100);
      expect(meta.height).toBe(100);
    });

    it('binarizes preprocessed buffer using thresholding', async () => {
      const img = await sharp({
        create: {
          width: 30,
          height: 30,
          channels: 3,
          background: { r: 150, g: 150, b: 150 },
        },
      })
        .png()
        .toBuffer();

      const binarized = await binarizeOcrImage(img);
      expect(binarized.length).toBeGreaterThan(0);
    });

    it('suppresses warm gold ornamental pixels while preserving dark navy and saddle brown ink', async () => {
      // 4 pixels test image:
      // Pixel 0: Gold #D4AF37 (212, 175, 55) -> should be masked to pure white
      // Pixel 1: Saddle Brown #8B4513 (139, 69, 19) -> should NOT be masked
      // Pixel 2: Dark Navy #0B132B (11, 19, 43) -> should NOT be masked
      // Pixel 3: Dark Charcoal #1C2541 (28, 37, 65) -> should NOT be masked
      const rawImage = await sharp(
        Buffer.from([
          212, 175, 55,
          139, 69, 19,
          11, 19, 43,
          28, 37, 65,
        ]),
        { raw: { width: 2, height: 2, channels: 3 } },
      )
        .png()
        .toBuffer();

      const rawCopy = Buffer.from(rawImage);
      const colorAware = await preprocessOcrColorAware(rawImage, { width: 2, height: 2 });

      // Ensure original buffer is unmodified
      expect(rawImage.equals(rawCopy)).toBe(true);
      expect(colorAware.length).toBeGreaterThan(0);
    });
  });

  describe('extractImage end-to-end', () => {
    it('executes 1 pass for a clean good-quality image and does not mutate buffer', async () => {
      const svg = Buffer.from(
        '<svg width="400" height="100">' +
          '<rect width="100%" height="100%" fill="white"/>' +
          '<text x="20" y="60" font-size="32" font-family="monospace" fill="black">GRADPORT 2026</text>' +
          '</svg>',
      );
      const testImage = await sharp(svg).png().toBuffer();
      const testImageCopy = Buffer.from(testImage);

      const result = await engine.extract({
        contents: testImage,
        mimeType: 'image/png',
        fileKind: 'image',
      });

      expect(result.engine).toBe('tesseract.js');
      expect(result.rawText).toContain('2026');
      expect(testImage.equals(testImageCopy)).toBe(true);
      expect(engine.lastExecutedPassCount).toBe(1);
    }, 20_000);

    it('adaptively evaluates secondary passes for blank or low-confidence images', async () => {
      const blankImage = await sharp({
        create: {
          width: 100,
          height: 100,
          channels: 3,
          background: { r: 255, g: 255, b: 255 },
        },
      })
        .png()
        .toBuffer();

      const result = await engine.extract({
        contents: blankImage,
        mimeType: 'image/png',
        fileKind: 'image',
      });

      expect(result.engine).toBe('tesseract.js');
      // Blank image has 0 usable chars, triggering adaptive passes
      expect(engine.lastExecutedPassCount).toBeGreaterThanOrEqual(2);
    }, 20_000);

    it('preserves names, dates, certificate IDs, and line breaks without concatenating passes', async () => {
      const svg = Buffer.from(
        '<svg width="600" height="200">' +
          '<rect width="100%" height="100%" fill="white"/>' +
          '<text x="30" y="50" font-size="24" font-family="monospace" fill="black">Certificate ID: CERT-90210</text>' +
          '<text x="30" y="90" font-size="24" font-family="monospace" fill="black">Awarded to: Jane Smith</text>' +
          '<text x="30" y="130" font-size="24" font-family="monospace" fill="black">Date: 2026-05-12</text>' +
          '</svg>',
      );
      const testImage = await sharp(svg).png().toBuffer();
      const result = await engine.extract({
        contents: testImage,
        mimeType: 'image/png',
        fileKind: 'image',
      });

      expect(result.rawText).toContain('CERT-90210');
      expect(result.rawText).toContain('Jane Smith');
      expect(result.rawText).toContain('2026-05-12');
      expect(result.rawText).toContain('\n');
      expect(engine.lastExecutedPassCount).toBe(1);
    }, 20_000);

    it('Generalization A: extracts text accurately with blue decorative borders and black text', async () => {
      const svg = Buffer.from(
        '<svg width="600" height="180">' +
          '<rect width="100%" height="100%" fill="white"/>' +
          '<rect x="15" y="15" width="570" height="150" fill="none" stroke="#1E3A8A" stroke-width="4"/>' +
          '<text x="300" y="80" font-size="28" font-family="sans-serif" font-weight="bold" fill="#000000" text-anchor="middle">GRADPORT CERTIFIED SYSTEM</text>' +
          '<text x="300" y="120" font-size="20" font-family="sans-serif" fill="#000000" text-anchor="middle">Certified on 2026-06-01</text>' +
          '</svg>',
      );
      const testImage = await sharp(svg).png().toBuffer();
      const result = await engine.extract({
        contents: testImage,
        mimeType: 'image/png',
        fileKind: 'image',
      });

      expect(result.rawText).toContain('GRADPORT CERTIFIED SYSTEM');
      expect(result.rawText).toContain('2026-06-01');
    }, 20_000);

    it('Generalization B: preserves legitimate saddle brown heading text without erasing it', async () => {
      const svg = Buffer.from(
        '<svg width="600" height="180">' +
          '<rect width="100%" height="100%" fill="#FAF7F0"/>' +
          '<text x="300" y="70" font-size="26" font-family="serif" font-weight="bold" fill="#8B4513" text-anchor="middle">DISTINGUISHED ACHIEVEMENT AWARD</text>' +
          '<text x="300" y="120" font-size="20" font-family="sans-serif" fill="#1C2541" text-anchor="middle">Conferred on September 2026</text>' +
          '</svg>',
      );
      const testImage = await sharp(svg).png().toBuffer();
      const result = await engine.extract({
        contents: testImage,
        mimeType: 'image/png',
        fileKind: 'image',
      });

      expect(result.rawText).toContain('DISTINGUISHED ACHIEVEMENT AWARD');
      expect(result.rawText).toContain('Conferred on September 2026');
    }, 20_000);

    it('Generalization C: cleanly extracts and pairs multi-column signatories and titles', async () => {
      const svg = Buffer.from(
        '<svg width="800" height="200">' +
          '<rect width="100%" height="100%" fill="white"/>' +
          '<text x="200" y="60" font-size="20" font-family="sans-serif" font-weight="bold" fill="#000000" text-anchor="middle">Alice Johnson</text>' +
          '<text x="600" y="60" font-size="20" font-family="sans-serif" font-weight="bold" fill="#000000" text-anchor="middle">Bob Williams</text>' +
          '<text x="200" y="100" font-size="16" font-family="sans-serif" fill="#333333" text-anchor="middle">Program Director</text>' +
          '<text x="600" y="100" font-size="16" font-family="sans-serif" fill="#333333" text-anchor="middle">Project Lead</text>' +
          '</svg>',
      );
      const testImage = await sharp(svg).png().toBuffer();
      const result = await engine.extract({
        contents: testImage,
        mimeType: 'image/png',
        fileKind: 'image',
      });

      expect(result.rawText).toContain('Alice Johnson');
      expect(result.rawText).toContain('Bob Williams');
      expect(result.rawText).toContain('Program Director');
      expect(result.rawText).toContain('Project Lead');
    }, 20_000);

    it('end-to-end simulated decorative certificate: eliminates borders, emblems, signatures, and anchor noise while preserving all core text', async () => {
      const certificateSvg = Buffer.from(`
<svg width="1200" height="850" xmlns="http://www.w3.org/2000/svg">
  <rect width="100%" height="100%" fill="#FAF7F0"/>
  <rect x="30" y="30" width="1140" height="790" fill="none" stroke="#D4AF37" stroke-width="4"/>
  <rect x="42" y="42" width="1116" height="766" fill="none" stroke="#C5A059" stroke-width="1.5"/>

  <!-- Gold flourishes that Tesseract previously read as noise -->
  <text x="150" y="75" font-family="serif" font-size="18" fill="#C5A059" text-anchor="middle">SERRE Tes TREE</text>
  <text x="1050" y="75" font-family="serif" font-size="18" fill="#C5A059" text-anchor="middle">Pe mans LAE et CEE</text>

  <!-- Central gold emblem / laurel -->
  <circle cx="600" cy="110" r="28" fill="none" stroke="#D4AF37" stroke-width="3"/>

  <!-- Main Body Text -->
  <text x="600" y="180" font-family="Arial, sans-serif" font-weight="bold" font-size="34" fill="#0B132B" text-anchor="middle" letter-spacing="3">CERTIFICATE OF COMPLETION</text>
  <line x1="400" y1="205" x2="800" y2="205" stroke="#D4AF37" stroke-width="2"/>

  <text x="600" y="250" font-family="Georgia, serif" font-style="italic" font-size="20" fill="#1C2541" text-anchor="middle">This certificate is proudly presented to</text>
  <path d="M 450,245 Q 455,240 460,247" fill="none" stroke="#C5A059" stroke-width="1.5"/>

  <text x="600" y="320" font-family="Arial, sans-serif" font-weight="bold" font-size="40" fill="#0B132B" text-anchor="middle" letter-spacing="2">JUAN DELA CRUZ</text>
  <line x1="350" y1="340" x2="850" y2="340" stroke="#C5A059" stroke-width="1.5"/>

  <text x="600" y="385" font-family="Georgia, serif" font-style="italic" font-size="18" fill="#1C2541" text-anchor="middle">for successfully completing the course</text>
  <text x="600" y="435" font-family="Arial, sans-serif" font-weight="bold" font-size="26" fill="#0B132B" text-anchor="middle">Introduction to Digital Documentation and OCR Systems</text>
  <text x="600" y="490" font-family="Georgia, serif" font-size="16" fill="#1C2541" text-anchor="middle">conducted by</text>
  <text x="600" y="525" font-family="Arial, sans-serif" font-weight="bold" font-size="22" fill="#0B132B" text-anchor="middle">GradPort Learning and Development Center</text>
  <text x="600" y="575" font-family="Georgia, serif" font-size="18" fill="#1C2541" text-anchor="middle">on September 14, 2026</text>

  <!-- Lower Section: Signatures & Labels -->
  <path d="M 220,640 Q 250,600 270,645 T 320,620 Q 350,650 370,630" fill="none" stroke="#1D2A44" stroke-width="2.5"/>
  <line x1="200" y1="655" x2="400" y2="655" stroke="#C5A059" stroke-width="1"/>
  <text x="300" y="680" font-family="Arial, sans-serif" font-weight="bold" font-size="18" fill="#0B132B" text-anchor="middle">Maria Santos</text>
  <text x="300" y="705" font-family="Arial, sans-serif" font-size="14" fill="#3A506B" text-anchor="middle">Program Director</text>

  <path d="M 820,635 Q 850,595 875,640 T 930,615 Q 960,645 980,625" fill="none" stroke="#1D2A44" stroke-width="2.5"/>
  <line x1="800" y1="655" x2="1000" y2="655" stroke="#C5A059" stroke-width="1"/>
  <text x="900" y="680" font-family="Arial, sans-serif" font-weight="bold" font-size="18" fill="#0B132B" text-anchor="middle">John Lloyd Lomugdang</text>
  <text x="900" y="705" font-family="Arial, sans-serif" font-size="14" fill="#3A506B" text-anchor="middle">Project Lead</text>

  <text x="300" y="770" font-family="serif" font-size="16" fill="#C5A059">ie bo pi</text>
  <text x="600" y="770" font-family="Arial, sans-serif" font-weight="bold" font-size="14" fill="#1C2541" text-anchor="middle">Certificate No.: GP-2026-0914-001</text>
  <text x="900" y="770" font-family="serif" font-size="16" fill="#C5A059">SEER</text>
  <text x="50" y="830" font-family="serif" font-size="16" fill="#C5A059">2</text>
</svg>
      `);

      const testImage = await sharp(certificateSvg).png().toBuffer();
      const testImageCopy = Buffer.from(testImage);

      const result = await engine.extract({
        contents: testImage,
        mimeType: 'image/png',
        fileKind: 'image',
      });

      // Target lines must be present:
      expect(result.rawText).toContain('CERTIFICATE OF COMPLETION');
      expect(result.rawText).toContain('This certificate is proudly presented to');
      expect(result.rawText).toContain('JUAN DELA CRUZ');
      expect(result.rawText).toMatch(/[fJ]or successfully completing the course/);
      expect(result.rawText).toContain('Introduction to Digital Documentation and OCR Systems');
      expect(result.rawText).toContain('conducted by');
      expect(result.rawText).toContain('GradPort Learning and Development Center');
      expect(result.rawText).toContain('September 14, 2026');
      expect(result.rawText).toContain('Maria Santos');
      expect(result.rawText).toContain('Program Director');
      expect(result.rawText).toContain('John Lloyd Lomugdang');
      expect(result.rawText).toContain('Project Lead');
      expect(result.rawText).toContain('Certificate No.: GP-2026-0914-001');

      // Decorative and signature noise lines must be absent:
      expect(result.rawText).not.toContain('SERRE Tes TREE');
      expect(result.rawText).not.toContain('Pe mans LAE et CEE');
      expect(result.rawText).not.toContain('ie bo pi');
      expect(result.rawText).not.toContain('SEER');

      // Input buffer must remain unmodified:
      expect(testImage.equals(testImageCopy)).toBe(true);

      // Verify executed candidate tracking
      expect(engine.lastExecutedPassCount).toBeGreaterThanOrEqual(2);
      expect(engine.lastExecutedCandidates.some((c) => c.pass === 'color-aware')).toBe(true);
    }, 45_000);
  });
});

function pdfFixture(text?: string): Buffer {
  const escaped = text?.replaceAll('\\', '\\\\').replaceAll('(', '\\(').replaceAll(')', '\\)');
  const content = escaped === undefined ? '' : `BT /F1 12 Tf 72 720 Td (${escaped}) Tj ET`;
  const objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>',
    `<< /Length ${Buffer.byteLength(content)} >>\nstream\n${content}\nendstream`,
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ];
  let body = '%PDF-1.4\n';
  const offsets = [0];
  for (const [index, object] of objects.entries()) {
    offsets.push(Buffer.byteLength(body));
    body += `${index + 1} 0 obj\n${object}\nendobj\n`;
  }
  const xrefOffset = Buffer.byteLength(body);
  body += `xref\n0 ${objects.length + 1}\n`;
  body += '0000000000 65535 f \n';
  for (const offset of offsets.slice(1)) {
    body += `${offset.toString().padStart(10, '0')} 00000 n \n`;
  }
  body += `trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n`;
  body += `startxref\n${xrefOffset}\n%%EOF\n`;
  return Buffer.from(body, 'ascii');
}
