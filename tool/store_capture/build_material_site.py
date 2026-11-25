# -*- coding: utf-8 -*-
"""Build offline-ready support pages and the private handoff index."""
from pathlib import Path
import html
import re
import shutil
root=Path(__file__).resolve().parents[2]/'app-store/2026-11-12'
css='''*{box-sizing:border-box}body{margin:0;background:#f5f6f8;color:#202630;font:16px/1.85 -apple-system,BlinkMacSystemFont,"PingFang SC",sans-serif}header,main,footer{max-width:880px;margin:auto;padding:28px 26px}header{display:flex;gap:18px;align-items:center;border-bottom:1px solid #dce1e6}header img{width:48px;height:48px;border-radius:12px}header a{color:inherit;text-decoration:none}nav{margin-left:auto;display:flex;gap:20px;font-size:14px}main{padding-top:42px;padding-bottom:64px}h1{font-size:34px;line-height:1.35;letter-spacing:-.5px;margin:0 0 26px}h2{font-size:21px;line-height:1.5;margin:38px 0 12px}p{margin:0 0 18px}a{color:#3c566e;text-underline-offset:4px}ul,ol{padding-left:24px}table{width:100%;border-collapse:collapse;font-size:14px;background:white;margin:24px 0}td,th{padding:12px;border:1px solid #dce1e6;text-align:left;vertical-align:top}footer{border-top:1px solid #dce1e6;color:#677180;font-size:13px}.lead{color:#5c6672;font-size:19px}.grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:16px}.tile{display:block;padding:22px 24px;background:white;border:1px solid #e0e4ea;border-radius:14px;text-decoration:none;color:inherit}.tile b{display:block;font-size:19px}.tile small{color:#616d7b}.notice{padding:18px 22px;background:#fff;border-left:3px solid #b47768;margin:28px 0}.wide{max-width:1250px}.overview{width:100%;border:1px solid #e0e4ea;border-radius:14px}code{font-size:13px;overflow-wrap:anywhere}@media(max-width:600px){nav{gap:12px}header{padding:20px}h1{font-size:29px}.grid{grid-template-columns:1fr}table{display:block;overflow:auto}}'''
(root/'website/site.css').write_text(css)
shutil.copy2(root/'images/app-icon-1024.png',root/'website/icon.png')
def inline(s):
 s=html.escape(s)
 s=re.sub(r'(https://[^\s&lt;]+)',r'<a href="\1">\1</a>',s)
 return s

def markdown(source):
 lines=source.splitlines(); out=[]; paragraph=[]; table=[]
 def flush():
  if paragraph:out.append('<p>'+inline(' '.join(paragraph))+'</p>');paragraph.clear()
 def flush_table():
  if table:
   rows=[]
   for i,line in enumerate(table):
    cells=[v.strip() for v in line.strip('|').split('|')]
    if all(re.match(r'^:?-+:?$',c) for c in cells):continue
    tag='th' if i==0 else 'td'
    rows.append('<tr>'+''.join(f'<{tag}>'+inline(c)+f'</{tag}>' for c in cells)+'</tr>')
   out.append('<table>'+''.join(rows)+'</table>');table.clear()
 for l in lines+['']:
  if l.startswith('|'):
   flush();table.append(l);continue
  flush_table()
  if l.startswith('#'):
   flush();level=min(len(l)-len(l.lstrip('#')),3);out.append(f'<h{level}>'+inline(l.lstrip('# ').strip())+f'</h{level}>')
  elif not l.strip():flush()
  elif l.startswith('- '):flush();out.append('<p>• '+inline(l[2:])+'</p>')
  else:paragraph.append(l)
 return '\n'.join(out)

def page(title,content,folder='website'):
 return '<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>'+html.escape(title)+' · PandaCCD</title><link rel="stylesheet" href="site.css"><header><img src="icon.png" alt="PandaCCD"><a href="index.html"><b>PandaCCD</b></a><nav><a href="support.html">支持</a><a href="privacy.html">隐私</a><a href="terms.html">条款</a></nav></header><main>'+content+'</main><footer>© 2026 潘星霖 · <a href="mailto:pan_xinglin@126.com">pan_xinglin@126.com</a></footer></html>'
for input,name in [('02-隐私政策.md','privacy'),('03-支持与常见问题.md','support'),('04-用户协议.md','terms')]:
 (root/f'website/{name}.html').write_text(page(name,markdown((root/'text'/input).read_text())))
(root/'website/index.html').write_text(page('支持与隐私','''<p class="lead">一款在设备上处理的复古相机</p><h1>把喜欢的色彩，<br>留给眼前的日常。</h1><p>PandaCCD提供复古风格拍摄、Live动态照片、可调美颜、照片编辑和本地相册。</p><div class="grid"><a class="tile" href="support.html"><b>使用帮助</b><small>保存、Live、美颜与相册问题</small></a><a class="tile" href="privacy.html"><b>隐私政策</b><small>照片、声音和人脸轮廓如何处理</small></a><a class="tile" href="terms.html"><b>使用条款</b><small>使用范围与内容权利</small></a><a class="tile" href="mailto:pan_xinglin@126.com"><b>联系开发者</b><small>pan_xinglin@126.com</small></a></div><h2>反馈时，请告诉我们</h2><p>手机型号、系统版本、应用版本和操作步骤。截图或录屏请先遮盖私人内容。不要发送密码或验证码。</p>'''))
shutil.copy2(root/'website/site.css',root/'site.css')
links=''.join('<a class="tile" href="text/'+f.name+'"><b>'+html.escape(f.stem)+'</b><small>Markdown 文稿，可复制或交给上架人员</small></a>' for f in sorted((root/'text').glob('*.md')))
(root/'index.html').write_text('''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>PandaCCD · 上架材料</title><link rel="stylesheet" href="site.css"><main class="wide"><p class="lead">PandaCCD / APP STORE / 2026.11.12</p><h1>PandaCCD上架材料</h1><p>运营者：潘星霖 · pan_xinglin@126.com · 首发包含中国大陆</p><div class="notice">这是提交准备包，尚未提交审核。网站文件已完成但尚未部署；大陆区离线备案适用性需苹果确认，不能视为已获豁免。</div><img class="overview" src="images/store-overview.png" alt="五张iPhone商店截图预览"><h2>商店图片</h2><div class="grid"><a class="tile" href="screenshots/phone/01-camera.png"><b>iPhone · 5 张</b><small>1290 × 2796 PNG，screenshots/phone 文件夹</small></a><a class="tile" href="screenshots/ipad/01-camera.png"><b>iPad · 5 张</b><small>2064 × 2752 PNG，screenshots/ipad 文件夹</small></a><a class="tile" href="images/app-icon-1024.png"><b>正式图标</b><small>沿用当前应用版本的 1024 × 1024 图标</small></a><a class="tile" href="website/index.html"><b>支持与隐私网站</b><small>可直接部署的静态网页；不含追踪或外部字体</small></a></div><h2>文字材料</h2><div class="grid">'''+links+'''</div><h2>素材说明</h2><p>示例静物和成年合成人像由 GPT Image 生成。界面取自当前 Flutter 页面在 iOS 模拟器上的目标尺寸渲染，使用应用的真实 GLSL；相机输入由标注的示例图替代，不冒充真机实拍。没有用生图模型虚构界面或美颜对比。</p><p>发布前请补齐审核联系电话、确认价格与正式网址，并完成正式构建的隐私审计和真机验收。详见 README.md。</p></main></html>''')
print('Built 4 standalone website pages and material preview index')
