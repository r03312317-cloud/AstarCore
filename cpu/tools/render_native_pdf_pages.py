from pathlib import Path
import importlib.util,json
from pypdf import PdfReader
r=Path(__file__).resolve().parents[1]
helper=Path('C:/Users/user/.codex/plugins/cache/openai-primary-runtime/documents/26.1026.10807/skills/documents/render_docx.py')
spec=importlib.util.spec_from_file_location('canonical_docx_renderer',helper);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
pdf=r/'verification/native_word/report.pdf'
assert pdf.exists()
def native_conversion(doc_path,user_profile,convert_tmp_dir,stem,verbose):
    return str(pdf),'Native Word ExportAsFixedFormat used after canonical CLI diagnosed missing LibreOffice. Original renderer file is unchanged.'
m.convert_to_pdf=native_conversion
out=r/'verification/rendered_final'
paths=m.rasterize(str(r/'docs/RV32_CPU架构与CoreMark性能分析.docx'),str(out),110,False,False)
pages=[]
reader=PdfReader(pdf)
for i,p in enumerate(reader.pages):
    text=p.extract_text();(out/f'page-{i+1}.txt').write_text(text,encoding='utf-8')
    pages.append({'page':i+1,'characters':len(text),'first':text.splitlines()[:5],'last':text.splitlines()[-5:]})
(r/'verification/render_layout.json').write_text(json.dumps({'conversion_backend':'isolated native Microsoft Word process, closed after export','raster_backend':str(helper),'canonical_cli_failure':'missing soffice.exe on PATH, recorded in renderer_cli.log','pages':pages,'images':paths},ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(pages,ensure_ascii=True,indent=2))
