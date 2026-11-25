# -*- coding: utf-8 -*-
from pathlib import Path
import json
root=Path(__file__).resolve().parents[2]/'app-store/2026-11-12'
folder=root/'text/paste-ready'
folder.mkdir(exist_ok=True)
for locale,source in [('zh-Hans','01-商店资料-简体中文.md'),('en-US','08-英文商店资料.md')]:
 text=(root/'text'/source).read_text()
 def field(prefix):
  return next(line[len(prefix):].strip() for line in text.splitlines() if line.startswith(prefix))
 if locale=='zh-Hans':
  data={'name':field('应用名称：'),'subtitle':field('副标题：'),'promotionalText':field('宣传文本：'),'keywords':field('关键词：')}
  data['description']=text.split('## 描述（复制本节正文）\n',1)[1].split('\n## 后台字段',1)[0].strip()
 else:
  data={'name':field('Name:'),'subtitle':field('Subtitle:'),'promotionalText':field('Promotional text:'),'keywords':field('Keywords:')}
  data['description']=text.split('## Description\n',1)[1].strip()
 assert data['name']=='PandaCCD'
 assert len(data['name'])<=30 and len(data['subtitle'])<=30
 assert len(data['promotionalText'])<=170
 assert len(data['keywords'].encode())<=100
 assert len(data['description'])<=4000
 data.update(copyright='2026 潘星霖',supportEmail='pan_xinglin@126.com',supportURL=None,privacyPolicyURL=None)
 (folder/f'{locale}.json').write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
 for key in ['name','subtitle','promotionalText','keywords','description']:
  (folder/f'{locale}-{key}.txt').write_text(data[key]+'\n')
 print(locale, 'metadata limits passed',len(data['description']))
