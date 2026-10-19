import { crc32, deflateRawSync } from 'node:zlib';
import { randomUUID } from 'node:crypto';

/** Small, deterministic OPC ZIP writer. Only application-owned part names enter
 * this function; no ZIP reading, file paths, shell commands, or external links. */
export function docxZip(parts: ReadonlyMap<string, Buffer>): Buffer {
  const local: Buffer[] = [], central: Buffer[] = [];
  let offset = 0, directorySize = 0;
  for (const [path, bytes] of parts) {
    // PNG is already losslessly compressed. Store unchanged bytes instead of
    // allocating/recompressing every rendered page a second time.
    const method = path.endsWith('.png') ? 0 : 8;
    const name = Buffer.from(path), packed = method === 0 ? bytes : deflateRawSync(bytes), crc = crc32(bytes);
    const header = Buffer.alloc(30);
    header.writeUInt32LE(0x04034b50); header.writeUInt16LE(20, 4);
    header.writeUInt16LE(method, 8); header.writeUInt16LE(33, 12); // 1980-01-01
    header.writeUInt32LE(crc, 14); header.writeUInt32LE(packed.length, 18);
    header.writeUInt32LE(bytes.length, 22); header.writeUInt16LE(name.length, 26);
    local.push(header, name, packed);
    const entry = Buffer.alloc(46);
    entry.writeUInt32LE(0x02014b50); entry.writeUInt16LE(20, 4); entry.writeUInt16LE(20, 6);
    entry.writeUInt16LE(method, 10); entry.writeUInt16LE(33, 14);
    entry.writeUInt32LE(crc, 16); entry.writeUInt32LE(packed.length, 20);
    entry.writeUInt32LE(bytes.length, 24); entry.writeUInt16LE(name.length, 28);
    entry.writeUInt32LE(offset, 42);
    central.push(entry, name); directorySize += entry.length + name.length;
    offset += header.length + name.length + packed.length;
  }
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50); end.writeUInt16LE(parts.size, 8); end.writeUInt16LE(parts.size, 10);
  end.writeUInt32LE(directorySize, 12); end.writeUInt32LE(offset, 16);
  return Buffer.concat([...local, ...central, end]);
}

export const xml = (value: string): string => value
  .split('').filter((c) => {
    const n = c.charCodeAt(0);
    return n === 9 || n === 10 || n === 13 || (n >= 32 && n !== 0xfffe && n !== 0xffff);
  }).join('')
  .replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;')
  .replaceAll('"', '&quot;').replaceAll("'", '&apos;');
const W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const R = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
export const paragraph = (text: string, style = 'Normal', properties = ''): string =>
  `<w:p><w:pPr><w:pStyle w:val="${style}"/>${properties}</w:pPr><w:r>${text.split(/\r?\n/).map((line, i) => `${i ? '<w:br/>' : ''}<w:t xml:space="preserve">${xml(line)}</w:t>`).join('')}</w:r></w:p>`;
export const pageBreak = '<w:p><w:r><w:br w:type="page"/></w:r></w:p>';

/** Explicit fixed column geometry, expanding rows, repeating scale headers. */
export function questionnaireTable(rows: readonly (readonly string[])[], widths: readonly number[]): string {
  const rowXml = rows.map((cells, r) => `<w:tr><w:trPr><w:cantSplit/>${r === 0 ? '<w:tblHeader/>' : ''}</w:trPr>${cells.map((text, c) =>
    `<w:tc><w:tcPr><w:tcW w:w="${widths[c]}" w:type="dxa"/><w:vAlign w:val="center"/>${r === 0 ? '<w:shd w:fill="F2F2F2"/>' : ''}</w:tcPr>${paragraph(text, 'TableCell', c === 1 ? '' : '<w:jc w:val="center"/>')}</w:tc>`).join('')}</w:tr>`).join('');
  return `<w:tbl><w:tblPr><w:tblW w:w="8640" w:type="dxa"/><w:tblInd w:w="100" w:type="dxa"/><w:tblBorders>${['top','left','bottom','right','insideH','insideV'].map(side => `<w:${side} w:val="single" w:sz="4" w:color="666666"/>`).join('')}</w:tblBorders><w:tblLayout w:type="fixed"/><w:tblCellMar><w:top w:w="100" w:type="dxa"/><w:left w:w="100" w:type="dxa"/><w:bottom w:w="100" w:type="dxa"/><w:right w:w="100" w:type="dxa"/></w:tblCellMar></w:tblPr><w:tblGrid>${widths.map(w => `<w:gridCol w:w="${w}"/>`).join('')}</w:tblGrid>${rowXml}</w:tbl>`;
}

export class DocxPackage {
  readonly parts = new Map<string, Buffer>();
  private readonly relationships: string[] = [];
  private drawingId = 0;
  private imageId = 0;
  private readonly fonts: string[] = [];
  private readonly fontRelationships: string[] = [];

  /** OOXML's reversible font obfuscation, not encryption. OFL permits embedding. */
  font(bytes: Buffer, bold: boolean): void {
    const id = bold ? 'bold' : 'regular', guid = randomUUID().toUpperCase();
    const key = Buffer.from(guid.replaceAll('-', ''), 'hex').reverse();
    const data = Buffer.from(bytes);
    for (let i = 0; i < 32; i++) data[i] = data[i]! ^ key[i % 16]!;
    this.parts.set(`word/fonts/${id}.odttf`, data);
    this.fonts.push(`<w:embed${bold ? 'Bold' : 'Regular'} r:id="${id}" w:fontKey="{${guid}}" w:subsetted="false"/>`);
    this.fontRelationships.push(`<Relationship Id="${id}" Type="${R}/font" Target="fonts/${id}.odttf"/>`);
  }

  image(bytes: Buffer): string {
    const id = `image${++this.imageId}`;
    this.parts.set(`word/media/${id}.png`, bytes);
    this.relationships.push(`<Relationship Id="${id}" Type="${R}/image" Target="media/${id}.png"/>`);
    return id;
  }

  drawing(id: string, width: number, height: number, description: string): string {
    const drawingId = ++this.drawingId, cx = Math.round(width * 12700), cy = Math.round(height * 12700);
    return `<w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="${cx}" cy="${cy}"/><wp:docPr id="${drawingId}" name="Evidence ${drawingId}" descr="${xml(description)}"/><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic><pic:nvPicPr><pic:cNvPr id="${drawingId}" name="${id}"/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed="${id}"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="${cx}" cy="${cy}"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r>`;
  }

  finish(body: string): Buffer {
    const add = (name: string, value: string) => this.parts.set(name, Buffer.from(`<?xml version="1.0" encoding="UTF-8" standalone="yes"?>${value}`));
    add('word/document.xml', `<w:document xmlns:w="${W}" xmlns:r="${R}" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"><w:body>${body}<w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="2160" w:header="500" w:footer="500" w:gutter="0"/></w:sectPr></w:body></w:document>`);
    add('_rels/.rels', `<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="document" Type="${R}/officeDocument" Target="word/document.xml"/></Relationships>`);
    this.relationships.push(`<Relationship Id="fonts" Type="${R}/fontTable" Target="fontTable.xml"/>`);
    add('word/_rels/document.xml.rels', `<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="styles" Type="${R}/styles" Target="styles.xml"/>${this.relationships.join('')}</Relationships>`);
    add('word/fontTable.xml', `<w:fonts xmlns:w="${W}" xmlns:r="${R}"><w:font w:name="Noto Sans"><w:family w:val="swiss"/>${this.fonts.join('')}</w:font></w:fonts>`);
    add('word/_rels/fontTable.xml.rels', `<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">${this.fontRelationships.join('')}</Relationships>`);
    add('[Content_Types].xml', '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Default Extension="png" ContentType="image/png"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/></Types>');
    const types = this.parts.get('[Content_Types].xml')!.toString().replace('</Types>', '<Default Extension="odttf" ContentType="application/vnd.openxmlformats-officedocument.obfuscatedFont"/><Override PartName="/word/fontTable.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.fontTable+xml"/></Types>');
    this.parts.set('[Content_Types].xml', Buffer.from(types));
    const styles = [
      ['Normal', '<w:widowControl/><w:spacing w:after="120" w:line="360" w:lineRule="auto"/>', ''],
      ['Title', '<w:keepNext/><w:spacing w:before="240" w:after="240"/><w:jc w:val="center"/>', '<w:b/><w:sz w:val="32"/>'],
      ['Heading1', '<w:keepNext/><w:spacing w:before="240" w:after="160"/><w:outlineLvl w:val="0"/>', '<w:b/><w:sz w:val="28"/>'],
      ['Heading2', '<w:keepNext/><w:spacing w:before="160" w:after="120"/><w:outlineLvl w:val="1"/>', '<w:b/>'],
      ['Question', '<w:keepNext/><w:spacing w:before="160" w:after="80"/>', '<w:b/>'],
      ['Response', '<w:shd w:fill="F2F4F6"/><w:spacing w:after="160"/><w:ind w:left="240"/>', ''],
      ['TableCell', '<w:spacing w:before="0" w:after="0" w:line="320" w:lineRule="exact"/>', ''],
      ['TitleField', '<w:keepLines/><w:spacing w:before="0" w:after="100" w:line="360" w:lineRule="exact"/><w:jc w:val="center"/>', ''],
    ].map(([id, p, r]) => `<w:style w:type="paragraph" w:styleId="${id}"><w:name w:val="${id}"/>${id === 'Normal' ? '' : '<w:basedOn w:val="Normal"/>'}<w:pPr>${p}</w:pPr><w:rPr>${r}</w:rPr></w:style>`).join('');
    add('word/styles.xml', `<w:styles xmlns:w="${W}"><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Noto Sans" w:hAnsi="Noto Sans" w:cs="Noto Sans"/><w:sz w:val="24"/></w:rPr></w:rPrDefault></w:docDefaults>${styles}</w:styles>`);
    return docxZip(this.parts);
  }
}
