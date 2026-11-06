#!/usr/bin/env python3
"""Build Android machine-translation drafts locally; never contacts a translation service.

Requires the optional runtime used by scripts/localization/complete_runtime_catalogs.py.
Download an M2M100 model separately, then pass its local directory. Existing entries
are preserved; complete locales are checkpointed. Human linguistic review is separate.
"""
from __future__ import annotations
import argparse
import json
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'scripts/localization'))
import complete_runtime_catalogs as offline


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--model',type=Path,required=True)
    parser.add_argument('--sources',type=Path,required=True)
    parser.add_argument('--output',type=Path,default=ROOT/'apps/android/localization/android-strings.json')
    parser.add_argument('--locales',nargs='*',default=[x for x in offline.RUNTIME_LOCALES if x!='en'])
    parser.add_argument('--batch-size',type=int,default=16)
    args=parser.parse_args()
    if not args.model.is_dir(): parser.error('A separately downloaded local model directory is required')
    os.environ['HF_HUB_OFFLINE']='1';os.environ['TRANSFORMERS_OFFLINE']='1'
    import torch
    from transformers import M2M100Tokenizer,M2M100ForConditionalGeneration
    from opencc import OpenCC
    sources=sorted(set(json.loads(args.sources.read_text())))
    data=json.loads(args.output.read_text()) if args.output.exists() else {
        'schemaVersion':1,'sourceLanguage':'en','reviewStatus':'requires-human-review',
        'provenance':{'method':'offline-machine-translation','model':'facebook/m2m100_1.2B','humanApproved':False},'strings':{}}
    device=offline.choose_device('auto')
    print('Loading local model on',device,flush=True)
    tokenizer=M2M100Tokenizer.from_pretrained(str(args.model),local_files_only=True)
    model=M2M100ForConditionalGeneration.from_pretrained(str(args.model),local_files_only=True).to(device).eval()
    if device=='mps':model.half()
    def save():
        args.output.parent.mkdir(parents=True,exist_ok=True)
        temporary=args.output.with_suffix('.tmp')
        temporary.write_text(json.dumps(data,ensure_ascii=False,indent=2,sort_keys=True)+'\n');temporary.replace(args.output)
    for locale in args.locales:
        pending=[]
        for source in sources:
            entry=data['strings'].setdefault(source,{})
            if locale in entry:continue
            if locale=='zh-Hant' and 'zh-Hans' in entry:
                entry[locale]=OpenCC('s2t').convert(entry['zh-Hans']);continue
            value=offline.reviewed_override(source,locale) or offline.glossary_value(source,locale)
            if value is not None or offline.technical_only(source):entry[locale]=value or source
            else:pending.append(source)
        # Batch unique natural-language spans across the whole locale. This avoids
        # repeatedly translating identical fragments around protected technical tokens.
        import re
        plans={}; natural=set()
        for source in pending:
            parts=[]; cursor=0
            for match in offline.PROTECTED_PATTERN.finditer(source):
                if match.start()>cursor:parts.append((source[cursor:match.start()],True))
                parts.append((match.group(),False));cursor=match.end()
            if cursor<len(source):parts.append((source[cursor:],True))
            plan=[]
            for piece,translate in parts:
                leading=re.match(r'^\s*',piece).group();trailing=re.search(r'\s*$',piece).group()
                core=piece[len(leading):len(piece)-len(trailing) if trailing else len(piece)]
                if translate and re.search(r'[^\W\d_]',core,re.UNICODE):
                    clauses=re.findall(r'.*?(?:[.!?](?=\s|$)|$)',piece,re.DOTALL)
                    for clause in clauses:
                        if not clause:continue
                        left=re.match(r'^\s*',clause).group();right=re.search(r'\s*$',clause).group()
                        text=clause[len(left):len(clause)-len(right) if right else len(clause)]
                        if text and re.search(r'[^\W\d_]',text,re.UNICODE):
                            plan.append((text,left,right));natural.add(text)
                        else:plan.append((None,clause,''))
                else:plan.append((None,piece,''))
            plans[source]=plan
        cache_path=Path('/tmp/vox-android-translation-segments-large')/(locale+'.json')
        cache_path.parent.mkdir(parents=True,exist_ok=True)
        translated=json.loads(cache_path.read_text()) if cache_path.exists() else {}
        natural=sorted(natural-set(translated),key=len)
        print(locale,'missing phrases',len(pending),'unique spans',len(natural),flush=True)
        for offset in range(0,len(natural),args.batch_size):
            batch=natural[offset:offset+args.batch_size]
            def context(text):
                substitutions=[(r'\bdurable chunks\b','saved audio segments'),(r'\bdurable chunk\b','saved audio segment'),
                    (r'\battachments\b','attached files'),(r'\battachment\b','attached file'),(r'\bFilename\b','file name'),
                    (r'\bTemplate\b','pattern'),(r'\bcaptures\b','notes'),(r'\bcapture\b','note'),(r'\bHistory\b','app history')]
                for pattern,value in substitutions:text=re.sub(pattern,value,text,flags=re.IGNORECASE)
                return text
            outputs=offline.translate_batch(tokenizer,model,[context(x) for x in batch],offline.MODEL_LANGUAGE.get(locale,locale),device,2)
            translated.update(zip(batch,outputs))
            cache_path.write_text(json.dumps(translated,ensure_ascii=False))
            print(locale,min(offset+args.batch_size,len(natural)),'/',len(natural),flush=True)
        for source,plan in plans.items():
            value=''.join(left+translated[key]+right if key is not None else left for key,left,right in plan)
            offline.validate_preservation(source,value)
            data['strings'][source][locale]=value
        save()
    print('Saved',len(data['strings']),'source phrases',flush=True)

if __name__=='__main__':main()
