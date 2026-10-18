#!/usr/bin/env python3
"""Veya Mahjong original lightweight 2D art pipeline. Generates independent SVG + PNG assets."""
from __future__ import annotations
import os, sys, json, math, random, shutil, zipfile, csv, io, textwrap, subprocess, re, time
from pathlib import Path
from collections import Counter
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageEnhance
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
import cairosvg
import numpy as np

BASE=Path('/mnt/data/veya_work/VeyaMahjong_AssetPack_v1')
BASE.mkdir(parents=True,exist_ok=True)
C={"violet":"#765AC7","blue":"#379DD8","teal":"#49BDB7","rose":"#F4A3C7","gold":"#F4C568","navy":"#153D56","ivory":"#FFF8EC","green":"#20A878","lightgreen":"#75DA92","cream":"#FFF0D4"}
FONTS={
 'cjk':TTFont('/usr/share/fonts/opentype/noto/NotoSerifCJK-Regular.ttc',fontNumber=0),
 'serif':TTFont('/usr/share/fonts/truetype/dejavu/DejaVuSerif.ttf'),
 'sans':TTFont('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'),
}

def fontpaths(text:str, font:str='sans', size:float=36, x:float=0, y:float=0, fill:str='#17435F', anchor:str='middle', weight=1.0):
 """Outline text to paths: visual assets are font-independent; no fonts are distributed."""
 tt=FONTS[font]; cmap=tt.getBestCmap(); units=tt['head'].unitsPerEm
 widths=tt['hmtx'].metrics; gs=tt.getGlyphSet(); paths=[]; scale=size/units
 glyphs=[cmap.get(ord(c),'.notdef') for c in text]
 advance=sum(widths[g][0] for g in glyphs)*scale
 xx=x-advance/2 if anchor=='middle' else (x-advance if anchor=='end' else x)
 for g in glyphs:
  pen=SVGPathPen(gs); gs[g].draw(pen)
  d=pen.getCommands()
  if d:
   paths.append(f'<path d="{d}" fill="{fill}" transform="translate({xx:.3f},{y:.3f}) scale({scale:.6f},{-scale:.6f})"/>')
  xx+=widths[g][0]*scale
 return ''.join(paths)

def svg(w,h,body,extra=''):
 return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">
 <defs>
 <linearGradient id="ivory" x1="0" y1="0" x2="0.5" y2="1"><stop stop-color="#FFFDF7"/><stop offset=".69" stop-color="#FFF5E6"/><stop offset="1" stop-color="#F3DEC5"/></linearGradient>
 <linearGradient id="tileSide" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#F8DEB8"/><stop offset="1" stop-color="#D8B390"/></linearGradient>
 <linearGradient id="buttonGreen" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#91E996"/><stop offset=".47" stop-color="#37BC81"/><stop offset="1" stop-color="#198966"/></linearGradient>
 <linearGradient id="buttonBlue" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#9DE8FB"/><stop offset=".42" stop-color="#4BA8E9"/><stop offset="1" stop-color="#2478C1"/></linearGradient>
 <linearGradient id="buttonViolet" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#CCB2FF"/><stop offset=".5" stop-color="#9565E3"/><stop offset="1" stop-color="#6339C4"/></linearGradient>
 <linearGradient id="buttonGold" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#FFE7A1"/><stop offset=".48" stop-color="#FBC351"/><stop offset="1" stop-color="#D98D28"/></linearGradient>
 <linearGradient id="buttonRose" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#FFDFEB"/><stop offset=".5" stop-color="#F69CBC"/><stop offset="1" stop-color="#DC6C9B"/></linearGradient>
 <linearGradient id="panel" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#FFFDF6"/><stop offset="1" stop-color="#FBE8CB"/></linearGradient>
 <linearGradient id="gem" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#EEC9FF"/><stop offset=".43" stop-color="#A75DF4"/><stop offset="1" stop-color="#6243C3"/></linearGradient>
 <radialGradient id="glow"><stop stop-color="#FFF7A9" stop-opacity="1"/><stop offset=".45" stop-color="#FFD572" stop-opacity=".43"/><stop offset="1" stop-color="#FFEDAF" stop-opacity="0"/></radialGradient>
 <filter id="shadow" x="-35%" y="-35%" width="170%" height="190%"><feGaussianBlur stdDeviation="5"/></filter>
 {extra}</defs>{body}</svg>'''

def save_svg(rel,markup,png_sizes=None):
 path=BASE/rel; path.parent.mkdir(parents=True,exist_ok=True); path.write_text(markup,encoding='utf-8')
 if png_sizes:
  for name,(w,h) in png_sizes.items():
   out=path.with_name(path.stem+name+'.png')
   try:cairosvg.svg2png(bytestring=markup.encode(),write_to=str(out),output_width=w,output_height=h)
   except Exception as e: print('RENDER FAIL:',out,e)
 return path

def png_only(rel,svgtext,w,h):
 p=BASE/rel; p.parent.mkdir(parents=True,exist_ok=True)
 cairosvg.svg2png(bytestring=svgtext.encode(),write_to=str(p),output_width=w,output_height=h)
 return p

def star(cx,cy,r=40,inner=.48,fill='#FFCB55',stroke='#F39E23',rot=-math.pi/2):
 pts=[]
 for j in range(10):
  a=rot+j*math.pi/5; q=r if j%2==0 else r*inner
  pts.append(f'{cx+math.cos(a)*q:.2f},{cy+math.sin(a)*q:.2f}')
 return f'<polygon points="{" ".join(pts)}" fill="{fill}" stroke="{stroke}" stroke-width="{max(2,r*.09):.2f}" stroke-linejoin="round"/>'

def blossom(cx,cy,r=32,color='#F593BB',core='#FFDA70',rot=0):
 o=f'<g transform="translate({cx},{cy}) rotate({rot})">'
 for k in range(5):
  a=k*72
  o+=f'<ellipse cx="0" cy="{-r*.49:.2f}" rx="{r*.40:.2f}" ry="{r*.63:.2f}" transform="rotate({a})" fill="{color}" stroke="#F8D0DD" stroke-width="{max(1,r*.035):.2f}"/>'
 o+=f'<circle r="{r*.24:.2f}" fill="{core}" stroke="#FFE9A7" stroke-width="2"/></g>'
 return o

def leaf(cx,cy,s=30,rot=0,color='#4EAF77'):
 return f'<g transform="translate({cx},{cy}) rotate({rot})"><path d="M0 0 Q{-s*.9} {-s*.78} 0 {-s*1.7} Q{s*.9} {-s*.75} 0 0Z" fill="{color}" stroke="#35865D" stroke-width="{max(1,s*.045)}"/><path d="M0 0 L0 {-s*1.45}" stroke="#90D9A0" stroke-width="{max(1,s*.07)}"/></g>'

def cloud(x,y,scale=1,color='#FFFFFF',op=.8):
 return f'<g opacity="{op}" transform="translate({x},{y}) scale({scale})" fill="{color}"><ellipse cx="0" cy="8" rx="90" ry="25"/><circle cx="-35" cy="-8" r="35"/><circle cx="10" cy="-28" r="50"/><circle cx="62" cy="-5" r="34"/></g>'

def mountain(shift=0, color='#A8D5E1', y=920, h=480):
 return f'<path d="M-80 {y+160} L{shift+35} {y-80} L{shift+150} {y+25} L{shift+320} {y-h} L{shift+505} {y-130} L{shift+590} {y-240} L{shift+750} {y+60} L{shift+940} {y-325} L1200 {y+70} L1200 1500 L-90 1500 Z" fill="{color}"/>'

def bridge(x,y,s=1):
 return f'''<g transform="translate({x},{y}) scale({s})">
 <path d="M-210 70 Q0 -120 230 70 L230 105 Q0 -65 -210 105Z" fill="#C47D57" stroke="#89503A" stroke-width="9"/>
 <path d="M-212 47 Q0 -122 228 47" fill="none" stroke="#EAB08B" stroke-width="14" stroke-linecap="round"/>
 <path d="M-215 3 Q0 -166 234 3" fill="none" stroke="#805244" stroke-width="11" stroke-linecap="round"/>
 <path d="M-215 3 Q0 -166 234 3" fill="none" stroke="#F5C3A0" stroke-width="5"/>
 <path d="M-210 20 L-210 85 M-128 -60 L-128 12 M-40 -104 L-40 -39 M51 -100 L51 -39 M145 -60 L145 12 M229 20 L229 85" stroke="#81503E" stroke-width="12"/>
 <path d="M-210 20 L-210 85 M-128 -60 L-128 12 M-40 -104 L-40 -39 M51 -100 L51 -39 M145 -60 L145 12 M229 20 L229 85" stroke="#E5A880" stroke-width="5"/>
 </g>'''

def pagoda(x,y,s=1,color='#E7A16B',roof='#315578',night=False):
 win='#FFDF8A' if night else '#FFF2CF'
 return f'''<g transform="translate({x},{y}) scale({s})">
 <path d="M-98 -145 L98 -145 L85 25 L-85 25 Z" fill="{color}" stroke="#9D6A52" stroke-width="8"/>
 <rect x="-49" y="-93" width="98" height="118" rx="5" fill="{win}" stroke="#A97964" stroke-width="9"/>
 <path d="M-49 -93V25 M49 -93V25 M0 -93V25 M-49 -35H49" stroke="#754F49" stroke-width="8"/>
 <path d="M-145 -153 Q-90 -159 -64 -223 L60 -223 Q89 -160 145 -153 Q63 -114 -145 -153Z" fill="{roof}" stroke="#243B5B" stroke-width="8"/>
 <path d="M-65 -218 L0 -276 L65 -218Z" fill="{roof}" stroke="#213652" stroke-width="7"/>
 <circle cx="0" cy="-283" r="9" fill="#F9D56D"/>
 <path d="M-102 17H102 V35H-102Z" fill="#997252"/>
 </g>'''

def tree(x,y,s=1,pink=True):
 rng=random.Random(3322+int(x*3+y))
 colors= ['#F4A7CB','#ED82B7','#FFC1DA','#F8BCD3','#F08AB6'] if pink else ['#64BB78','#7ACA78','#93CE76','#53A66F']
 b=f'<g transform="translate({x},{y}) scale({s})"><path d="M-23 4 Q-40 -115 -76 -167 M-8 -78 Q43 -120 65 -196 M-12 0 Q-5 -125 -10 -258" fill="none" stroke="#845A5B" stroke-width="26" stroke-linecap="round"/><path d="M-12 0Q-20 -104 -10 -250" fill="none" stroke="#AC7973" stroke-width="10"/>'
 for _ in range(45):
  xx=rng.uniform(-142,128); yy=rng.uniform(-318,-160); r=rng.uniform(20,38)
  b+=f'<circle cx="{xx:.1f}" cy="{yy:.1f}" r="{r:.1f}" fill="{rng.choice(colors)}"/>'
 for _ in range(22):
  xx=rng.uniform(-142,128); yy=rng.uniform(-323,-158)
  if pink:b+=blossom(xx,yy,rng.uniform(7,15),rng.choice(colors),rot=rng.randint(0,60))
 b+='</g>'
 return b

def frontflowers(seed=5,variant='pink'):
 r=random.Random(seed); out=''
 palette=['#F6A7C9','#F38DBA','#F8C2DC'] if variant=='pink' else ['#7DD2E1','#5FBFCA','#FFEAA0']
 for i in range(54):
  x=r.uniform(-50,1130); y=r.uniform(1410,2000); sz=(y/1920)**3 *r.uniform(22,52)
  if r.random()<.30:out+=blossom(x,y,sz, r.choice(palette),rot=r.randint(0,60))
  else:out+=f'<ellipse cx="{x:.1f}" cy="{y:.1f}" rx="{sz:.1f}" ry="{sz*.48:.1f}" fill="{r.choice(('#65AF72','#4D9A6A','#79BA85'))}" transform="rotate({r.randint(-65,65)},{x:.1f},{y:.1f})"/>'
 return out

def make_world(world):
 if world=='aurora_garden':
  palette=dict(sky1='#A2DEFA',sky2='#F9D4E9',mount1='#B7CDEA',mount2='#82B7D0',lake1='#7FD2E4',lake2='#3686A9',grass='#5AB58D')
  moon='<circle cx="832" cy="265" r="122" fill="#FFF8D8" opacity=".72"/>'
  body=f'''<rect width="1080" height="1920" fill="url(#sky)"/>
  {cloud(180,282,1.1)}{cloud(875,422,.75,op=.48)}{moon}
  {mountain(-170,palette['mount1'],1040,520)}{mountain(180,palette['mount2'],1110,325)}
  <path d="M0 975 Q310 882 640 1026 Q820 945 1080 990 L1080 1920H0Z" fill="#67AE9B"/>
  <path d="M0 1126 Q280 975 570 1120 Q765 1025 1080 1105V1920H0Z" fill="#90D7AC"/>
  <path d="M-30 1295 Q260 1150 610 1270 Q900 1170 1120 1300V1920H-30Z" fill="url(#lake)"/>
  <path d="M-80 1470 Q170 1390 440 1460 M550 1550Q760 1460 1130 1550 M-20 1700Q190 1620 460 1700 M630 1770Q920 1695 1130 1780" fill="none" stroke="#D5FFFF" stroke-width="12" opacity=".25" stroke-linecap="round"/>
  {pagoda(880,1095,1.25)}{bridge(370,1355,1.20)}
  {tree(30,1070,1.40)}{tree(1070,1180,1.52)}{tree(130,1680,.82)}
  <path d="M-40 1810 Q205 1620 355 1770 Q480 1830 530 1920H0Z" fill="#348C69"/>
  <path d="M700 1920 Q840 1770 1120 1750V1920Z" fill="#3C9978"/>
  {frontflowers(89,'pink')}'''
 elif world=='pearl_coast':
  palette=dict(sky1='#8AD5F7',sky2='#FFF2D6',mount1='#9EDBD2',mount2='#62A9C0',lake1='#65D7E7',lake2='#2476B8',grass='#66BDB1')
  moon='<circle cx="813" cy="250" r="128" fill="#FFF2BF" opacity=".85"/>'
  body=f'''<rect width="1080" height="1920" fill="url(#sky)"/>{moon}
  {cloud(160,308,1.15)}{cloud(820,480,.8)}
  {mountain(-260,'#AED6D4',1000,340)}
  <path d="M0 865 Q340 960 700 820 Q890 890 1080 840V1920H0Z" fill="url(#lake)"/>
  <path d="M-80 1280 Q220 1190 455 1310 M560 1450Q850 1380 1200 1510 M-40 1720 Q260 1630 500 1740" stroke="#D3FCFF" stroke-width="12" fill="none" stroke-linecap="round" opacity=".35"/>
  <path d="M-50 1008 Q70 870 190 858 Q310 780 395 780L470 920L435 1230Q220 1345 -50 1300Z" fill="#D6C29A"/>
  <path d="M-50 930 Q175 760 400 855L420 922Q140 890 -40 1080Z" fill="#81C69A"/>
  <path d="M660 1130 Q780 940 970 990Q1060 955 1130 1050L1130 1375Q820 1375 660 1230Z" fill="#C9C49D"/>
  <path d="M660 1130 Q820 940 1150 1000L1150 1090Q900 1040 690 1230Z" fill="#78BC8E"/>
  <g transform="translate(100,790)">
  <rect x="0" y="60" width="195" height="185" rx="9" fill="#FFF4DC" stroke="#E2B7A0" stroke-width="7"/><path d="M-15 73 L96 -16 L210 73Z" fill="#427AAB"/><rect x="63" y="128" width="70" height="117" fill="#A8DCEA"/><rect x="147" y="120" width="32" height="48" rx="15" fill="#4D8CA8"/>
  </g><g transform="translate(245,710) scale(.72)">
  <rect x="0" y="60" width="195" height="185" rx="9" fill="#FFE3D8" stroke="#D3A4A0" stroke-width="7"/><path d="M-15 73 L96 -16 L210 73Z" fill="#C47D81"/><rect x="63" y="128" width="70" height="117" fill="#99CFCA"/>
  </g>{tree(1030,1110,1.05,False)}
  <path d="M0 1730 Q260 1560 430 1730 Q600 1920 800 1920H0Z" fill="#FFE4B1" opacity=".87"/>
  {frontflowers(50,'blue')}'''
 elif world=='crystal_nocturne':
  palette=dict(sky1='#17234C',sky2='#7963AB',mount1='#3B477B',mount2='#242F69',lake1='#6B79C5',lake2='#283966',grass='#436F8C')
  moon='<circle cx="824" cy="285" r="125" fill="#FCF3DC"/><circle cx="883" cy="240" r="120" fill="#27315E"/>'
  r=random.Random(556); stars=''.join(f'<circle cx="{r.randrange(20,1050)}" cy="{r.randrange(35,780)}" r="{r.choice((2,3,4))}" fill="#FFFEF1" opacity="{r.uniform(.45,1):.2f}"/>' for _ in range(75))
  body=f'''<rect width="1080" height="1920" fill="url(#sky)"/>{stars}{moon}
  {cloud(180,395,1.2,'#BAC4F5',.11)}
  {mountain(-150,palette['mount1'],1050,420)}{mountain(120,palette['mount2'],1140,330)}
  <path d="M0 1050 Q250 955 600 1050 Q850 990 1080 1060V1920H0Z" fill="#415B85"/>
  <path d="M0 1310 Q250 1160 600 1300 Q850 1210 1080 1300V1920H0Z" fill="url(#lake)"/>
  <path d="M-40 1430Q290 1340 600 1450 M500 1660Q800 1540 1140 1680" fill="none" stroke="#AFB6FC" stroke-width="10" opacity=".25"/>
  {pagoda(850,1120,1.45,'#624F7B','#252F5D',True)}{bridge(260,1470,1.04)}
  {tree(85,1230,1.30)}{tree(1090,1430,1.6)}
  <path d="M0 1840Q245 1640 470 1810 L600 1920H0Z" fill="#283E66"/>
  <path d="M610 1920 Q880 1700 1080 1780V1920Z" fill="#34466E"/>
  {frontflowers(108,'pink')}'''
 else:raise ValueError(world)
 gradients=f'''<linearGradient id="sky" x1="0" y1="0" x2="0" y2="1"><stop stop-color="{palette['sky1']}"/><stop offset="1" stop-color="{palette['sky2']}"/></linearGradient>
 <linearGradient id="lake" x1="0" y1="0" x2="0" y2="1"><stop stop-color="{palette['lake1']}"/><stop offset="1" stop-color="{palette['lake2']}"/></linearGradient>'''
 return svg(1080,1920,body,gradients)

def stage_worlds():
 from PIL import Image
 for w in ['aurora_garden','pearl_coast','crystal_nocturne']:
  data=make_world(w);path=save_svg('backgrounds/worlds/'+w+'.svg',data,{'_1080x1920':(1080,1920),'_540x960':(540,960)})
  original=Image.open(path.with_name(path.stem+'_1080x1920.png')).convert('RGBA')
  dim=original.filter(ImageFilter.GaussianBlur(11))
  overlay=Image.new('RGBA',dim.size,(6,46,61,92));dim=Image.alpha_composite(dim,overlay)
  gd=BASE/'backgrounds/gameplay';gd.mkdir(parents=True,exist_ok=True)
  dim.save(gd/(w+'_soft_1080x1920.png'),optimize=True)
  # map has organic winding path and tiles will be laid out as live interface
  mapim=original.copy(); layer=Image.new('RGBA',(1080,1920),(0,0,0,0)); dr=ImageDraw.Draw(layer)
  route=[(525,1560),(400,1400),(610,1240),(450,1070),(655,900),(475,720),(625,550)]
  dr.line(route,fill=(255,246,210,230),width=75,joint='curve')
  dr.line(route,fill=(228,185,126,175),width=7,joint='curve')
  mapim=Image.alpha_composite(mapim,layer)
  out=BASE/'backgrounds/maps';out.mkdir(parents=True,exist_ok=True)
  mapim.save(out/(w+'_map_1080x1920.png'),optimize=True)
  print('WORLD',w,flush=True)

# --- Tile generator ---
SUITS=['character','circle','bamboo']
WINDS={'east':'東','south':'南','west':'西','north':'北'}
DRAGONS={'red':'中','green':'發','white':''}
FLOWERS={'plum':'梅','orchid':'蘭','chrysanthemum':'菊','bamboo_flower':'竹'}
SEASONS={'spring':'春','summer':'夏','autumn':'秋','winter':'冬'}
TILE_IDS=[f'{s}_{j}' for s in SUITS for j in range(1,10)]+[f'wind_{w}' for w in WINDS]+[f'dragon_{w}' for w in DRAGONS]+[f'flower_{w}' for w in FLOWERS]+[f'season_{w}' for w in SEASONS]
THEMES={
 'classic':{'top':'#FFFEF7','edge':'#FFEED7','rim':'#E4C3A3','ink':'#1D5879','green':'#268C69','red':'#DB5158','blue':'#336FAB','pink':'#E886AA'},
 'sakura':{'top':'#FFF8F9','edge':'#F9DFE8','rim':'#DCB3C6','ink':'#4D5186','green':'#489D77','red':'#D65D84','blue':'#5984C4','pink':'#E985B4'},
 'ocean':{'top':'#F8FCFF','edge':'#DAECF6','rim':'#A8CCD7','ink':'#1D5B85','green':'#3DA19A','red':'#EB8584','blue':'#2D92CE','pink':'#93BEEA'},
 'nocturne':{'top':'#44476E','edge':'#303457','rim':'#7E70B8','ink':'#F1E0FF','green':'#8BE2B3','red':'#FF9AB8','blue':'#9BD0FF','pink':'#E4A8FF'}
}

def tile_symbol(tid,theme):
 p=THEMES[theme]; b=''
 if tid.startswith('character_'):
  n=int(tid.split('_')[1]); sym='一二三四五六七八九'[n-1]
  b+=fontpaths(sym,'cjk',116,128,154,p['ink'])
  b+=fontpaths('萬','cjk',100,128,257,p['red'])
  b+=f'<path d="M67 278 H190" stroke="{p["rim"]}" stroke-width="3"/>'
 elif tid.startswith('circle_'):
  n=int(tid.split('_')[1]); locations={1:[(128,167)],2:[(100,116),(155,214)],3:[(95,104),(128,164),(159,227)],4:[(90,110),(166,110),(90,221),(166,221)],5:[(90,108),(166,108),(128,167),(90,228),(166,228)],6:[(86,97),(170,97),(86,167),(170,167),(86,238),(170,238)],7:[(84,93),(128,93),(172,93),(84,170),(172,170),(84,238),(172,238)],8:[(88,98),(138,98),(188,98),(88,167),(188,167),(88,236),(138,236),(188,236)],9:[(82+i*46,105+j*68) for j in range(3) for i in range(3)]}[n]
  r=32 if n<=4 else (25 if n<=6 else 20)
  for i,(x,y) in enumerate(locations):
   co=(p['red'] if n==1 else [p['blue'],p['green'],p['red']][i%3])
   b+=f'<circle cx="{x}" cy="{y}" r="{r}" fill="{p["ink"]}" opacity=".13"/><circle cx="{x}" cy="{y}" r="{r-3}" fill="{co}"/><circle cx="{x}" cy="{y}" r="{(r-4)*.70}" fill="none" stroke="#FFFFFF" stroke-width="4" opacity=".9"/><circle cx="{x}" cy="{y}" r="{r*.24}" fill="{p["top"]}"/>'
 elif tid.startswith('bamboo_'):
  n=int(tid.split('_')[1]); locations={1:[(128,164)],2:[(92,125),(164,205)],3:[(95,105),(128,166),(161,227)],4:[(97,120),(162,120),(97,215),(162,215)],5:[(88,104),(168,104),(128,164),(88,233),(168,233)],6:[(88,97),(168,97),(88,164),(168,164),(88,231),(168,231)],7:[(88,86),(168,86),(88,145),(168,145),(88,203),(168,203),(128,256)],8:[(90+i*74,84+j*59) for j in range(4) for i in range(2)],9:[(77+i*51,90+j*70) for j in range(3) for i in range(3)]}[n]
  for i,(x,y) in enumerate(locations):
   s=1.25 if n<=3 else (.88 if n>=7 else 1)
   color=p['red'] if i==0 and n in (1,5,9) else p['green']
   b+=f'<g transform="translate({x},{y}) scale({s})"><rect x="-9" y="-24" width="18" height="48" rx="6" fill="{color}"/><path d="M-10 -6H10 M-10 7H10" stroke="{p["top"]}" stroke-width="5"/><path d="M0 -32V-24 M0 24V32" stroke="{p["green"]}" stroke-width="5" stroke-linecap="round"/></g>'
 elif tid.startswith('wind_'):
  b+=fontpaths(WINDS[tid[5:]],'cjk',160,128,212,p['ink'])
 elif tid.startswith('dragon_'):
  typ=tid[7:]
  if typ=='white':
   b+=f'<rect x="58" y="102" width="140" height="142" rx="16" fill="none" stroke="{p["blue"]}" stroke-width="13"/><rect x="73" y="117" width="110" height="112" rx="7" fill="none" stroke="{p["green"]}" stroke-width="4"/>'
  else:b+=fontpaths(DRAGONS[typ],'cjk',168,128,216,p['red'] if typ=='red' else p['green'])
 elif tid.startswith('flower_'):
  key=tid[7:]; ids=list(FLOWERS); col=[p['red'],p['pink'],p['gold'] if 'gold' in p else '#F1A548',p['green']][ids.index(key)]
  b+=blossom(128,151,69,p['pink'] if key in ('plum','orchid') else ('#E5A94A' if key=='chrysanthemum' else p['green']),rot=17)
  b+=f'<path d="M128 201 Q109 246 126 267" stroke="{p["green"]}" stroke-width="8" fill="none"/>'+leaf(124,254,25,rot=45,color=p['green'])
  b+=fontpaths(FLOWERS[key],'cjk',34,204,283,p['ink'])
 elif tid.startswith('season_'):
  key=tid[7:]; ids=list(SEASONS); cols=['#66C786','#F6CB62','#E99469','#79ABDF']; co=cols[ids.index(key)]
  b+=f'<circle cx="128" cy="158" r="69" fill="{co}" opacity=".20"/>'+blossom(128,157,64,co,rot=35)
  b+=fontpaths(SEASONS[key],'cjk',36,199,286,p['ink'])
 return b

def make_tile(tid,theme):
 p=THEMES[theme]
 extra=f'''<linearGradient id="face" x1="0" y1="0" x2="0" y2="1"><stop stop-color="{p['top']}"/><stop offset="1" stop-color="{p['edge']}"/></linearGradient>'''
 body=f'''<rect x="22" y="24" width="214" height="300" rx="25" fill="#17293E" opacity=".16"/>
 <rect x="14" y="11" width="228" height="302" rx="29" fill="{p['rim']}"/>
 <rect x="15" y="9" width="226" height="292" rx="27" fill="url(#face)" stroke="{p['rim']}" stroke-width="5"/>
 <path d="M45 33 Q128 20 210 33" stroke="#FFFFFF" stroke-width="5" opacity=".75" fill="none"/>
 {tile_symbol(tid,theme)}'''
 return svg(256,328,body,extra)

def stage_tiles():
 for theme in THEMES:
  tstart=time.time()
  for tid in TILE_IDS:
   s=make_tile(tid,theme)
   save_svg(f'tiles/{theme}/svg/{tid}.svg',s)
   png_only(f'tiles/{theme}/png_256/{tid}.png',s,256,328)
   # 128 versions are optional to keep small (export for game-ready low-res)
   png_only(f'tiles/{theme}/png_128/{tid}.png',s,128,164)
  print('TILE THEME',theme,len(TILE_IDS),'T',round(time.time()-tstart,1),'s',flush=True)
 # alternate rear tile and free/disabled overlay
 for theme in THEMES:
  p=THEMES[theme]; color=p['blue']; back=svg(256,328,f'''<rect x="18" y="19" width="220" height="302" rx="28" fill="{p['rim']}"/><rect x="18" y="12" width="220" height="292" rx="25" fill="{p['edge']}" stroke="{p['rim']}" stroke-width="5"/><rect x="39" y="36" width="178" height="244" rx="14" fill="none" stroke="{p['blue']}" stroke-width="8" opacity=".75"/>{blossom(128,155,60,p['pink'])}''')
  save_svg(f'tiles/{theme}/svg/back.svg',back,{'':(256,328)})
 # tile mask overlays separate for UI states
 save_svg('tiles/states/selected.svg',svg(256,328,'<rect x="16" y="10" width="224" height="294" rx="26" fill="#FFF5B0" fill-opacity=".18" stroke="#FFE485" stroke-width="11"/>'),{'':(256,328)})
 save_svg('tiles/states/hint.svg',svg(256,328,'<rect x="16" y="10" width="224" height="294" rx="26" fill="#B0FFEA" fill-opacity=".17" stroke="#53DDBD" stroke-width="11"/>'),{'':(256,328)})
 save_svg('tiles/states/blocked.svg',svg(256,328,'<rect x="16" y="10" width="224" height="294" rx="26" fill="#15263E" fill-opacity=".26"/>'),{'':(256,328)})
 print('TILES DONE',flush=True)

# --- Lightweight vector UI & brand assets ---
ICON_SHAPES={
'home':'<path d="M22 60L64 26L106 60V108H77V78H51V108H22Z"/>',
'worlds':'<circle cx="64" cy="66" r="41"/><path d="M25 66H103 M64 25Q38 65 64 107 M64 25Q90 65 64 107 M36 39Q64 53 92 39 M36 91Q64 79 92 91"/>',
'daily':'<rect x="24" y="32" width="80" height="74" rx="12"/><path d="M24 54H104 M43 23V42 M84 23V42 M46 73H56 M73 73H83 M46 89H56"/>',
'collection':'<path d="M64 20L108 43L64 67L20 43Z M20 64L64 88L108 64 M20 84L64 108L108 84"/>',
'shop':'<path d="M30 50H98L90 107H38Z M24 50L36 25H92L104 50Z M49 73V87 M79 73V87"/>',
'settings':'<circle cx="64" cy="64" r="14"/><path d="M56 18H72L78 29L90 34L102 28L113 40L107 52L110 66L119 74L113 89L99 89L89 101L90 114H72L65 105L52 103L40 113L27 102L32 88L26 76L15 69L21 53L34 51L40 40L37 28L49 20Z"/>',
'shuffle':'<path d="M17 36H34Q48 36 58 54L72 75Q80 89 94 89H112 M100 76L113 89L100 102 M17 91H33Q46 91 56 75L71 53Q81 37 95 37H110 M97 24L111 37L97 50"/>',
'hint':'<path d="M48 84Q48 72 41 63Q24 39 43 24Q60 10 81 25Q102 43 85 65Q79 72 79 84Z M50 91H78 M54 104H74"/>',
'undo':'<path d="M53 31L23 58L54 82 M24 58H75Q107 58 107 82Q107 106 80 106H61"/>',
'pause':'<rect x="30" y="23" width="23" height="82" rx="8"/><rect x="75" y="23" width="23" height="82" rx="8"/>',
'play':'<path d="M42 23L106 64L42 105Z"/>',
'close':'<path d="M32 32L96 96 M96 32L32 96"/>',
'back':'<path d="M75 24L35 64L75 104 M36 64H108"/>',
'next':'<path d="M53 24L93 64L53 104 M92 64H20"/>',
'check':'<path d="M22 65L51 94L107 34"/>',
'plus':'<path d="M64 22V106 M22 64H106"/>',
'minus':'<path d="M22 64H106"/>',
'lock':'<rect x="30" y="56" width="68" height="56" rx="10"/><path d="M44 56V42Q44 18 64 18Q84 18 84 42V56"/>',
'gift':'<rect x="21" y="54" width="86" height="58" rx="8"/><rect x="15" y="40" width="98" height="24" rx="7"/><path d="M64 39V112 M65 38Q27 40 36 21Q44 7 64 38Z M65 38Q99 40 93 21Q84 7 65 38Z"/>',
'heart':'<path d="M64 110L25 74Q2 52 24 29Q46 10 64 35Q82 10 104 29Q126 52 103 74Z"/>',
'star':'<path d="M64 14L80 47L116 52L90 79L96 115L64 98L32 115L38 79L12 52L48 47Z"/>',
'coin':'<circle cx="64" cy="64" r="46"/><circle cx="64" cy="64" r="34"/><path d="M64 43L70 57L86 59L75 70L78 86L64 78L50 86L53 70L42 59L58 57Z"/>',
'gem':'<path d="M16 52L37 22H91L112 52L64 112Z M16 52H112 M37 22L52 52L64 112 M91 22L76 52L64 112 M52 52H76"/>',
'flower':'<circle cx="64" cy="41" r="18"/><circle cx="86" cy="56" r="18"/><circle cx="79" cy="83" r="18"/><circle cx="49" cy="83" r="18"/><circle cx="41" cy="56" r="18"/><circle cx="64" cy="64" r="10"/>',
'restart':'<path d="M28 65A38 38 0 1 0 56 27 M56 27L43 14 M56 27L39 45"/>',
'sound':'<path d="M19 49H39L66 24V104L39 79H19Z M78 47Q99 62 78 81 M89 31Q119 61 89 97"/>',
'music':'<path d="M53 29V87Q53 100 36 100Q18 100 18 86Q18 72 39 72Q47 72 53 75 M53 35L109 23V80Q109 95 91 95Q75 95 75 82Q75 67 94 67Q102 67 109 70"/>',
'share':'<circle cx="91" cy="24" r="14"/><circle cx="35" cy="64" r="14"/><circle cx="91" cy="104" r="14"/><path d="M48 57L78 30 M48 72L78 98"/>',
'info':'<circle cx="64" cy="64" r="45"/><path d="M64 57V88 M64 36V41"/>',
'calendar_check':'<rect x="22" y="30" width="84" height="80" rx="11"/><path d="M22 54H106 M42 20V41 M85 20V41 M43 81L57 94L86 67"/>',
'crown':'<path d="M20 42L42 62L64 25L86 62L108 42L98 99H30Z M30 108H98"/>',
'eye':'<path d="M18 64Q64 18 110 64Q64 110 18 64Z"/><circle cx="64" cy="64" r="16"/>',
'sparkle':'<path d="M64 15L78 50L114 64L78 78L64 114L50 78L14 64L50 50Z"/>',
'cloud':'<path d="M34 91H98Q117 91 117 72Q117 54 98 51Q92 29 73 27Q45 20 33 50Q13 51 13 71Q13 91 34 91Z"/>',
'volume_off':'<path d="M19 49H39L66 24V104L39 79H19Z M80 45L105 82 M105 45L80 82"/>',
'loading':'<circle cx="64" cy="64" r="42" stroke-dasharray="38 17"/>',
}

def make_icon(name,color='#1C6B8F',width=128):
 paths=ICON_SHAPES[name]
 # outlines are white in a chip? for standalone use dark stroke and near-transparent fill except special symbols
 if name in ('heart','star','gift','flower','gem','coin','play','pause','crown','sparkle','home'):
  fill=f'{color}'
 else:fill='none'
 return svg(128,128,f'<g fill="{fill}" stroke="{color}" stroke-width="7" stroke-linecap="round" stroke-linejoin="round">{paths}</g>')

def draw_button(w,h,kind='green',state='normal'):
 grad={'green':'buttonGreen','blue':'buttonBlue','violet':'buttonViolet','gold':'buttonGold','rose':'buttonRose','cream':'panel'}[kind]
 opacity='.55' if state=='disabled' else '1'; y=14 if state=='pressed' else 4
 return svg(w,h,f'''<g opacity="{opacity}">
 <rect x="12" y="{y+12}" width="{w-24}" height="{h-y-20}" rx="{(h-y-20)*.41:.1f}" fill="#224E59" opacity=".22"/>
 <rect x="10" y="{y}" width="{w-20}" height="{h-y-21}" rx="{(h-y-21)*.43:.1f}" fill="url(#{grad})" stroke="{('#B7DBBB' if kind=='green' else '#FFFFFF')}" stroke-width="5"/>
 <path d="M{h*.42:.0f} {y+17} Q{w/2} {y+3} {w-h*.42:.0f} {y+17}" fill="none" stroke="#FFFFFF" stroke-width="4" opacity=".55"/>
 </g>''')

def make_badge(name):
 if name=='coin':
  return svg(128,128,f'<circle cx="64" cy="65" r="49" fill="#C78522"/><circle cx="64" cy="60" r="46" fill="url(#buttonGold)" stroke="#FFE8A6" stroke-width="5"/><circle cx="64" cy="60" r="32" fill="none" stroke="#FFE8A6" stroke-width="5"/>{star(64,59,23,fill="#FFF1A8",stroke="#E7A546")}')
 if name=='gem':
  return svg(128,128,'<path d="M14 43L41 17H87L114 43L64 115Z" fill="url(#gem)" stroke="#7043C5" stroke-width="5"/><path d="M14 43H114M41 17L54 43L64 115M87 17L74 43L64 115 M54 43H74" fill="none" stroke="#F5DFFF" stroke-width="4"/>')
 if name=='star':return svg(128,128,star(64,65,50,fill='#FFCD52')+'<path d="M43 50Q58 34 70 37" stroke="#FFEEBA" stroke-width="7" fill="none" stroke-linecap="round"/>')
 if name=='heart':return svg(128,128,'<path d="M64 110L22 70Q1 45 26 27Q49 13 64 39Q82 12 106 27Q131 49 107 74Z" fill="#FB6477" stroke="#B83E63" stroke-width="5"/><path d="M28 42Q38 32 48 38" stroke="#FFD8DF" stroke-width="7" fill="none" stroke-linecap="round"/>')
 if name=='flower':return svg(128,128,blossom(64,66,50,'#F49BBF'))
 if name=='light':return svg(128,128,'<circle cx="64" cy="64" r="56" fill="url(#glow)"/>'+star(64,64,34,fill='#FFF4BD',stroke='#F5C35E'))
 if name=='chest':
  return svg(128,128,'<rect x="18" y="47" width="92" height="62" rx="13" fill="#D68438" stroke="#8E5128" stroke-width="5"/><path d="M18 57Q19 22 64 22Q111 22 110 57Z" fill="url(#buttonGold)" stroke="#AA6B35" stroke-width="6"/><path d="M61 26V109" stroke="#FFE9AD" stroke-width="12"/><rect x="51" y="60" width="26" height="28" rx="4" fill="#F5DB68" stroke="#A9632D" stroke-width="4"/>')
 if name=='gift':
  return svg(128,128,'<rect x="19" y="55" width="90" height="59" rx="8" fill="#EA687A" stroke="#B84F68" stroke-width="5"/><rect x="13" y="42" width="102" height="24" rx="6" fill="#F897A5" stroke="#B84F68" stroke-width="4"/><path d="M64 41V114" stroke="#FFE392" stroke-width="14"/><path d="M65 41Q20 42 37 19Q54 6 65 41Z M65 41Q111 40 96 18Q80 8 65 41Z" fill="#FFD96D" stroke="#C79345" stroke-width="4"/>')
 raise ValueError(name)

def make_app_emblem():
 b=f'<rect width="1024" height="1024" rx="232" fill="url(#bg)"/>'
 b+='<circle cx="822" cy="235" r="265" fill="#F5D2F0" opacity=".44"/><circle cx="160" cy="760" r="270" fill="#BCEAD5" opacity=".68"/>'
 for (x,y,s,rot) in [(165,211,.72,-24),(790,190,.76,15),(810,790,.7,38),(208,791,.68,20)]:
  b+=f'<g transform="translate({x},{y}) scale({s})">{leaf(-5,72,88,-42)}{leaf(92,60,82,48)}{blossom(32,22,104,"#F78AB7",rot=rot)}</g>'
 b+='<g transform="translate(512,505) rotate(-9)"><rect x="-194" y="-237" width="388" height="508" rx="65" fill="#19385A" opacity=".25"/><rect x="-200" y="-252" width="385" height="492" rx="53" fill="#E8C9AB" stroke="#CEB092" stroke-width="14"/><rect x="-200" y="-267" width="385" height="487" rx="53" fill="url(#ivory)" stroke="#EDD1AF" stroke-width="12"/>'
 b+=blossom(0,-20,116,'#F590BE')+leaf(-76,135,63,-42)+leaf(80,151,68,41)+'</g>'
 b+='<circle cx="635" cy="279" r="15" fill="#FFEDAC"/><circle cx="275" cy="636" r="11" fill="#FFF7CB"/>'
 bg='<linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#7EE4EE"/><stop offset=".45" stop-color="#69B7E6"/><stop offset="1" stop-color="#9678DF"/></linearGradient>'
 return svg(1024,1024,b,bg)

def stage_brand_ui():
 # Brand: independent no text / text, no embedded external font binaries
 emblem=make_app_emblem()
 save_svg('branding/app_icon_master.svg',emblem,{'_1024':(1024,1024),'_512':(512,512),'_192':(192,192),'_180':(180,180)})
 ico=Image.open(BASE/'branding/app_icon_master_1024.png')
 for sub,name,size in [('ios','AppIcon_1024.png',1024),('android','play_store_icon_512.png',512),('web','favicon_64.png',64)]:
  p=BASE/'app_icons'/sub;p.mkdir(parents=True,exist_ok=True)
  ico.resize((size,size),Image.Resampling.LANCZOS).convert('RGB').save(p/name)
 # Android adaptive foreground transparent centered / background opaque
 img=Image.new('RGBA',(432,432),(0,0,0,0))
 tile=ico.resize((275,275),Image.Resampling.LANCZOS)
 img.alpha_composite(tile,(79,79))
 p=BASE/'app_icons/android';p.mkdir(parents=True,exist_ok=True)
 img.save(p/'adaptive_foreground_432.png')
 bg=Image.new('RGBA',(432,432),'#76B9E3'); bg.save(p/'adaptive_background_432.png')
 mon=Image.new('RGBA',(432,432),(0,0,0,0));d=ImageDraw.Draw(mon)
 d.rounded_rectangle((128,105,304,329),radius=24,fill=(255,255,255,255));d.ellipse((160,148,273,263),fill=(0,0,0,0))
 mon.save(p/'adaptive_monochrome_432.png')
 # logos (SVG glyphs as paths to avoid font dependency)
 for kind in ('dark','light'):
  c='#163F5A' if kind=='dark' else '#FFFFFF'
  body=blossom(295,82,43,'#F18BB7')+fontpaths('Veya','serif',144,300,245,c)
  body+=fontpaths('MAHJONG','sans',39,300,315,c)
  save_svg(f'branding/veya_logo_stacked_{kind}.svg',svg(600,370,body),{'':(600,370)})
  body=blossom(88,110,51,'#F18BB7')+fontpaths('Veya','serif',142,208,150,c,anchor='start')+fontpaths('MAHJONG','sans',35,213,202,c,anchor='start')
  save_svg(f'branding/veya_logo_horizontal_{kind}.svg',svg(650,245,body),{'':(650,245)})
 # Buttons
 for kind in ('green','blue','violet','gold','rose','cream'):
  for state in ('normal','pressed','disabled'):
   for nm,wh in (('large',(460,150)),('small',(220,100))):
    a=draw_button(wh[0],wh[1],kind,state)
    save_svg(f'ui/buttons/{kind}_{nm}_{state}.svg',a,{'':wh})
 # icons and tinted icons
 for name in ICON_SHAPES:
  for tint,co in [('navy','#23536C'),('white','#FFFFFF')]:
   save_svg(f'ui/icons/{tint}/{name}.svg',make_icon(name,co),{'':(128,128)})
 for name in ('coin','gem','star','heart','flower','light','gift','chest'):
  save_svg(f'ui/rewards/{name}.svg',make_badge(name),{'':(128,128),'_256':(256,256)})
 # Panels/cards/rounded circles/switch/progress bars
 surfaces={
  'panel_cream':(640,760,'<rect x="22" y="25" width="596" height="711" rx="55" fill="#235063" opacity=".15"/><rect x="14" y="13" width="611" height="718" rx="48" fill="url(#panel)" stroke="#E5CFAA" stroke-width="8"/>'),
  'panel_dark':(640,760,'<rect x="22" y="20" width="596" height="710" rx="55" fill="#09162A" opacity=".25"/><rect x="14" y="13" width="611" height="718" rx="48" fill="#164C62" stroke="#7ED9CF" stroke-width="7"/>'),
  'panel_white':(640,760,'<rect x="14" y="13" width="611" height="718" rx="48" fill="#FFFFFF" stroke="#E6E5E1" stroke-width="7"/>'),
  'card_cream':(512,280,'<rect x="15" y="18" width="484" height="248" rx="38" fill="#7E684E" opacity=".10"/><rect x="12" y="9" width="488" height="248" rx="32" fill="url(#panel)" stroke="#EBCF9F" stroke-width="6"/>'),
  'card_blue':(512,280,'<rect x="12" y="10" width="488" height="250" rx="30" fill="#D9F2FF" stroke="#88CBDF" stroke-width="6"/>'),
  'bar_track':(540,92,'<rect x="12" y="14" width="516" height="63" rx="31" fill="#DCCCB0" stroke="#FFFFFF" stroke-width="5"/>'),
  'bar_fill_green':(540,92,'<rect x="11" y="13" width="515" height="64" rx="31" fill="url(#buttonGreen)" stroke="#D7F7DA" stroke-width="4"/>'),
  'bar_fill_blue':(540,92,'<rect x="11" y="13" width="515" height="64" rx="31" fill="url(#buttonBlue)" stroke="#DFF6FC" stroke-width="4"/>'),
  'nav_bar':(1080,180,'<rect x="0" y="20" width="1080" height="160" rx="43" fill="url(#panel)" stroke="#FFFDFC" stroke-width="7"/>'),
  'hud_pill':(460,118,'<rect x="12" y="12" width="436" height="92" rx="46" fill="#134C60" opacity=".82" stroke="#A7EEE4" stroke-width="4"/>'),
  'ribbon':(630,145,'<path d="M12 23H618L572 75L618 129H12L58 75Z" fill="url(#panel)" stroke="#DBBD98" stroke-width="5"/>'),
  'round_green':(180,180,'<circle cx="90" cy="95" r="78" fill="#195D67" opacity=".3"/><circle cx="90" cy="85" r="76" fill="url(#buttonGreen)" stroke="#FFF3D6" stroke-width="8"/>'),
  'round_blue':(180,180,'<circle cx="90" cy="95" r="78" fill="#195D67" opacity=".3"/><circle cx="90" cy="85" r="76" fill="url(#buttonBlue)" stroke="#FFF3D6" stroke-width="8"/>'),
  'round_locked':(180,180,'<circle cx="90" cy="95" r="78" fill="#195D67" opacity=".3"/><circle cx="90" cy="85" r="76" fill="#B9C1C7" stroke="#F9F0E5" stroke-width="8"/>'),
  'toggle_on':(150,84,'<rect x="4" y="7" width="142" height="70" rx="35" fill="#36BC87"/><circle cx="112" cy="42" r="29" fill="#FFFFFF"/>'),
  'toggle_off':(150,84,'<rect x="4" y="7" width="142" height="70" rx="35" fill="#ADB8BC"/><circle cx="39" cy="42" r="29" fill="#FFFFFF"/>')
 }
 for name,(w,h,body) in surfaces.items():save_svg(f'ui/components/{name}.svg',svg(w,h,body),{'':(w,h)})
 print('BRANDING+UI',len(ICON_SHAPES),'icons',len(surfaces),'components',flush=True)

# --- Standalone environment sprites and sprite atlases ---
def decor_sprite(name):
 if name=='sakura_tree':return svg(620,650,tree(305,606,1.65))
 if name=='leaf_tree':return svg(620,650,tree(305,606,1.65,False))
 if name=='maple_tree':
  b=tree(305,606,1.65,False).replace('#64BB78','#ED985F').replace('#7ACA78','#F0BA63').replace('#93CE76','#E28054').replace('#53A66F','#CB744E')
  return svg(620,650,b)
 if name=='bridge':return svg(640,330,bridge(320,162,1.16))
 if name=='pagoda':return svg(500,600,pagoda(250,500,1.75))
 if name=='pagoda_night':return svg(500,600,pagoda(250,500,1.75,'#64547A','#354273',True))
 if name=='pond':
  b='<ellipse cx="312" cy="280" rx="275" ry="132" fill="#5BAC86" opacity=".35"/><ellipse cx="312" cy="270" rx="266" ry="113" fill="#61C8DA" stroke="#3D9DB0" stroke-width="10"/><path d="M145 260Q255 220 325 264 M340 297Q444 268 502 303" stroke="#B5F0F4" stroke-width="8" fill="none" opacity=".64"/>'
  for x,y,s in [(150,296,.7),(492,241,.8),(420,336,.5)]:b+=f'<ellipse cx="{x}" cy="{y}" rx="{55*s}" ry="{25*s}" fill="#57AA72"/><path d="M{x} {y}L{x+55*s} {y-15*s}" stroke="#82D490" stroke-width="5"/>'
  return svg(640,520,b)
 if name=='stone_lantern':
  return svg(390,530,'''<path d="M140 474H264L248 503H158Z" fill="#9AA5AA" stroke="#697E87" stroke-width="6"/><path d="M177 235H228L241 482H162Z" fill="#AAB8B5" stroke="#71858C" stroke-width="8"/><path d="M151 216H252L236 330H166Z" fill="#7A8993" stroke="#576A79" stroke-width="7"/><rect x="177" y="239" width="51" height="60" rx="7" fill="#FFE8A8"/><path d="M107 214Q198 165 300 214L282 243H121Z" fill="#8795A0" stroke="#64727A" stroke-width="9"/><path d="M146 165L197 111L250 165Z" fill="#9EADB2" stroke="#708087" stroke-width="7"/><circle cx="197" cy="105" r="15" fill="#ADB7B5"/>''')
 if name=='lantern':
  return svg(310,450,'''<path d="M154 45V100" stroke="#80564F" stroke-width="15"/><path d="M69 110L154 68L241 110" stroke="#9B4F50" stroke-width="15" stroke-linejoin="round"/><rect x="68" y="110" width="173" height="211" rx="35" fill="#F48B91" stroke="#C46171" stroke-width="12"/><rect x="92" y="128" width="124" height="170" rx="25" fill="#FFDDA3"/><path d="M154 115V316 M73 207H238" stroke="#CB6870" stroke-width="12"/><path d="M75 320Q154 367 235 320" fill="none" stroke="#AA5960" stroke-width="14"/><path d="M154 346V408" stroke="#AC7B50" stroke-width="8"/>''')
 if name=='hedge':
  r=random.Random(66);b=''
  for i in range(12):
   x=r.randrange(80,515);y=r.randrange(290,400);z=r.randrange(53,95)
   b+=f'<circle cx="{x}" cy="{y}" r="{z}" fill="{r.choice(("#60AE70","#6EC285","#449E69","#76C88A"))}"/>'
  return svg(600,480,b)
 if name=='flower_bed':
  r=random.Random(87); b='<ellipse cx="300" cy="360" rx="252" ry="95" fill="#4C9D69"/>'
  for i in range(40):
   x=r.randrange(90,510);y=r.randrange(300,407)
   b+=blossom(x,y,r.randrange(12,22),r.choice(['#F98FB5','#FFD973','#EDB5CE','#F9D1D3','#F9A4D5']))
  return svg(600,480,b)
 if name=='shrub':
  return svg(520,500,'<ellipse cx="254" cy="438" rx="206" ry="47" fill="#499A71"/>' + ''.join(f'<circle cx="{x}" cy="{y}" r="{z}" fill="{col}"/>' for x,y,z,col in [(142,337,88,'#55A572'),(223,282,111,'#62BA7B'),(341,322,93,'#83C988'),(404,373,65,'#50A76E')]))
 if name=='rocks':
  return svg(560,430,'<ellipse cx="280" cy="360" rx="245" ry="49" fill="#689E88"/>' + ''.join(f'<path d="M{x-rr} 360L{x-rr*.85} {360-rr*1.4}L{x-rr*.2} {360-rr*2.1}L{x+rr*.65} {360-rr*1.5}L{x+rr} 360Z" fill="{col}" stroke="#8D9F9E" stroke-width="5"/>' for x,rr,col in [(133,71,'#98A7A8'),(278,115,'#B8C3BC'),(435,65,'#879B9C')]))
 if name=='shell':
  b='<path d="M80 356Q45 185 284 68Q503 183 475 355Q260 410 80 356Z" fill="#F8DDBD" stroke="#D09C91" stroke-width="13"/><path d="M284 68L284 363 M284 68L159 356 M284 68L410 356 M284 68L88 296 M284 68L467 296" stroke="#E6AD9C" stroke-width="13" opacity=".85" fill="none"/>'
  return svg(560,450,b)
 if name=='coral':
  b='<path d="M262 464V175 M262 337L165 248V140 M262 300L350 203V120 M165 244L110 211V130 M346 217L407 170V104" fill="none" stroke="#EE8F9D" stroke-width="53" stroke-linecap="round" stroke-linejoin="round"/><path d="M250 450H280" stroke="#F7AFAC" stroke-width="14"/>'
  return svg(540,540,b)
 if name=='crystal_cluster':
  b='<path d="M205 490L110 339L166 160L249 89L308 191L297 490Z" fill="#AB93EB" stroke="#6F64BA" stroke-width="10"/><path d="M303 492L260 280L337 98L421 203L453 393L405 490Z" fill="#79C4E7" stroke="#498AB7" stroke-width="10"/><path d="M178 167L248 89L244 470 M338 104L360 458" stroke="#E5E0FF" stroke-width="15" opacity=".72"/>'
  return svg(550,560,b)
 if name=='wooden_fence':
  b='<path d="M35 220Q350 155 655 215 M35 310Q350 247 655 303" stroke="#965C43" stroke-width="26" fill="none"/>'
  for x in range(70,690,130):b+=f'<path d="M{x} 125L{x+18} 100L{x+36} 125V360H{x}Z" fill="#D29C69" stroke="#945E48" stroke-width="7"/>'
  return svg(710,450,b)
 if name=='cherry_petals':
  b=''
  for i,(x,y,rot) in enumerate([(65,58,3),(130,144,40),(200,54,70),(300,157,12),(360,45,43),(465,101,84)]):
   b+=f'<ellipse cx="{x}" cy="{y}" rx="18" ry="34" fill="{["#F2A2C8","#F7C5D9","#E983B4"][i%3]}" transform="rotate({rot},{x},{y})"/>'
  return svg(530,240,b)
 if name=='grass_patch':
  b='<ellipse cx="300" cy="390" rx="256" ry="70" fill="#74BA7D"/>'
  for i in range(12):
   x=65+i*42;b+=f'<path d="M{x} 375Q{x-16} 320 {x-10} 285 M{x} 375Q{x+18} 316 {x+25} 307" fill="none" stroke="#4B9D67" stroke-width="9" stroke-linecap="round"/>'
  return svg(610,490,b)
 if name=='stone_path':
  b=''
  for x,y,a,bw in [(110,338,90,50),(254,279,79,46),(360,207,64,38),(432,142,57,32)]:b+=f'<ellipse cx="{x}" cy="{y+9}" rx="{a}" ry="{bw}" fill="#97A9A4"/><ellipse cx="{x}" cy="{y}" rx="{a}" ry="{bw}" fill="#D6D4B7" stroke="#A1B1A3" stroke-width="7"/>'
  return svg(600,470,b)
 if name=='blossom_pink':return svg(320,320,blossom(160,160,112,'#F295BF'))
 if name=='blossom_white':return svg(320,320,blossom(160,160,112,'#FFF5ED','#EFC661'))
 if name=='blossom_blue':return svg(320,320,blossom(160,160,112,'#72C8E9','#FFE19E'))
 if name=='lotus':
  b='<ellipse cx="280" cy="425" rx="210" ry="57" fill="#60A878"/><ellipse cx="280" cy="425" rx="150" ry="40" fill="#8EC894"/>'
  for i in range(7):
   xx=280+(i-3)*37;b+=f'<path d="M280 365Q{xx-95} 290 {xx} 164Q{xx+95} 300 280 365Z" fill="{["#F6A2D2","#FFA4CC","#FFC6DD"][i%3]}" stroke="#E58AB5" stroke-width="4" transform="rotate({(i-3)*10},280,365)"/>'
  return svg(560,510,b)
 if name=='butterfly':
  b='<ellipse cx="271" cy="294" rx="16" ry="95" fill="#8B6188"/><path d="M265 285Q110 68 103 248Q100 355 265 315Z" fill="#B79CED" stroke="#7D68C4" stroke-width="9"/><path d="M277 285Q435 68 440 248Q440 355 277 315Z" fill="#F9A8CB" stroke="#CE7DA8" stroke-width="9"/><path d="M265 323Q131 317 178 440Q240 475 268 337 M278 323Q405 317 371 440Q303 475 275 337" fill="#8ED0E4" stroke="#6AA8C4" stroke-width="8"/><path d="M264 207L227 149 M279 207L319 149" stroke="#7B6888" stroke-width="8"/>'
  return svg(550,550,b)
 if name=='pearl':return svg(300,300,'<circle cx="150" cy="154" r="116" fill="#F9EDF7" stroke="#CBC9E4" stroke-width="11"/><circle cx="110" cy="107" r="42" fill="#FFFFFF" opacity=".75"/>')
 raise ValueError(name)

def stage_decor_fx():
 names=['sakura_tree','leaf_tree','maple_tree','bridge','pagoda','pagoda_night','pond','stone_lantern','lantern','hedge','flower_bed','shrub','rocks','shell','coral','crystal_cluster','wooden_fence','cherry_petals','grass_patch','stone_path','blossom_pink','blossom_white','blossom_blue','lotus','butterfly','pearl']
 for name in names:
  markup=decor_sprite(name)
  # per-object SVG & PNG; much smaller for low end devices
  save_svg('decorations/'+name+'.svg',markup,{'_512':(512,512),'_256':(256,256)})
 # Particle sprites, 12 sequential frames @128x128 and atlases
 for typ in ('match_sparkle','petal_pop','ripple','gold_twinkle'):
  frames=[]
  for frame in range(12):
   progress=frame/11
   if typ=='match_sparkle':
    b=f'<circle cx="64" cy="64" r="{8+progress*47:.1f}" fill="none" stroke="#FFE299" stroke-width="{7*(1-progress)+1:.1f}" opacity="{1-progress:.2f}"/>'
    for j in range(6):
     a=j*math.pi/3+progress*.55;x=64+math.cos(a)*progress*52;y=64+math.sin(a)*progress*52
     b+=star(x,y,7+(1-progress)*5,fill='#FFF0B3',stroke='#FFD069')
   elif typ=='petal_pop':
    b=''
    for j in range(5):
     a=j*math.pi*2/5; rr=progress*47; x=64+math.cos(a)*rr;y=64+math.sin(a)*rr
     b+=f'<ellipse cx="{x:.1f}" cy="{y:.1f}" rx="{max(2,8*(1-progress)):.1f}" ry="{max(4,14*(1-progress)):.1f}" fill="#F5A3C8" transform="rotate({j*72+frame*5},{x:.1f},{y:.1f})"/>'
   elif typ=='ripple':b=f'<circle cx="64" cy="64" r="{2+progress*57}" fill="none" stroke="#82E5EB" stroke-width="{7*(1-progress)+1}" opacity="{1-progress:.2f}"/>'
   else:b=f'<circle cx="64" cy="64" r="{58*(1-progress/2)}" fill="url(#glow)" opacity="{1-progress:.2f}"/>'+star(64,64,(20+progress*22)*(1-progress*.6),fill='#FFEBA6',stroke='#FFE6A3')
   markup=svg(128,128,b)
   filename=f'effects/frames/{typ}_{frame:02d}.png';png_only(filename,markup,128,128)
   frames.append((BASE/filename))
  atlas=Image.new('RGBA',(128*6,128*2),(0,0,0,0))
  for j,p in enumerate(frames):atlas.alpha_composite(Image.open(p).convert('RGBA'),((j%6)*128,(j//6)*128))
  out=BASE/'effects/atlases';out.mkdir(parents=True,exist_ok=True)
  atlas.save(out/(typ+'_atlas.png'),optimize=True)
  (out/(typ+'_atlas.json')).write_text(json.dumps({'frame_width':128,'frame_height':128,'columns':6,'rows':2,'count':12,'fps':20,'loop':False},indent=2))
 print('DECOR+FX',len(names),'decor objects, 4 atlases',flush=True)

def stage_atlases():
 at=BASE/'tiles/atlases';at.mkdir(parents=True,exist_ok=True)
 for theme in THEMES:
  for size,(w,h) in [('256',(256,328)),('128',(128,164))]:
   cols=7; rows=6;atlas=Image.new('RGBA',(cols*w,rows*h),(0,0,0,0)); mapping={}
   for idx,tid in enumerate(TILE_IDS):
    x=idx%cols*w;y=idx//cols*h
    p=BASE/f'tiles/{theme}/png_{size}/{tid}.png'
    atlas.alpha_composite(Image.open(p).convert('RGBA'),(x,y))
    mapping[tid]={'x':x,'y':y,'width':w,'height':h,'index':idx}
   atlas.save(at/(f'{theme}_{size}_atlas.png'),optimize=True)
   (at/(f'{theme}_{size}_atlas.json')).write_text(json.dumps({'texture':f'{theme}_{size}_atlas.png','cell_size':[w,h],'tile_count':len(TILE_IDS),'mapping':mapping},ensure_ascii=False,indent=2))
 print('ATLASES',flush=True)

# --- Original procedurally synthesized sound (no third-party samples) ---
def wav_write(path,samples,sr=22050):
 import wave
 path.parent.mkdir(parents=True,exist_ok=True)
 arr=(np.clip(samples,-1,1)*32767).astype(np.int16)
 with wave.open(str(path),'wb') as w:
  w.setnchannels(1);w.setsampwidth(2);w.setframerate(sr);w.writeframes(arr.tobytes())

def synth_note(f, seconds, sr=22050, color=0):
 t=np.arange(round(sr*seconds))/sr
 env=(1-np.exp(-t*95))*(np.exp(-t*(6 if color==0 else 3)))
 if color==0:
  wave=np.sin(2*np.pi*f*t)*.76 +np.sin(2*np.pi*f*2*t)*.20+np.sin(2*np.pi*f*3*t)*.04
 else:
  wave=np.sin(2*np.pi*f*t)*.74+np.sin(2*np.pi*f*2.01*t)*.12+np.sin(2*np.pi*f*3.99*t)*.05
 return wave*env

def stage_audio():
 sr=22050
 musicroot=BASE/'audio/music';musicroot.mkdir(parents=True,exist_ok=True)
 sfxroot=BASE/'audio/sfx';sfxroot.mkdir(parents=True,exist_ok=True)
 def tone(freqs,dur,gain=.42,color=0):
  a=np.zeros(int(round(sr*dur)),np.float32)
  for i,f in enumerate(freqs):
   x=synth_note(f,dur,sr,color)
   a[:len(x)]+=x*gain/len(freqs)
  return a
 def save(name,seq,dur):
  total=np.zeros(int(dur*sr),np.float32)
  for start,freqs,gain,color in seq:
   ns=tone(freqs,max(.01,dur-start),gain,color)
   off=int(round(sr*start)); nn=min(len(ns),len(total)-off); total[off:off+nn]+=ns[:nn]
  if total.max()>0.85: total*=.85/total.max()
  wav_write(sfxroot/(name+'.wav'),total,sr)
 notes={'tap':[523.25],'select':[659.25],'match':[523.25,783.99],
 'invalid':[196.00,246.94],'undo':[392,329.63],'hint':[659.25,987.77],
 'shuffle':[440,554.37,659.25], 'coin':[659.25,1046.5], 'reward':[659.25,783.99,987.77],
 'world_unlock':[523.25,659.25,783.99,1046.5], 'victory':[523.25,659.25,783.99,1046.5], 'button':[392],
 'soft_pop':[293.66,440.00]}
 for name,nns in notes.items():
  dur=1.9 if name in ('victory','world_unlock') else (.8 if name in ('reward','shuffle','hint') else .35)
  seq=[]
  if name in ('victory','world_unlock'):
   for j,f in enumerate(nns):seq.append((j*.22,[f],.38,1))
  elif name in ('reward','shuffle'):seq=[(j*.13,[f],.33,1) for j,f in enumerate(nns)]
  else:seq=[(0,nns,.35,0)]
  save(name,seq,dur)
 # Endless peaceful music loops, 24 seconds. Procedurally composed from sine tone/chime envelopes.
 tracks={
  'aurora_garden':{'root':261.63,'chords':[[0,4,7],[9,0,4],[5,9,0],[7,11,2]],'mel':[0,4,7,9,7,4,2,4,5,9,12,9,7,4,2,0]},
  'pearl_coast':{'root':293.66,'chords':[[0,4,7],[5,9,0],[7,11,2],[0,4,7]],'mel':[7,9,12,9,7,4,5,7,9,7,4,2,0,4,5,7]},
  'crystal_nocturne':{'root':220.0,'chords':[[0,3,7],[8,0,3],[5,8,0],[7,10,2]],'mel':[0,3,7,10,8,7,3,0,2,5,8,10,7,5,3,2]}
 }
 N=int(sr*24)
 for name,meta in tracks.items():
  rng=np.random.default_rng(1741+len(name));x=np.arange(N)/sr;arr=np.zeros(N,np.float64)
  root=meta['root']
  # smooth slow pads with periodic envelopes; 4 chords, six seconds each
  for k,chord in enumerate(meta['chords']):
   pos=k*6;span=8
   at=np.arange(int(sr*span))/sr
   env=np.sin(np.pi*np.clip(at/span,0,1))**1.5
   for j,n in enumerate(chord):
    freq=(root/2)*(2**(n/12))
    w=(np.sin(2*np.pi*freq*at)+.2*np.sin(2*np.pi*(freq*2.002)*at))*env*.033
    st=int(pos*sr)
    # wrap-around for seamless playback
    indices=(np.arange(len(w))+st)%N
    np.add.at(arr,indices,w)
  # notes placed every 1.5 seconds as very soft bell
  for j,n in enumerate(meta['mel']):
   freq=root*(2**(n/12))
   st=int(j*1.5*sr);dur=1.38
   note=synth_note(freq,dur,sr,1)*.085
   env=np.linspace(1,.2,len(note))
   arr[st:st+len(note)]+=note*env
  # extremely faint soft wideband noise bed from smoothed random signal
  raw=rng.standard_normal(N).astype(np.float32)
  smooth=np.convolve(raw,np.ones(320)/320,mode='same')
  arr+=smooth*.015
  # exact seam interpolation crossfade
  fade=int(sr*.22)
  for i in range(fade):
   a=i/fade;m=arr[-fade+i]*(1-a)+arr[i]*a
   arr[-fade+i]=m;arr[i]=m
  arr=np.clip(arr,-.65,.65)
  temp=musicroot/(name+'_source.wav');wav_write(temp,arr,sr)
  ogg=musicroot/(name+'_loop.ogg')
  subprocess.run(['ffmpeg','-y','-loglevel','error','-i',str(temp),'-c:a','libvorbis','-qscale:a','3',str(ogg)],check=True)
  temp.unlink()
  print('MUSIC',name,round(ogg.stat().st_size/1024),'KB',flush=True)
 # licensed no samples used; synth only. internal docs
 (BASE/'audio/AUDIO_MAP.json').write_text(json.dumps({'events':{k:f'sfx/{k}.wav' for k in notes},'loops':{name:f'music/{name}_loop.ogg' for name in tracks},'music_loop_seconds':24,'audio_origins':'Procedurally synthesized originals; no external samples'},indent=2))
 print('AUDIO',len(notes),'SFX + 3 loops',flush=True)

# --- deterministic authored layouts / provably solvable example level configurations ---
def free_positions(remaining):
 # simplified 3D grid with horizontally aligned tile layers and exactly overlapping cover checks
 rem=set(remaining);out=[]
 for x,y,z in rem:
  if (x,y,z+1) in rem:continue
  if (x-1,y,z) not in rem or (x+1,y,z) not in rem:
   out.append((x,y,z))
 return out

def make_layout(i):
 rng=random.Random(32000+i*17)
 if i<5:w,h=4+(i//2)*2,4+(i%2)*2
 else:
  w=min(12,6+(i%6));h=min(10,4+(i%5))
 shape=['rect','hourglass','steps','diamond','frame'][i%5]
 pos=[]
 for y in range(h):
  row=[]
  for x in range(w):
   ok=True
   if shape=='hourglass' and abs(y-(h-1)/2)<h*.24:ok=(x>0 and x<w-1)
   if shape=='steps' and y in (0,h-1):ok=(x>0 and x<w-1)
   if shape=='diamond':ok=(abs(x-(w-1)/2)/(w/2)+abs(y-(h-1)/2)/(h/2)<1.50)
   if shape=='frame' and i%2 and (1<y<h-2 and 1<x<w-2):ok=False
   if ok:row.append((x,y,0))
  if len(row)%2: row.pop()
  pos.extend(row)
 if i>=7:
  for y in range(1,h-1):
   row=[(x,y,1) for x in range(1,w-1) if (x+y+i)%8!=0]
   if len(row)%2:row.pop()
   pos.extend(row)
 if i>=27:
  for y in range(2,h-2):
   row=[(x,y,2) for x in range(2,w-2)]
   if len(row)%2:row.pop()
   pos.extend(row)
 if len(pos)>144:
  # layerwise remove whole rows from highest layer until under 144
  while len(pos)>144:
   vals=sorted(set(y for x,y,z in pos if z==0),reverse=True)
   if not vals:break
   yy=vals[0]
   pos=[p for p in pos if not(p[1]==yy and p[2]==0)]
 return pos,shape,w,h

def construct_solution(pos,seed):
 rng=random.Random(seed)
 remaining=set(pos);order=[]
 for _ in range(len(pos)//2):
  free=free_positions(remaining)
  if len(free)<2: return None
  # favor pairing same row to avoid difficult stranded rows
  byrow={}
  for t in free:byrow.setdefault((t[1],t[2]),[]).append(t)
  rows=[a for a in byrow.values() if len(a)>=2]
  if not rows:return None
  pairs=rng.choice(rows)
  one=rng.choice(pairs);two=rng.choice([p for p in pairs if p!=one])
  remaining.remove(one);remaining.remove(two);order.append((one,two))
 return order

def stage_levels():
 out=BASE/'levels';out.mkdir(parents=True,exist_ok=True)
 all_levels=[];all_layouts=[];problem=[]
 regular=[name for name in TILE_IDS if not(name.startswith('flower_') or name.startswith('season_'))]
 pair_pool=[(tid,tid) for tid in regular for _ in range(2)]
 flower_keys=[f'flower_{s}' for s in FLOWERS];season_keys=[f'season_{s}' for s in SEASONS]
 pair_pool.extend([(flower_keys[0],flower_keys[1]),(flower_keys[2],flower_keys[3]),(season_keys[0],season_keys[1]),(season_keys[2],season_keys[3])])
 for i in range(50):
  pos,shape,w,h=make_layout(i)
  all_layouts.append({'id':f'layout_{i+1:03d}','shape':shape,'grid':[w,h],'position_count':len(pos),'positions':[list(p) for p in pos]})
 for i in range(150):
  layout=all_layouts[i%50];pos=[tuple(p) for p in layout['positions']]
  sol=None
  for offset in range(40):
   sol=construct_solution(pos,10000+i*761+offset)
   if sol is not None:break
  if sol is None:problem.append(i+1);continue
  rng=random.Random(9980+i)
  pool=pair_pool.copy();rng.shuffle(pool)
  pool=pool[:len(sol)]
  tiles={};solution=[]
  for (a,b),(face1,face2) in zip(sol,pool):
   tiles[a]=face1;tiles[b]=face2
   solution.append([list(a),list(b)])
  lvl={'id':i+1,'world':['aurora_garden','pearl_coast','crystal_nocturne'][i//50],
       'layout_id':layout['id'],'tile_count':len(pos),'board_bounds':[layout['grid'][0],layout['grid'][1]],
       'tiles':[{'x':x,'y':y,'z':z,'face':tiles[(x,y,z)]} for x,y,z in sorted(pos,key=lambda p:(p[2],p[1],p[0]))],
       'verified_solution':solution,'difficulty_band':'relaxed' if i<20 else ('standard' if i<90 else 'challenge'),
       'note':'Solution verified by reverse-play; more solutions may exist. Flower and season groups match internally.'}
  # verify every step of the known solution
  remaining=set(pos);assert len(remaining)==len(tiles)
  for a,b in sol:
   frees=free_positions(remaining)
   assert a in frees and b in frees,(i,a,b)
   ga=tiles[a];gb=tiles[b]
   assert (ga==gb or (ga.startswith('flower_') and gb.startswith('flower_')) or (ga.startswith('season_') and gb.startswith('season_')))
   remaining.remove(a);remaining.remove(b)
  assert not remaining
  all_levels.append(lvl)
 (out/'layouts_50.json').write_text(json.dumps(all_layouts,ensure_ascii=False,indent=2))
 (out/'levels_001_150_verified.json').write_text(json.dumps(all_levels,ensure_ascii=False,separators=(',',':')))
 (out/'verification_report.json').write_text(json.dumps({'levels_generated':len(all_levels),'unverified':problem,'verified':len(all_levels),'verification_method':'Legal open-side and uncovered-state solution replay; each remaining tile position removed exactly once.'},indent=2))
 (out/'tile_match_rules.json').write_text(json.dumps({'standard_matching':'identical face ids','bonus_matching':{'flower':['flower_'+x for x in FLOWERS],'season':['season_'+x for x in SEASONS]},'free_tile_rule':'No tile at (x,y,z+1), plus at least one of (x-1,y,z) and (x+1,y,z) is empty','tile_coordinate_system':'positive integer grid x,y,z; layers overlap exactly','limitations':'A solvable starting arrangement can become unsolvable after arbitrary moves; engine must provide undo/shuffle/rescue'},ensure_ascii=False,indent=2))
 if len(all_levels)!=150:raise RuntimeError(f'Generated only {len(all_levels)} levels, failed:{problem}')
 print('LEVELS',len(all_levels),'verified layouts',len(all_layouts),flush=True)

# --- High-res screen composition previews for handoff and visual QA ---
FONT_REG='/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
FONT_BOLD='/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'
FONT_SERIF='/usr/share/fonts/truetype/dejavu/DejaVuSerif.ttf'
def font(sz=32,bold=False,serif=False):return ImageFont.truetype(FONT_SERIF if serif else (FONT_BOLD if bold else FONT_REG),sz)

def over(im,overlay,xy,size=None,opacity=1):
 if not isinstance(overlay,Image.Image):overlay=Image.open(BASE/overlay).convert('RGBA')
 else:overlay=overlay.convert('RGBA')
 if size:overlay=overlay.resize(size,Image.Resampling.LANCZOS)
 if opacity<1:overlay.putalpha(overlay.getchannel('A').point(lambda x:round(x*opacity)))
 im.alpha_composite(overlay,xy)

def rr(draw,rect,radius,fill,outline=None,width=1):draw.rounded_rectangle(rect,radius=radius,fill=fill,outline=outline,width=width)

def text_at(d,xy,t,size=42,fill='#133E58',bold=False,anchor='mm',stroke=0,strokefill=None,serif=False):
 d.text(xy,t,font=font(size,bold,serif),fill=fill,anchor=anchor,stroke_width=stroke,stroke_fill=strokefill)

def panel(im,rect,radius=40,color=(255,252,240,247),border=(233,204,165,255)):
 d=ImageDraw.Draw(im)
 x1,y1,x2,y2=rect
 d.rounded_rectangle((x1+6,y1+12,x2+6,y2+12),radius=radius,fill=(15,65,74,50))
 d.rounded_rectangle(rect,radius=radius,fill=color,outline=border,width=5)

def button(im,xy,label,kind='green',size=(440,146),sizefont=49):
 file=f'ui/buttons/{kind}_large_normal.png';over(im,file,xy,size)
 d=ImageDraw.Draw(im)
 text_at(d,(xy[0]+size[0]/2,xy[1]+size[1]*.45),label,sizefont,'#FFFFFF' if kind!='cream' else '#214A67',bold=True,stroke=1,strokefill='#2E6D6D')

def badge(im,xy,name,size=80):over(im,f'ui/rewards/{name}.png',xy,(size,size))

def circleicon(im,xy,name,filled='#FDF7E9',icon_color='navy'):
 d=ImageDraw.Draw(im)
 d.ellipse((xy[0],xy[1],xy[0]+94,xy[1]+94),fill=filled,outline='#FDFDFB',width=5)
 over(im,f'ui/icons/{icon_color}/{name}.png',(xy[0]+21,xy[1]+20),(52,52))

def base(w='aurora_garden',mode='world'):
 filename=('backgrounds/gameplay/'+w+'_soft_1080x1920.png' if mode=='game' else ('backgrounds/maps/'+w+'_map_1080x1920.png' if mode=='map' else 'backgrounds/worlds/'+w+'_1080x1920.png'))
 return Image.open(BASE/filename).convert('RGBA')

def hud(im,level=None,top=20):
 d=ImageDraw.Draw(im)
 rr(d,(34,top+22,370,top+118),52,(17,72,79,205),outline=(226,255,245,190),width=3)
 badge(im,(42,top+26),'coin',84);text_at(d,(174,top+70),'1,250',36,'#FFFFFF',True)
 rr(d,(711,top+22,1045,top+118),52,(17,72,79,205),outline=(226,255,245,190),width=3)
 badge(im,(721,top+26),'gem',84);text_at(d,(865,top+70),'30',36,'#FFFFFF',True)

def navbar(im,active='Home'):
 d=ImageDraw.Draw(im)
 rr(d,(15,1745,1065,1915),47,(255,250,235,246),outline=(255,255,255,255),width=6)
 nav=[('Home','home'),('Worlds','worlds'),('Daily','daily'),('Collection','collection'),('Shop','shop')]
 for i,(name,ic) in enumerate(nav):
  x=110+i*213
  if name==active:rr(d,(x-78,1763,x+79,1897),33,(223,250,243,244))
  over(im,f'ui/icons/navy/{ic}.png',(x-36,1773),(72,72))
  text_at(d,(x,1880),name,25,'#15516A' if active==name else '#557C88',bold=(name==active))

def make_preview(name):
 w='aurora_garden'
 if name in ('level_complete',):w='crystal_nocturne'
 if name in ('tile_collections','shop'):w='pearl_coast'
 im=base(w,'game' if name=='gameplay' else ('map' if name=='world_map' else 'world'))
 d=ImageDraw.Draw(im)
 if name=='splash':
  # very quiet splash with large original logo
  overlay=Image.new('RGBA',im.size,(253,244,234,0)); layer=ImageDraw.Draw(overlay)
  layer.rectangle((0,200,1080,910),fill=(252,247,241,80));im=Image.alpha_composite(im,overlay)
  over(im,'branding/veya_logo_stacked_dark.png',(193,335),(694,427))
  button(im,(260,1486),'Play','green',size=(560,176),sizefont=65)
  d=ImageDraw.Draw(im);text_at(d,(540,1693),'MATCH · BLOOM · RELAX',30,'#FFFFFF',bold=True,stroke=1,strokefill='#337181')
 elif name=='home':
  hud(im);over(im,'branding/veya_logo_stacked_dark.png',(285,190),(510,310))
  panel(im,(175,1152,905,1365),56)
  d=ImageDraw.Draw(im);text_at(d,(540,1218),'Aurora Garden',48,'#244E67',True);text_at(d,(540,1291),'Continue Level 12',39,'#367C88')
  button(im,(273,1410),'Play','green',size=(534,170),sizefont=60)
  navbar(im,'Home')
 elif name=='gameplay':
  hud(im);d=ImageDraw.Draw(im)
  text_at(d,(65,201),'LEVEL 25',51,'#FFFFFF',True,anchor='lm')
  circleicon(im,(934,161),'pause')
  d.rounded_rectangle((65,261,452,285),radius=12,fill=(14,90,86,150));d.rounded_rectangle((65,261,329,285),radius=12,fill='#FFD06A')
  basefaces=['character_1','character_7','wind_east','circle_5','bamboo_4','dragon_red','flower_plum','character_9','circle_6','bamboo_6','wind_north','bamboo_2','flower_orchid','wind_west','dragon_green']
  # tall board compact enough for one-hand play, all sprites independent
  tile_width,tile_height=134,171;x0,y0=199,408
  for j in range(5):
   for i in range(5):
    face=basefaces[(i*3+j*5)%len(basefaces)]
    over(im,f'tiles/classic/png_256/{face}.png',(x0+i*tile_width,y0+j*141),(tile_width,tile_height))
  # upper layer across middle
  for j in range(3):
   for i in range(3):
    face=basefaces[(i+j*2+7)%len(basefaces)]
    over(im,f'tiles/classic/png_256/{face}.png',(x0+tile_width+i*tile_width-10,y0+152+j*141),(tile_width,tile_height))
  rr(d,(120,1498,959,1715),55,(11,86,91,180),outline=(177,255,241,120),width=3)
  for i,(action,lab) in enumerate([('shuffle','Shuffle'),('hint','Hint'),('undo','Undo')]):
   xx=235+i*304
   rr(d,(xx-70,1510,xx+70,1650),34,(89,146,231,245),outline=(255,255,255,240),width=5)
   over(im,f'ui/icons/white/{action}.png',(xx-40,1538),(80,80))
   text_at(d,(xx,1686),lab,31,'#FFFFFF',True)
 elif name=='world_map':
  hud(im);panel(im,(248,181,832,351),39)
  d=ImageDraw.Draw(im);text_at(d,(540,247),'Aurora Garden',49,'#1C4B65',True);text_at(d,(540,311),'CHAPTER 1',30,'#5B8996',True)
  spots=[(530,1540,1),(400,1400,2),(610,1240,3),(450,1070,4),(655,900,5),(475,720,6),(625,550,7)]
  for x,y,n in spots:
   over(im,'ui/components/round_green.png',(x-70,y-70),(140,140));text_at(d,(x,y-12),str(n),43,'#FFFFFF',True)
   if n<=5:
    for k in range(3):
     badge(im,(x-44+k*30,y+35),'star',32)
  navbar(im,'Worlds')
 elif name=='level_complete':
  overlayer=Image.new('RGBA',im.size,(17,25,61,100));im=Image.alpha_composite(im,overlayer)
  d=ImageDraw.Draw(im);text_at(d,(540,348),'Level Complete!',70,'#FFFFFF',True)
  for x,y,s in [(290,500,165),(455,448,205),(680,500,165)]:badge(im,(x,y),'star',s)
  panel(im,(139,832,941,1349),61)
  d=ImageDraw.Draw(im);text_at(d,(540,926),'REWARDS',44,'#2A5973',True)
  badge(im,(259,1020),'coin',166);badge(im,(641,1020),'gem',166)
  text_at(d,(343,1262),'+60',49,'#22516C',True);text_at(d,(722,1262),'+1',49,'#22516C',True)
  button(im,(256,1415),'Next Level','green',size=(570,175),sizefont=50)
 elif name=='daily_challenges':
  im=Image.new('RGBA',(1080,1920),'#FDF5E3');d=ImageDraw.Draw(im)
  circleicon(im,(50,72),'back');badge(im,(850,70),'flower',120)
  text_at(d,(540,233),'Daily Challenges',60,'#1A4D66',True)
  text_at(d,(540,313),'Fresh Mahjong moments every day',27,'#6B8592')
  items=[('Play 3 levels','2 / 3','gem',.66),('Clear 5 flower tiles','5 / 5','star',1.0),('Finish without hints','0 / 1','coin',0)]
  for i,(label,progress,icon,val) in enumerate(items):
   y=410+i*310;panel(im,(67,y,1013,y+270),40)
   badge(im,(90,y+63),icon,112)
   text_at(d,(250,y+86),label,35,'#234F69',True,anchor='lm')
   rr(d,(258,y+143,791,y+191),24,'#E1D3B9')
   if val>0:rr(d,(258,y+143,258+int(533*val),y+191),24,'#46C191')
   text_at(d,(533,y+167),progress,29,'#FFFFFF' if val else '#667981',True)
  panel(im,(67,1424,1013,1720),40)
  text_at(d,(540,1498),'WEEKLY REWARD',38,'#2D5B70',True)
  for k in range(7):
   x=191+k*116
   badge(im,(x-32,1558),'star' if k<4 else 'coin',64)
   text_at(d,(x,1655),f'Day {k+1}',25,'#527789')
  navbar(im,'Daily')
 elif name=='tile_collections':
  im=Image.new('RGBA',(1080,1920),'#B6E2EC');d=ImageDraw.Draw(im)
  rr(d,(0,0,1080,295),35,'#347DA3');circleicon(im,(48,67),'back')
  text_at(d,(540,136),'Tile Collections',56,'#FFFFFF',True)
  text_at(d,(540,243),'All      Nature      Seasonal      Special',28,'#E4F5FF',True)
  choices=[('Classic','classic','character_1'),('Sakura','sakura','flower_plum'),('Ocean','ocean','circle_5'),('Nocturne','nocturne','dragon_green'),('Bamboo','classic','bamboo_5'),('Blossom','sakura','flower_orchid')]
  for j,(label,theme,tid) in enumerate(choices):
   xx=44+(j%3)*346;yy=357+(j//3)*463
   panel(im,(xx,yy,xx+306,yy+413),30)
   over(im,f'tiles/{theme}/png_256/{tid}.png',(xx+45,yy+39),(216,276))
   text_at(d,(xx+153,yy+356),label,31,'#1D5571',True)
  navbar(im,'Collection')
 elif name=='veya_bloom':
  panel(im,(34,85,1046,330),50)
  d=ImageDraw.Draw(im);text_at(d,(540,167),'Veya Bloom',64,'#245A72',True);text_at(d,(540,256),'Build your peaceful garden',32,'#567C85')
  panel(im,(58,1432,1022,1717),46)
  text_at(d,(540,1504),'Garden Discovery — 12 / 20',36,'#20536B',True)
  for i,(asset,label) in enumerate([('blossom_pink','Flowers'),('stone_lantern','Lantern'),('sakura_tree','Tree'),('bridge','Bridge')]):
   xx=101+i*235;rr(d,(xx,1558,xx+185,1684),24,'#F5E8CF')
   over(im,f'decorations/{asset}_256.png',(xx+44,1558),(98,100))
   text_at(d,(xx+90,1664),label,23,'#31576B')
  navbar(im,'Worlds')
 elif name=='shop':
  im=Image.new('RGBA',(1080,1920),'#C2E9EE');d=ImageDraw.Draw(im)
  rr(d,(0,0,1080,271),40,'#277FA3')
  text_at(d,(540,112),'Veya Boutique',57,'#FFFFFF',True)
  hud(im,top=120)
  panel(im,(60,359,1020,941),50)
  text_at(d,(540,445),'Welcome Bundle',53,'#22526E',True)
  badge(im,(292,536),'coin',150);badge(im,(481,526),'gem',160);badge(im,(680,536),'gift',145)
  text_at(d,(540,767),'Extra themes · Coins · Gems',33,'#396E7C')
  button(im,(356,802),'$4.99','green',size=(366,119),sizefont=39)
  for i,(item,ico,price) in enumerate([('Coin Pack','coin','$2.99'),('Gem Pack','gem','$2.99')]):
   xx=61+i*494;panel(im,(xx,1002,xx+460,1450),42)
   text_at(d,(xx+230,1070),item,39,'#285269',True)
   badge(im,(xx+146,1132),ico,168)
   button(im,(xx+82,1312),price,'green',size=(296,105),sizefont=35)
  navbar(im,'Shop')
 elif name=='settings':
  im=Image.new('RGBA',(1080,1920),'#FFF9EF');d=ImageDraw.Draw(im)
  circleicon(im,(48,64),'back');text_at(d,(540,146),'Settings',62,'#234D67',True)
  items=[('Music',True),('Sound Effects',True),('Vibration',True),('Reduce Motion',False),('High Contrast',False)]
  for j,(label,on) in enumerate(items):
   y=302+j*151;rr(d,(76,y,1004,y+127),33,'#FFFFFF',outline='#EDE1D2',width=4)
   text_at(d,(125,y+65),label,37,'#264D62',anchor='lm')
   over(im,'ui/components/toggle_on.png' if on else 'ui/components/toggle_off.png',(830,y+25),(130,73))
  text_at(d,(120,1138),'Graphics Quality',37,'#235269',True,anchor='lm')
  for j,lab in enumerate(('Low','Medium','High')):
   x=135+j*290;rr(d,(x,1194,x+252,1296),25,'#3F9CB6' if j==0 else '#E5E4DE')
   text_at(d,(x+126,1246),lab,31,'#FFFFFF' if j==0 else '#426A79',True)
  for j,lab in enumerate(('Language','Support','Privacy Policy','Terms of Service')):
   y=1358+j*120;rr(d,(78,y,1000,y+102),22,'#FFFFFF',outline='#EEE5D8',width=3);text_at(d,(119,y+52),lab,32,'#345C70',anchor='lm')
 else:raise ValueError(name)
 out=BASE/'previews/screens';out.mkdir(parents=True,exist_ok=True)
 im.convert('RGB').save(out/(name+'_1080x1920.png'),optimize=True)
 return out/(name+'_1080x1920.png')

def stage_previews():
 names=['splash','home','gameplay','world_map','level_complete','daily_challenges','tile_collections','veya_bloom','shop','settings']
 for name in names:
  try:make_preview(name);print('SCREEN',name,flush=True)
  except Exception as e:print('SCREEN FAIL',name,e);raise
 # beautiful overview contact sheet with legible labels and reduced screens
 thumbw,thumbh=320,569
 canvas=Image.new('RGB',(4*thumbw+5*28,3*(thumbh+64)+45),'#EAF5F4');d=ImageDraw.Draw(canvas)
 for n,name in enumerate(names):
  x=28+(n%4)*(thumbw+28);y=25+(n//4)*(thumbh+64)
  im=Image.open(BASE/f'previews/screens/{name}_1080x1920.png').resize((thumbw,thumbh),Image.Resampling.LANCZOS)
  canvas.paste(im,(x,y));d.rounded_rectangle((x-2,y-2,x+thumbw+2,y+thumbh+2),radius=13,outline='#548CA6',width=4)
  text_at(d,(x+thumbw//2,y+thumbh+32),name.replace('_',' ').title(),24,'#1B4D66',True)
 out=BASE/'previews';canvas.save(out/'contact_sheet.png')
 # marketing feature graphic 1024x500, not an actual screenshot
 bg=Image.open(BASE/'backgrounds/worlds/aurora_garden_1080x1920.png').crop((0,330,1080,1350)).resize((1024,500),Image.Resampling.LANCZOS).convert('RGBA')
 mask=Image.new('RGBA',(1024,500),(0,0,0,0));dm=ImageDraw.Draw(mask)
 dm.rounded_rectangle((30,44,639,457),45,fill=(250,246,236,235))
 bg=Image.alpha_composite(bg,mask)
 over(bg,'branding/veya_logo_stacked_dark.png',(140,84),(371,230))
 dd=ImageDraw.Draw(bg)
 text_at(dd,(340,370),'Match. Bloom. Relax.',34,'#315E74',True)
 for j,tid in enumerate(['flower_plum','dragon_red','circle_5']):
  over(bg,f'tiles/classic/png_256/{tid}.png',(677+j*93,123+j*36),(145,190))
 p=BASE/'marketing';p.mkdir(parents=True,exist_ok=True)
 bg.convert('RGB').save(p/'google_play_feature_graphic_1024x500_CONCEPT.png')
 # square promo
 square=Image.open(BASE/'backgrounds/worlds/aurora_garden_1080x1920.png').crop((0,150,1080,1230)).convert('RGBA')
 ov=Image.new('RGBA',(1080,1080),(255,248,230,0));D=ImageDraw.Draw(ov);D.rounded_rectangle((74,90,1006,940),60,fill=(255,247,236,185))
 square=Image.alpha_composite(square,ov);over(square,'branding/veya_logo_stacked_dark.png',(210,120),(660,405))
 for j,tid in enumerate(['flower_plum','wind_east','bamboo_6']):over(square,f'tiles/classic/png_256/{tid}.png',(270+j*174,580+j*15),(178,228))
 square.convert('RGB').save(p/'social_square_1080.png')
 print('PREVIEWS',len(names),'screens + marketing',flush=True)

def finalize_pack():
 import xml.etree.ElementTree as ET
 # store icons: make full opaque (no baked rounded iOS silhouette/alpha)
 ic=Image.open(BASE/'branding/app_icon_master_1024.png').convert('RGBA')
 W=1024
 g=Image.new('RGBA',(W,W),(0,0,0,255));pix=g.load()
 for y in range(W):
  for x in range(W):
   v=(x+y)/(2*(W-1));pix[x,y]=(int(119+(134-119)*v),int(213+(132-213)*v),int(230+(223-230)*v),255)
 flattened=Image.alpha_composite(g,ic).convert('RGB')
 flattened.save(BASE/'app_icons/ios/AppIcon_1024.png',optimize=True)
 flattened.resize((512,512),Image.Resampling.LANCZOS).save(BASE/'app_icons/android/play_store_icon_512.png',optimize=True)
 # adaptive icon: transparent foreground with the tile/blossom mark, centered inside Android safe zone
 fg=svg(432,432,'''
 <g transform="translate(216,218) rotate(-8)">
 <rect x="-82" y="-116" width="164" height="235" rx="28" fill="#E9C9AC"/>
 <rect x="-82" y="-123" width="164" height="226" rx="28" fill="url(#ivory)" stroke="#DFC4A8" stroke-width="6"/>
 </g>'''+blossom(216,214,57,'#F58CB8')+leaf(186,270,30,-40)+leaf(258,278,30,45))
 save_svg('app_icons/android/adaptive_foreground_master.svg',fg,{'_432':(432,432)})
 (BASE/'app_icons/android/adaptive_foreground_master_432.png').replace(BASE/'app_icons/android/adaptive_foreground_432.png')
 # opaque legacy launcher icon density variants
 sizes={'mipmap-mdpi':48,'mipmap-hdpi':72,'mipmap-xhdpi':96,'mipmap-xxhdpi':144,'mipmap-xxxhdpi':192}
 for nm,n in sizes.items():
  p=BASE/'app_icons/android'/nm;p.mkdir(parents=True,exist_ok=True)
  flattened.resize((n,n),Image.Resampling.LANCZOS).save(p/'ic_launcher.png')
 # splash static assets + favicon
 shutil.copy(BASE/'previews/screens/splash_1080x1920.png',BASE/'branding/splash_screen_1080x1920_CONCEPT.png')
 f=BASE/'app_icons/web';f.mkdir(parents=True,exist_ok=True)
 flattened.save(f/'favicon.ico',sizes=[(16,16),(32,32),(48,48)])
 # reference mood boards already generated in this conversation; no direct cut-up into tile sprites
 refs=BASE/'references';refs.mkdir(parents=True,exist_ok=True)
 reference_files=[
  ('/mnt/data/a_bright_colorful_polished_2d_casual_game_ui_moc.png','original_ui_concept_reference.png'),
  ('/mnt/data/a_wide_clean_high_resolution_ui_ux_game_asset_sh.png','visual_moodboard_01.png'),
  ('/mnt/data/a_high_resolution_flat_ui_asset_sheet_game_desig.png','visual_moodboard_02.png')]
 for src,nm in reference_files:
  if Path(src).exists():shutil.copy(src,refs/nm)
 # asset/game config
 cf=BASE/'config';cf.mkdir(parents=True,exist_ok=True)
 config={
  'title':'Veya Mahjong','genre':'Mahjong Solitaire','default_orientation':'portrait',
  'rendering':{'engine':'Godot 4.x','recommended_renderer':'Compatibility','target_fps':60,'low_end_target_fps':30,
               'original_background_resolution':[1080,1920],'low_end_background_resolution':[540,960],
               'tile_size_source':[256,328],'tile_size_low':[128,164],'pixel_filter':'linear',
               'use_runtime_3d':False,'particle_budget':'small','prefer_atlases':True},
  'gameplay':{'timer_required':False,'offline_first':True,'optional_undo':True,'hint_available':True,'shuffle_requires_solvable_result':True,
              'allow_resume':True,'bonus_tile_matching':'flowers match any flower; seasons match any season'},
  'economy':{'mandatory_ads':False,'lives_system':False,'pay_to_unblock':False,'currency_costs_not_defined':True},
  'design':{'palette':C,'art_direction':'Lightweight crisp 2D, bright matte porcelain tiles, subtle bevel/shadow, calm pastel backgrounds'}
 }
 (cf/'game_ui_config.json').write_text(json.dumps(config,indent=2,ensure_ascii=False))
 worlds=[
  {'id':'aurora_garden','name':'Aurora Garden','chapter':1,'levels':[1,50],'bg':'backgrounds/worlds/aurora_garden_1080x1920.png','map':'backgrounds/maps/aurora_garden_map_1080x1920.png','music':'audio/music/aurora_garden_loop.ogg','default_tile_theme':'classic'},
  {'id':'pearl_coast','name':'Pearl Coast','chapter':2,'levels':[51,100],'bg':'backgrounds/worlds/pearl_coast_1080x1920.png','map':'backgrounds/maps/pearl_coast_map_1080x1920.png','music':'audio/music/pearl_coast_loop.ogg','default_tile_theme':'ocean'},
  {'id':'crystal_nocturne','name':'Crystal Nocturne','chapter':3,'levels':[101,150],'bg':'backgrounds/worlds/crystal_nocturne_1080x1920.png','map':'backgrounds/maps/crystal_nocturne_map_1080x1920.png','music':'audio/music/crystal_nocturne_loop.ogg','default_tile_theme':'nocturne'}]
 (cf/'worlds.json').write_text(json.dumps(worlds,indent=2))
 (cf/'tile_catalog.json').write_text(json.dumps({'themes':list(THEMES),'tile_ids':TILE_IDS,'normal_tiles_count':34,'bonuses':['flower_*','season_*'],'tile_dimensions':[256,328]},ensure_ascii=False,indent=2))
 (cf/'animation_specs.json').write_text(json.dumps({'tap_duration_ms':90,'match_duration_ms':220,'win_animation_max_ms':1200,'animations':{'match_sparkle':{'frames':12,'fps':20},'petal_pop':{'frames':12,'fps':20},'ripple':{'frames':12,'fps':20},'gold_twinkle':{'frames':12,'fps':20}},'reduced_motion':'skip or shorten particles, preserve game state transitions'},indent=2))
 translations={
 'en':{'app_name':'Veya Mahjong','app_tagline':'Match. Bloom. Relax.','play':'Play','continue':'Continue','next_level':'Next Level',
 'level':'Level','chapter':'Chapter','level_complete':'Level Complete!','rewards':'Rewards','home':'Home','worlds':'Worlds','daily':'Daily',
 'collection':'Collection','shop':'Shop','settings':'Settings','daily_challenges':'Daily Challenges','tile_collections':'Tile Collections',
 'veya_bloom':'Veya Bloom','bloom_subtitle':'Build your peaceful garden','world_aurora':'Aurora Garden','world_coast':'Pearl Coast',
 'world_nocturne':'Crystal Nocturne','shuffle':'Shuffle','hint':'Hint','undo':'Undo','restart':'Restart','resume':'Resume',
 'no_moves':'No moves available','no_moves_help':'Use Undo or Shuffle to keep playing.','match_two_free':'Match two free tiles',
 'music':'Music','sound_effects':'Sound Effects','vibration':'Vibration','graphics_quality':'Graphics Quality',
 'reduce_motion':'Reduce Motion','high_contrast':'High Contrast','language':'Language','support':'Support',
 'privacy_policy':'Privacy Policy','terms_of_service':'Terms of Service','low':'Low','medium':'Medium','high':'High',
 'collection_unlocked':'New tile theme unlocked!','journey':'Journey','beautiful':'Beautiful!','daily_puzzle':'Daily Puzzle',
 'world_unlock':'New World Unlocked!','coins':'Coins','gems':'Gems','starter_pack':'Starter Pack','no_ads':'Remove Ads',
 'play_three_levels':'Play 3 levels','clear_flower_tiles':'Clear 5 flower tiles','finish_without_hints':'Finish 1 level without hints',
 'next_discovery':'Next Garden Discovery','pause':'Paused','loading':'Loading...','error_generic':'Something went wrong. Please try again.'},
 'he':{'app_name':'Veya Mahjong','app_tagline':'מתאימים. פורחים. נרגעים.','play':'שחקו','continue':'המשך','next_level':'השלב הבא',
 'level':'שלב','chapter':'פרק','level_complete':'השלב הושלם!','rewards':'פרסים','home':'בית','worlds':'עולמות','daily':'יומי',
 'collection':'אוסף','shop':'חנות','settings':'הגדרות','daily_challenges':'אתגרים יומיים','tile_collections':'אוסף אריחים',
 'veya_bloom':'Veya Bloom','bloom_subtitle':'בונים גן קסום בכל שלב','world_aurora':'גן הזוהר','world_coast':'חוף הפנינה',
 'world_nocturne':'ליל הקריסטלים','shuffle':'ערבוב','hint':'רמז','undo':'ביטול','restart':'התחלה מחדש','resume':'המשך',
 'no_moves':'לא נותרו מהלכים','no_moves_help':'אפשר לבטל מהלך או לערבב ולהמשיך לשחק.','match_two_free':'התאימו שני אריחים פנויים',
 'music':'מוזיקה','sound_effects':'אפקטים קוליים','vibration':'רטט','graphics_quality':'איכות גרפיקה',
 'reduce_motion':'צמצום תנועה','high_contrast':'ניגודיות גבוהה','language':'שפה','support':'תמיכה',
 'privacy_policy':'מדיניות פרטיות','terms_of_service':'תנאי שימוש','low':'נמוכה','medium':'בינונית','high':'גבוהה',
 'collection_unlocked':'עיצוב אריחים חדש נפתח!','journey':'מסע','beautiful':'מקסים!','daily_puzzle':'האתגר היומי',
 'world_unlock':'עולם חדש נפתח!','coins':'מטבעות','gems':'יהלומים','starter_pack':'ערכת התחלה','no_ads':'הסרת פרסומות',
 'play_three_levels':'שחקו 3 שלבים','clear_flower_tiles':'הסירו 5 אריחי פרחים','finish_without_hints':'סיימו שלב ללא רמזים',
 'next_discovery':'התגלית הבאה בגן','pause':'המשחק מושהה','loading':'טוען...','error_generic':'משהו השתבש. נסו שוב.'}
 }
 for lang,content in translations.items():
  p=BASE/'localization';p.mkdir(parents=True,exist_ok=True)
  (p/(lang+'.json')).write_text(json.dumps({'locale':lang,'rtl':lang=='he','strings':content},ensure_ascii=False,indent=2),encoding='utf8')
 # Asset mapping per screen
 screen_bindings={
  'Splash':['branding/veya_logo_stacked_dark.png','backgrounds/worlds/aurora_garden_1080x1920.png','ui/buttons/green_large_normal.png'],
  'Home':['branding/veya_logo_stacked_dark.png','ui/components/nav_bar.png','ui/components/hud_pill.png','ui/rewards/coin.png','ui/rewards/gem.png'],
  'Gameplay':['tiles/{theme}/png_256/{tile_id}.png','backgrounds/gameplay/{world}_soft_1080x1920.png','ui/icons/white/hint.png','ui/icons/white/shuffle.png','ui/icons/white/undo.png'],
  'WorldMap':['backgrounds/maps/{world}_map_1080x1920.png','ui/components/round_green.png','ui/rewards/star.png'],
  'Bloom':['backgrounds/worlds/{world}_1080x1920.png','decorations/*_256.png','ui/rewards/light.png'],
  'Win':['ui/components/panel_cream.png','ui/rewards/star.png','ui/rewards/coin.png','ui/rewards/gem.png','ui/buttons/green_large_normal.png'],
  'Daily':['ui/components/card_cream.png','ui/components/bar_fill_green.png','ui/icons/navy/daily.png'],
  'Collections':['tiles/{theme}/png_256/{tile_id}.png','ui/components/card_cream.png','ui/icons/navy/collection.png'],
  'Settings':['ui/components/toggle_on.png','ui/components/toggle_off.png','ui/icons/navy/settings.png'],
  'Shop':['ui/components/panel_cream.png','ui/rewards/coin.png','ui/rewards/gem.png','ui/buttons/green_large_normal.png']
 }
 (cf/'screen_asset_bindings.json').write_text(json.dumps(screen_bindings,ensure_ascii=False,indent=2))
 # Docs
 readme_he='''# Veya Mahjong — ערכת Assets מלאה v1.0

## מה יש בקובץ?
ערכת נכסים מקורית למשחק Mahjong Solitaire ב־Godot, מותאמת לעיצוב 2D צבעוני וקליל ולמכשירים חלשים.

- **tiles/** — 42 סוגי אריחים מסורתיים בכל אחת מ־4 ערכות: Classic / Sakura / Ocean / Nocturne. כל אריח בקובץ SVG עצמאי, PNG 256×328 ו־PNG 128×164, בנוסף ל־Atlases ומיפוי JSON.
- **backgrounds/** — 3 עולמות מקוריים ב־SVG, שתי רזולוציות PNG, רקעים מטושטשים ללוחות המשחק ומפות עולמות.
- **branding/** ו־**app_icons/** — לוגואים, אייקוני iOS/Android, adaptive icons וגרסאות דפדפן.
- **ui/** — כפתורים במצבים רגיל/לחוץ/מושבת, אייקונים נפרדים, רכיבי HUD, פאנלים, פסי התקדמות ופרסים.
- **decorations/** — 26 אובייקטים מאוירים בנפרד, כולל עצים, גשר, ביתן, בריכה, פרחים ועוד.
- **effects/** — ארבע אנימציות חלקיקים קלילות, 12 פריימים כל אחת, ואטלסים.
- **audio/** — 13 אפקטים קוליים מקוריים ושלוש לולאות מוזיקה שקטות ב־OGG.
- **levels/** — 50 Layouts ו־150 שלבי דוגמה עם פתרון שנבדק על ידי שחזור הסרת כל זוג.
- **config/** ו־**localization/** — קובצי JSON לתכנון מסכים, צבעים, עולמות, כללי התאמה ותרגום אנגלית/עברית.
- **previews/screens/** — 10 מסכי תצוגה להמחשה; **אינם צילומי מסך מאפליקציה פועלת**.
- **marketing/** — נכסי קונספט לפרסום ולחנות (יש לוודא התאמה לתוצר הסופי ולדרישות החנות).
- **references/** — תמונות הקונספט המלאות שנוצרו בתחילת העבודה; השראה בלבד ולא sprite sheet מוכן.
- **tools/** — הסקריפט שמייצר את רוב הנכסים מחדש.

## שימוש ב־Godot
1. העתיקו את תיקיות הנכסים לפרויקט Godot 4.x בתיקיית `res://assets/`.
2. השתמשו בקובצי PNG בזמן ריצה. קובצי SVG הם מקורות עריכה — גליפים סיניים ולטיניים הומרו ל־paths כדי להימנע מתלות בפונטים.
3. הציגו את ה־Game Board כ־Node2D ואת המסכים וה־HUD בעזרת Control.
4. השתמשו ב־Compatibility Renderer. בטלפונים חלשים: `png_128` ו־`540x960` והגבלת FPS ל־30 אם נחוץ.
5. שימו לב ל־RTL בעברית, לאזורים בטוחים (Safe Areas) ולגדלים דינמיים.
6. אטלסי האריחים מלווים במיפוי פיקסלים מדויק JSON. צבע או עיצוב לא צריכים לשנות את לוגיקת ההתאמה.

## הבדלי חוקי המשחק
- משפחות רגילות תואמות רק לזהות בדיוק.
- כל שני Flowers יכולים להתאים; כל שני Seasons יכולים להתאים.
- אריח פנוי אם אין אריח מעליו, והצד הימני או השמאלי פנוי.
- הדאטה משתמש בקואורדינטות רשת מיושרות, לא בחפיפה חלקית בין תאים.
- פתרון התחלתי מוכח לא מבטיח שכל מסלול מהלכים יצליח — נדרשים Undo/Shuffle/Rescue במנוע המשחק.

## מה לא כלול / מה עדיין צריך לפתח
זו **ערכת נכסים**, לא פרויקט Godot עובד. עדיין יש לממש לוגיקת משחק, סצנות וממשק חי, שמירה/טעינה, תשלומים ו־Ads, שירותי פרטיות, Analytics, בדיקות משתמשים ונגישות, תוספת תוכן, צילומי חנות אמיתיים, ולבסוף QA על מכשירי iOS/Android. לחבילה אין פונטים להפצה (בכוונה). ה־synth music הוא נכס מקורי אך רצוי לבדוק את התאמתו לחוויית המשחק.

## נקודות מקצועיות
- לוחות הדוגמה אינם איזון קושי סופי; מדדי Challenge דורשים playtesting.
- מכניקת Veya Bloom היא שכבת Meta שתיבנה בקוד. כאן נמצאים הרקעים והאובייקטים שלה.
- הכיתוב VEYA בשם המותג וסימני המסחר דורשים בדיקה לפני פרסום.
- חומרי `references` הם הדמיות אמנותיות; אין לחתוך מהם אריחים במקום קובצי ה־SVG/PNG העצמאיים.
- גרפיקת האייקונים מקורית ובנויה מחלקים וקטוריים, ללא שימוש בנכסים של Vita Mahjong.
'''
 readme_en='''# Veya Mahjong — 2D Production-Oriented Asset Pack v1.0

This is an editable, lightweight **game asset kit**, not an executable Godot game.

Folder quick reference: `tiles/` (42 faces × 4 themes × PNG 128/256 + SVG + atlases), `backgrounds/` (3 worlds, maps, gameplay), `ui/` (buttons, panels, icons, HUD, rewards), `branding/`, `app_icons/`, `decorations/` (26), `effects/` (4 12-frame atlases), `audio/` (13 sound effects + 3 loops), `levels/` (150 validated demo stages), `localization/` (EN/HE), `config/` (UI, worlds, bindings), `previews/` (10 design mockups), `marketing/`, `references/`, `tools/`.

Use Godot 4.x with Compatibility Renderer for older phones, runtime PNG textures from `png_128` or `png_256`, and 540px or 1080px backgrounds. SVG sources have text outlined as paths. No fonts are redistributed. The asset names and binding JSON files are intended to simplify the next implementation step.

Sample levels have a proven initial removal sequence; arbitrary player moves can still dead-end. In the engine implement Undo, Hint, a verified-solvable Shuffle/Rescue, pause/resume, save, localization, dynamic safe areas, accessibility, native store and ads, GDPR/consent as applicable and device testing.

Store previews are CONCEPT art until actual gameplay matches. Validate App Store/Google Play compliance, licensing, trademark and marketing details before publishing.
'''
 (BASE/'README_HE.md').write_text(readme_he,encoding='utf8')
 (BASE/'README_EN.md').write_text(readme_en,encoding='utf8')
 (BASE/'GODOT_HANDOFF.md').write_text('''# Godot implementation handoff

**Import root:** `res://assets/veya/` (copy these folders beneath it). Recommended 2D Compatibility renderer. Example tile path: `res://assets/veya/tiles/classic/png_128/character_5.png`.

**Gameplay screen:** Base canvas reference 1080×1920 (responsive aspect; no hard-coded positions); tile art aspect 256:328; logical coordinates from `levels/levels_001_150_verified.json`. Source sprite has small padding and shadow. Keep visual tile sprites distinct from logical hitboxes, so tile selection feels reliable.

**Tiles:** `tiles/atlases/classic_128_atlas.png` and matching `.json` let a Texture2D atlas be subdivided accurately. Each tile uses `face`, `x`, `y`, `z` and separate match-group semantics for Flowers/Seasons. The provided step-by-step solution is a verified witness, not a forced autoplay path.

**UI:** Render button labels with Godot FontFile or DynamicFont chosen/licensed by developer. Source vector icons have no embedded font dependencies. PNG buttons are label-free to enable translation. Separate state PNGs exist. Nineslice panels should be evaluated with `NinePatchRect` and tuned corner margins around 30-45 logical pixels, adapting from the 512/640px SVG sources.

**Performance:** Load one world background/theme at a time. Use the 540×960 variants on low-end Android, 128×164 tiles, sprite atlases, 30 FPS low-end fallback, ≤12 particles visible per match, stop particle emissions on reduced motion. Disable filtering at very small glyph sizes only after device evaluation. Target memory usage and FPS must be benchmarked with real phones.

**World system:** Each world has `worlds/...` a full background, `gameplay/...` subdued background, `maps/...` path art, `audio/music/...` loop. Place world decoration sprites in game as editable separate nodes.

**Audio:** `audio/AUDIO_MAP.json` maps event names to WAV files and 24-second OGG loops. Set loops to loop playback; actual cross-fade may be required on target devices.

**Accessibility:** large tappable hitboxes, Reduce Motion, High Contrast, one-hand portrait handling, left-to-right and right-to-left layouts, hint controls without paywalls, accessibility labels.

**Not implemented:** No actual Godot project, scenes, SFX event playback, persistence, backend, IAP/Ads, privacy flows or Play Store/App Store signing are included. The next coding prompt should explicitly request those systems and validate their status separately.
''')
 (BASE/'ART_DIRECTION.md').write_text('''# Art direction — Veya Mahjong

Modern colorful casual Mahjong, lightweight 2D, premium through consistency instead of expensive effects.

## Mood
Warm porcelain tiles, rounded cream cards, sea-blue/teal backgrounds, cherry blossom pink, violet accents, soft gold reward moments. Never obscure match symbols with ornaments.

## Do
- Preserve clear Chinese character glyphs and strong visual differences among bamboo/circle/character suits.
- Keep interface uncluttered in gameplay; use large and forgiving hit boxes.
- Prefer 2D sprite atlases and low shader budgets, original backgrounds and independent decor sprites.
- Use limited tap animations (90ms) and match transitions (220ms), optional particles.
- Keep premium visual language via spacing, soft shading, pleasant transitions, no 3D.

## Avoid
- Busy backgrounds behind tile stacks; intense glitter; animation loops on every decor element.
- Using moodboard composites as in-game sprites (they contain text baked in / inconsistent scales).
- Fixed-position UI assuming every screen has 1080×1920 safe zone.
- Dependent texts embedded into button PNGs; all dynamic labels should be drawn by the game.

## Brand colors
`#765AC7`, `#49BDB7`, `#F4A3C7`, `#F4C568`, `#FFF8EC`, `#153D56`.
''')
 (BASE/'LICENSE_AND_ORIGINS.md').write_text('''# Asset origin and rights notes

All independent SVG art, PNG exports, procedurally generated Mahjong arrangements and synthesized audio in this package were generated specifically for this project through original geometric/vector procedures and sound synthesis. The three artwork images in `references/` were generated in this conversation as concept moodboards and are not to be treated as cut-ready game sprites.

The project draws on traditional Mahjong Solitaire gameplay and traditional tile symbol conventions. It does not intentionally reproduce a competitor's logo, proprietary illustrations, screens, sounds, branded text or assets.

No font binaries are provided: outline SVG paths were converted from fonts available in the working environment. The PNG rasterizations are self-contained. Use a properly licensed font in your game project for runtime UI text.

This is not a trademark clearance or legal certification. Confirm `Veya Mahjong` availability, third-party service licenses, privacy/ads/IAP obligations and app-store requirements before commercial publication.
''')
 # Include reproducible generator, not third-party fonts
 toolroot=BASE/'tools';toolroot.mkdir(parents=True,exist_ok=True)
 shutil.copy('/mnt/data/veya_work/build_assets.py',toolroot/'build_assets.py')
 (toolroot/'README.md').write_text('''The script `build_assets.py` generates most original artwork, audio, screen comps and Mahjong demo layouts. Requires Python with Pillow, fontTools, cairosvg, numpy, ffmpeg and font files available in your environment for outlining glyphs. Those font files are **not** redistributed. Generated reference moodboards are separate conversation artifacts. Running the script uses hard-coded `/mnt/data/veya_work` output paths; change `BASE` before rerunning elsewhere. Stages can be run by importing the module and calling `stage_worlds`, `stage_tiles`, `stage_brand_ui`, `stage_decor_fx`, `stage_atlases`, `stage_audio`, `stage_levels`, `stage_previews`, `finalize_pack`.\n''')
 # remove stale interrupted prototype preview, not a real named screen
 stray=BASE/'previews/screens/undo_1080x1920.png'
 if stray.exists():stray.unlink()
 # manifest enumerates exported assets with precise dimensions and sizes
 media=[]
 for p in sorted(BASE.rglob('*')):
  if not p.is_file():continue
  entry={'path':str(p.relative_to(BASE)),'size_bytes':p.stat().st_size,'extension':p.suffix.lower()}
  if p.suffix.lower()=='.png':
   try:
    with Image.open(p) as img:entry['pixels']=[img.width,img.height];entry['alpha']=img.mode in ('RGBA','LA')
   except Exception as e:entry['error']=str(e)
  media.append(entry)
 (BASE/'ASSET_MANIFEST.json').write_text(json.dumps({'app':'Veya Mahjong','version':'1.0.0','asset_count':len(media),'assets':media},indent=2,ensure_ascii=False))
 print('FINALIZE',len(media),'files before manifest',flush=True)


def validate_and_zip():
 import xml.etree.ElementTree as ET
 bad=[];kinds=Counter()
 root=BASE
 for f in root.rglob('*'):
  if not f.is_file():continue
  kinds[f.suffix.lower()]+=1
  try:
   if f.suffix.lower()=='.png':
    with Image.open(f) as im:im.verify()
   if f.suffix.lower()=='.svg':ET.parse(f)
   if f.suffix.lower()=='.json':json.loads(f.read_text(encoding='utf8'))
  except Exception as e:bad.append((str(f.relative_to(root)),str(e)))
 # direct essential file check
 must=['app_icons/ios/AppIcon_1024.png','tiles/atlases/classic_128_atlas.png',
       'backgrounds/worlds/aurora_garden_540x960.png','previews/contact_sheet.png',
       'levels/levels_001_150_verified.json','audio/music/aurora_garden_loop.ogg',
       'localization/he.json','ui/buttons/green_large_normal.png']
 for rel in must:
  if not (root/rel).exists():bad.append((rel,'missing critical file'))
 levels=json.loads((root/'levels/levels_001_150_verified.json').read_text());assert len(levels)==150
 # ffprobe all compressed sounds
 for ogg in (root/'audio/music').glob('*.ogg'):
  proc=subprocess.run(['ffprobe','-v','error','-show_entries','format=duration','-of','default=noprint_wrappers=1:nokey=1',str(ogg)],capture_output=True,text=True)
  if proc.returncode:bad.append((ogg.name,'audio decoding error'))
 # check alpha/opaque correctness in app icons
 with Image.open(root/'app_icons/ios/AppIcon_1024.png') as im:
  if im.mode !='RGB':bad.append(('AppIcon_1024','iOS icon not opaque RGB'))
 with Image.open(root/'app_icons/android/adaptive_foreground_432.png') as im:
  if im.getpixel((0,0))[3]!=0:bad.append(('adaptive_foreground','Android FG missing alpha'))
 report={'asset_count':sum(kinds.values()),'by_extension':dict(kinds),'unique_tile_faces':len(TILE_IDS),
         'tile_themes':list(THEMES),'levels_verified':len(levels),'preview_screens':10,
         'errors':bad,'ready_for_godot_import':not bad,
         'disclaimer':'Art package validated; not an executable game or certified store submission.'}
 (root/'QA_REPORT.json').write_text(json.dumps(report,indent=2))
 if bad:raise RuntimeError('Asset validation failed: '+str(bad[:10]))
 zipfile_path=Path('/mnt/data/Veya_Mahjong_Full_Assets_v1.zip')
 with zipfile.ZipFile(zipfile_path,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=7) as z:
  for f in sorted(root.rglob('*')):
   if f.is_file():z.write(f,arcname='VeyaMahjong_AssetPack_v1/'+str(f.relative_to(root)))
 # test archive: CRC check, named entries
 with zipfile.ZipFile(zipfile_path) as z:
  err=z.testzip();assert err is None,err
  assert len(z.namelist())>1000
 print('ZIP_READY',zipfile_path,'bytes',zipfile_path.stat().st_size,'members',len(z.namelist()),'report',report,flush=True)
 return zipfile_path
