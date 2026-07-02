#!/usr/bin/env python3
"""Extract the unique top-level messages from a Gmail-print email thread PDF.

Gmail's "print all" export repeats the entire quoted history under every message,
so an N-message thread balloons to hundreds of pages of near-duplicate text. This
script keeps only the *new* content each message added (the part above the first
quoted block) and drops the page chrome and signature trailers.

Usage:
    extract_thread.py <thread.pdf> [-o OUT] [--format md|json|txt]

Detection anchors on the recipient ("To:") line of each top-level Gmail message,
walking up (skipping blank lines) to the date and sender lines. This tolerates:
  - blank lines inserted between sender / date / To:,
  - dates truncated by Gmail's layout ("Mon, Ju", "Th", or even empty),
  - and rejects quoted Outlook "From:/Sent:/To:" blocks (a To: whose sender line
    is itself preceded by a "Sent:" line is quoted history, not a new message).

Truncated/empty header dates are reconstructed from the full dates that survive in
the quoted history: Gmail "On <date> at <time> ... wrote:" lines (recipient TZ, exact)
and Outlook "Sent: <date>" blocks (sender TZ). The recipient/sender timezone offset
is auto-detected by matching messages that carry both forms, so reconstructed dates
stay consistent with the rest of the thread. Exact times are shown only when known
from a Gmail "On ... wrote:" line; otherwise the calendar date alone is shown.
"""
import argparse, json, re, sys, datetime

MON3={'Jan':1,'Feb':2,'Mar':3,'Apr':4,'May':5,'Jun':6,'Jul':7,'Aug':8,'Sep':9,'Oct':10,'Nov':11,'Dec':12}
FULLMON={'January':1,'February':2,'March':3,'April':4,'May':5,'June':6,'July':7,
         'August':8,'September':9,'October':10,'November':11,'December':12}
I2M={v:k for k,v in MON3.items()}
WD={0:'Mon',1:'Tue',2:'Wed',3:'Thu',4:'Fri',5:'Sat',6:'Sun'}

SENDER_BAD_PREFIX=('From:','To:','Cc:','Sent:','Subject:','On ','<','>')
ONWROTE=re.compile(r'^On .*wrote:\s*$')
SIGNOFF=re.compile(r'^(best regards|regards|thanks|thanks in advance|sincerely|cheers|br)[,!.]*$', re.I)
HARD=[re.compile(p) for p in [
    r'^(De Novo LLC|Kyiv, Ukraine)\b',
    r'^(phone|cell|mail|tel|fax|web|mobile)\s*:', r'^\+?\d[\d \-]{7,}\d$',
    r'^Head of ', r'^[\w.\-]+\.(ua|com|net|org|biz|io)$', r'^web:\s*http',
    r'^Якщо у Вас', r'^If you have any suggestions',
]]


def extract_text(pdf_path):
    try:
        import fitz  # PyMuPDF
    except ImportError:
        sys.exit("PyMuPDF not found. Install it (e.g. `pip install pymupdf`, ideally "
                 "in a venv) and re-run. See the skill's SKILL.md for the venv recipe.")
    doc = fitz.open(pdf_path)
    return [page.get_text() for page in doc]


def clean_lines(pages):
    """Drop Gmail print chrome and return a flat list of content lines."""
    out=[]
    for text in pages:
        for ln in text.split('\n'):
            s=ln.strip()
            if not s and not out: continue
            if s.startswith('https://mail.google.com/mail'): continue
            if re.match(r'^\d+/\d+$', s): continue                 # page counter "273/603"
            if re.match(r'^\d{1,2}/\d{1,2}/\d{2,4},\s', s): continue  # print timestamp line
            if ' Mail - ' in s: continue                            # running subject header
            out.append(ln.rstrip())
    return out


def is_sender(s):
    s=s.strip()
    return ('<' in s and '@' in s and s.endswith('>')
            and not s.startswith(SENDER_BAD_PREFIX))


def nb_up(lines, i):
    """Index of the nearest non-blank line above i (or -1)."""
    j=i-1
    while j>=0 and not lines[j].strip(): j-=1
    return j


def find_headers(lines):
    """Top-level messages: a 'To:' line, with sender/date above (blanks allowed),
    that is NOT a quoted Outlook block."""
    heads=[]
    for i,ln in enumerate(lines):
        s=ln.strip()
        if not (s.startswith('To:') and '@' in s): continue
        a=nb_up(lines,i)
        if a<0: continue
        da=lines[a].strip()
        if is_sender(da):
            sidx=a; date=''
        else:
            b=nb_up(lines,a)
            if b>=0 and is_sender(lines[b]):
                sidx=b; date=da
            else:
                continue
        p=nb_up(lines,sidx)
        if p>=0 and lines[p].strip().startswith('Sent:'):   # quoted Outlook header block
            continue
        heads.append({'to':i,'sidx':sidx,'date':date,'sender':lines[sidx].strip()})
    return heads


def author_of(sender_line):
    name=sender_line.split('<')[0].strip().strip('"')
    m=re.search(r'<([^>]+)>', sender_line)
    return name or (m.group(1) if m else ''), (m.group(1) if m else '')


def key(y,mon,d,mins): return ((y*12+mon)*31+d)*1440+mins
def t12(h,m,ap): return (int(h)%12 + (12 if ap=='PM' else 0))*60+int(m)


def parse_full_date(s):
    """(key, display, has_time) if s is a complete Gmail header date, else None."""
    m=re.match(r'^(Mon|Tue|Wed|Thu|Fri|Sat|Sun), (\w{3}) (\d{1,2}), (\d{4})'
               r'(?: at (\d{1,2}):(\d{2})\s*([AP]M))?$', s)
    if not m: return None
    mon=MON3.get(m.group(2))
    if not mon: return None
    d=int(m.group(3)); y=int(m.group(4))
    if m.group(5):
        mins=t12(m.group(5),m.group(6),m.group(7))
        return key(y,mon,d,mins), f"{m.group(1)}, {m.group(2)} {d}, {y} at {int(m.group(5))}:{m.group(6)} {m.group(7)}", True
    return key(y,mon,d,0), f"{m.group(1)}, {m.group(2)} {d}, {y}", False


def parse_partial(s):
    """(weekday, month_idx, day, year) from a possibly-truncated header date."""
    wd=mon=day=yr=None
    m=re.match(r'^(Mon|Tue|Wed|Thu|Fri|Sat|Sun)', s)
    if m: wd=m.group(1)
    m=re.search(r'(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\w* (\d{1,2})', s)
    if m: mon=MON3[m.group(1)]; day=int(m.group(2))
    m=re.search(r'(\d{4})', s)
    if m: yr=int(m.group(1))
    return wd,mon,day,yr


def collect_on(full):
    """Gmail 'On <date> at <time> <sender> wrote:' -> recipient-TZ, exact time."""
    out=[]
    for m in re.finditer(r'On (Mon|Tue|Wed|Thu|Fri|Sat|Sun), (\w{3}) (\d{1,2}), (\d{4}) at '
                         r'(\d{1,2}):(\d{2})\s*[ ]?([AP]M)\s+(.+?)\s+wrote:', full):
        mon=MON3[m.group(2)]; d=int(m.group(3)); y=int(m.group(4))
        mins=t12(m.group(5),m.group(6),m.group(7))
        me=re.search(r'<([^>]+)>', m.group(8))
        out.append({'y':y,'mon':mon,'d':d,'mins':mins,'wd':m.group(1),
                    'email':me.group(1) if me else '', 'name':m.group(8).split('<')[0].strip().strip('"'),
                    'disp':f"{m.group(1)}, {m.group(2)} {d}, {y} at {int(m.group(5))}:{m.group(6)} {m.group(7)}",
                    'exact':True})
    return out


def collect_sent(lines):
    """Outlook 'From:/Sent:' quoted blocks -> sender-TZ local times."""
    out=[]
    for i,ln in enumerate(lines):
        m=re.match(r'Sent:\s+\w+,\s+(\w+)\s+(\d{1,2}),\s+(\d{4})\s+(\d{1,2}):(\d{2})\s*([AP]M)', ln.strip())
        if not m: continue
        mon=FULLMON.get(m.group(1))
        if not mon: continue
        d=int(m.group(2)); y=int(m.group(3)); mins=t12(m.group(4),m.group(5),m.group(6))
        email=''; nm=''
        f=lines[i-1].strip() if i>0 else ''
        if f.startswith('From:'):
            me=re.search(r'<([^>]+)>', f); email=me.group(1) if me else ''
            nm=f[5:].split('<')[0].strip().strip('"')
        out.append({'y':y,'mon':mon,'d':d,'mins':mins,'email':email,'name':nm})
    return out


def detect_tz_shift(heads, sent):
    """Recipient-minus-sender minute offset, from messages present as both a full
    Gmail header date and an Outlook Sent: line (same sender, same calendar day)."""
    samples=[]
    for h in heads:
        fd=parse_full_date(h['date'])
        if not fd or not fd[2]: continue
        m=re.match(r'^(\w{3}), (\w{3}) (\d{1,2}), (\d{4}) at (\d{1,2}):(\d{2}) ([AP]M)$', h['disp_full'])
        nm,em=author_of(h['sender'])
        hk=fd[0]; hday=hk//1440; htod=hk%1440
        for s in sent:
            if not ((em and s['email']==em) or (nm and s['name']==nm)): continue
            if key(s['y'],s['mon'],s['d'],0)//1440 != hday: continue
            samples.append(htod - s['mins'])
    if not samples: return 0
    samples.sort()
    return samples[len(samples)//2]


def build_corpus(on, sent, shift):
    corp=[]
    for e in on:
        corp.append({'key':key(e['y'],e['mon'],e['d'],e['mins']),'wd':e['wd'],
                     'email':e['email'],'name':e['name'],'disp':e['disp'],'exact':True})
    for e in sent:
        dt=datetime.datetime(e['y'],e['mon'],e['d'])+datetime.timedelta(minutes=e['mins']+shift)
        corp.append({'key':key(dt.year,dt.month,dt.day,dt.hour*60+dt.minute),'wd':WD[dt.weekday()],
                     'email':e['email'],'name':e['name'],
                     'disp':f"{WD[dt.weekday()]}, {I2M[dt.month]} {dt.day}, {dt.year}",'exact':False})
    uniq={}
    for c in corp: uniq.setdefault((c['key'],c['email'] or c['name'],c['disp']), c)
    return sorted(uniq.values(), key=lambda c:c['key'])


def reconstruct(heads, corpus):
    used=[False]*len(corpus)
    floor=0
    for h in heads:
        h['key']=None
        fd=parse_full_date(h['date'])
        if fd:
            h['key'],h['disp'],_=fd; floor=max(floor,h['key']); continue
        nm,em=author_of(h['sender'])
        wd,mon,day,yr=parse_partial(h['date'])
        pick=None
        for idx,c in enumerate(corpus):
            if used[idx] or c['key']<floor: continue
            if not ((em and c['email']==em) or (nm and c['name']==nm)): continue
            if wd and c['wd']!=wd: continue
            if mon and day and f"{I2M[mon]} {day}," not in c['disp']: continue
            pick=idx; break
        if pick is not None:
            used[pick]=True; h['key']=corpus[pick]['key']; h['disp']=corpus[pick]['disp']; floor=h['key']
    # interpolate the rest by calendar between known neighbours
    n=len(heads)
    for i,h in enumerate(heads):
        if h.get('key') is not None: continue
        wd,mon,day,yr=parse_partial(h['date'])
        lo=next((heads[j]['key'] for j in range(i-1,-1,-1) if heads[j].get('key') is not None), None)
        hi=next((heads[j]['key'] for j in range(i+1,n) if heads[j].get('key') is not None), None)
        cand=None
        if lo is not None:
            lo_d=lo//1440; hi_d=(hi//1440) if hi is not None else lo_d+10
            for dk in range(lo_d, hi_d+1):
                d=dk%31; rest=dk//31; mon_=rest%12; y=rest//12
                if d<1 or mon_<1: continue
                try: dt=datetime.date(y,mon_,d)
                except ValueError: continue
                if wd and WD[dt.weekday()]!=wd: continue
                if day and d!=day: continue
                if mon and mon_!=mon: continue
                cand=(y,mon_,d); break
        if cand:
            y,mon_,d=cand
            h['key']=key(y,mon_,d,0); h['disp']=f"{WD[datetime.date(y,mon_,d).weekday()]}, {I2M[mon_]} {d}, {y}"
        else:
            h['key']=lo; h['disp']=h['date'] or '(date unknown)'
    return heads


def is_contact(s, name):
    if any(r.match(s) for r in HARD): return True
    if name and (s==name or s==name+'.'): return True
    if re.match(r'^[\w.\-]+@[\w.\-]+$', s): return True
    return False


def nameish(s):
    """A short line that looks like a signature name (1-4 capitalised tokens)."""
    toks=s.rstrip('.').split()
    if not (1<=len(toks)<=4): return False
    return all(re.match(r"^[A-ZА-ЯЇІЄҐ][\wʼ'’.\-]*$", t) for t in toks)


def extract_body(lines, to_idx, end, name):
    j=to_idx+1
    while j<end:
        s=lines[j].strip()
        if s.startswith(('To:','Cc:')): j+=1; continue
        # wrapped recipient list line: "Name" <email>, ... — address, no prose end
        if '@' in s and '<' in s and not s.endswith(('.',':','!','?')) and len(s)<200: j+=1; continue
        break
    body=[]
    for x in range(j,end):
        s=lines[x].rstrip(); st=s.strip()
        if st.startswith('From:') and (x+1<end and lines[x+1].strip().startswith('Sent:')): break
        if ONWROTE.match(st) or (st.startswith('On ') and st.endswith('wrote:')): break
        if st=='[Quoted text hidden]': continue
        if st.startswith('[УВАГА]') or st.startswith('або не знаєте'): continue
        if any(r.match(st) for r in HARD): break            # signature/footer block
        body.append(s)
    while body:   # pop trailing blank / sign-off / name / contact lines
        st=body[-1].strip()
        if st=='' or SIGNOFF.match(st) or is_contact(st,name) or nameish(st): body.pop()
        else: break
    return '\n'.join(body).strip()


def parse(pdf_path):
    pages=extract_text(pdf_path)
    lines=clean_lines(pages)
    full="\n".join(pages)
    heads=find_headers(lines)
    # stash full-date display (used for tz detection) before reconstruct overwrites
    for h in heads:
        fd=parse_full_date(h['date']); h['disp_full']=fd[1] if (fd and fd[2]) else ''
    sent=collect_sent(lines)
    shift=detect_tz_shift(heads, sent)
    corpus=build_corpus(collect_on(full), sent, shift)
    reconstruct(heads, corpus)
    starts=[h['sidx'] for h in heads]
    msgs=[]
    for k,h in enumerate(heads):
        end=starts[k+1] if k+1<len(heads) else len(lines)
        name,email=author_of(h['sender'])
        msgs.append({'index':k,'author':name,'email':email,
                     'date':h.get('disp') or h['date'],
                     'text':extract_body(lines,h['to'],end,name)})
    return msgs


def render_md(msgs, title):
    out=[f'# {title}', '', f'{len(msgs)} top-level messages extracted.', '']
    for m in msgs:
        out.append(f"## [{m['index']}] {m['author']} — {m['date']}")
        if m['email']: out.append(f"*{m['email']}*")
        out.append('')
        out.append(m['text'] if m['text'] else '_(no new content)_')
        out.append('')
    return '\n'.join(out)


def render_txt(msgs):
    blocks=[]
    for m in msgs:
        blocks.append(f"===== [{m['index']}] {m['author']} <{m['email']}> | {m['date']} =====\n{m['text']}")
    return '\n\n'.join(blocks)


def main():
    ap=argparse.ArgumentParser(description=__doc__,
                               formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('pdf')
    ap.add_argument('-o','--out', help='output file (default: stdout)')
    ap.add_argument('--format', choices=['md','json','txt'], default='md')
    args=ap.parse_args()

    msgs=parse(args.pdf)
    if not msgs:
        sys.exit("No top-level messages detected. The PDF may not be a Gmail print "
                 "export, or the layout differs — inspect the extracted text and adjust "
                 "find_headers() in this script.")

    if args.format=='json':
        data=json.dumps(msgs, ensure_ascii=False, indent=2)
    elif args.format=='txt':
        data=render_txt(msgs)
    else:
        import os
        data=render_md(msgs, os.path.splitext(os.path.basename(args.pdf))[0])

    if args.out:
        with open(args.out,'w') as f: f.write(data)
        print(f"Wrote {len(msgs)} messages -> {args.out}")
    else:
        print(data)

    from collections import Counter
    c=Counter(m['author'] for m in msgs)
    print("\n-- messages per author --", file=sys.stderr)
    for name,n in c.most_common():
        print(f"  {n:3d}  {name}", file=sys.stderr)


if __name__ == '__main__':
    main()
