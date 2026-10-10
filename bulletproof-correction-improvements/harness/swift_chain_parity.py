"""Differential check: the Swift post-processing chain (cleanResponse + OutputGate.rejection)
against this harness's Python mirror, on stored (input, model output) pairs plus synthetic
perturbations (joined/added breaks, trailing spaces, expansions, unwrapped code, respelled
links, recasing, misplaced apostrophes, <text> wrappers, dropped words, typos).

Run from bulletproof-correction-improvements/:
  python3 harness/swift_chain_parity.py gen      # writes /tmp/parity-in.jsonl
  cp harness/ZZParityScratch.swift.template ../bulletproofTests/ZZParityScratch.swift
  (cd .. && TEST_RUNNER_BP_PARITY_IN=/tmp/parity-in.jsonl TEST_RUNNER_BP_PARITY_OUT=/tmp/parity-swift.jsonl \
     xcodebuild test -project bulletproof.xcodeproj -scheme bulletproof -destination 'platform=macOS' \
     -derivedDataPath /tmp/dd-main -only-testing:bulletproofTests/ZZParityScratch); rm ../bulletproofTests/ZZParityScratch.swift
  python3 harness/swift_chain_parity.py compare
Never commit the scratch test. #87: 0 differences on 5,849 pairs.
"""
import sys
if __name__ == "__main__" and sys.argv[1:2] == ["gen"]:
    import json,glob,random,re
    random.seed(86)
    inputs=[]
    for f in glob.glob('baseline-2026-10-09/corpus/*.jsonl')+glob.glob('*-2026-10-10/slice_*.jsonl')+['splits/guard.jsonl']:
        for l in open(f):
            c=json.loads(l); inputs.append((c['input'], c['id'].startswith('s3-')))
    inputs=list(dict.fromkeys(inputs))
    EXP={"don't":"do not","I'm":"I am","can't":"cannot","it's":"it is","we'll":"we will","won't":"will not","dont":"do not","im":"i am",
         "tmrw":"tomorrow","idk":"I don't know","u":"you","bc":"because","thx":"thanks","tbh":"to be honest","gonna":"going to","pls":"please"}
    def p_join(t): return t.replace('\n',' ',random.randint(1,3))
    def p_addbreak(t):
        w=[m.start() for m in re.finditer(' ',t)]
        if not w: return t
        i=random.choice(w); return t[:i]+'\n'+t[i+1:]
    def p_trail(t): return t.replace('\n','  \n')
    def p_expand(t):
        for k,v in random.sample(list(EXP.items()),len(EXP)):
            t2=re.sub(r'(?<![\w\'])'+re.escape(k)+r'(?![\w\'])',v,t,count=1)
            if t2!=t: return t2
        return t
    def p_backtick(t): return t.replace('`','',2) if random.random()<.5 else re.sub(r'`([^`]+)`',lambda m:'`'+m.group(1).replace('_','')+'`',t,count=1)
    def p_link(t): return re.sub(r'(https?://\S+|\S+@\S+\.\w+|#[A-Za-z]\w*|/[\w.]+/[\w./{}]+)',lambda m:m.group(0).replace('a','e',1).replace('t','tt',1),t,count=1)
    def p_case(t):
        r=random.random()
        if r<.33: return t[:1].upper()+t[1:]
        if r<.66: return t.capitalize()
        return re.sub(r'\b(\w)',lambda m:m.group(1).upper(),t,count=3)
    def p_aposts(t): return t.replace("n't","'t",1) if random.random()<.5 else t.replace("a lot","alot",1).replace("'","\u2019",2)
    def p_wrap(t): return '<text>'+t+'</text>' if random.random()<.5 else ' \n'+t+'\n'
    def p_punct(t): return t.rstrip('.!?')+random.choice(['.','!','',' 🙂','...'])
    def p_sentence(t): return '. '.join(s[:1].upper()+s[1:] for s in t.split(' ',1)) if ' ' in t else t
    def p_drop(t):
        w=t.split(' ')
        if len(w)<6: return t
        i=random.randrange(len(w)-3); return ' '.join(w[:i]+w[i+random.randint(2,5):])
    def p_typo(t):
        w=t.split(' ');i=random.randrange(len(w))
        if len(w[i])>3: w[i]=w[i][0]+w[i][2]+w[i][1]+w[i][3:]
        return ' '.join(w)
    P=[p_join,p_addbreak,p_trail,p_expand,p_backtick,p_link,p_case,p_aposts,p_wrap,p_punct,p_sentence,p_drop,p_typo]
    rows=[];seen=set()
    for inp,d in inputs:
        for k in range(8):
            t=inp
            for p in random.sample(P,random.randint(1,3)): t=p(t)
            if t==inp or (inp,t,d) in seen: continue
            seen.add((inp,t,d)); rows.append({"n":len(rows),"input":inp,"raw":t,"dictation":d})
    open('/tmp/parity-in.jsonl','w').write(''.join(json.dumps(x,ensure_ascii=False)+'\n' for x in rows))
    print(len(inputs),'inputs ->',len(rows),'synthetic pairs')
elif __name__ == "__main__" and sys.argv[1:2] == ["compare"]:
    sys.argv = sys.argv[:1] + sys.argv[2:]
    import json,sys,collections
    sys.path.insert(0,'harness'); import fast_eval as F
    inp=[json.loads(l) for l in open('/tmp/parity-in.jsonl')]
    sw={r['n']:r for r in map(json.loads,open('/tmp/parity-swift.jsonl'))}
    cd=[];gd=[]
    for r in inp:
        py=F.clean_response(r['raw'],r['input'],typed=not r['dictation'])
        pg=F.output_gate(r['input'],py) or ''
        s=sw[r['n']]
        if py!=s['clean']: cd.append((r,py,s['clean']))
        elif pg!=s['gate']: gd.append((r,pg,s['gate']))
    print(f"pairs {len(inp)}: cleanResponse differs {len(cd)}, gate differs (same clean) {len(gd)}")
    import difflib
    def show(a,b):
        sm=difflib.SequenceMatcher(None,a,b); return [(a[i1-8:i2+8],b[j1-8:j2+8]) for t,i1,i2,j1,j2 in sm.get_opcodes() if t!='equal'][:2]
    for r,py,s in cd[:int(sys.argv[1]) if len(sys.argv)>1 else 12]: print('  CLEAN', 'dict' if r['dictation'] else 'typed', repr(r['input'][:50]),'\n      py vs swift:',show(py,s))
    c=collections.Counter((p,s) for _,p,s in gd); print('gate diffs (py, swift):',c.most_common(8))
    for r,p,s in gd[:6]: print('  GATE',p,'|',s,repr(r['input'][:60]),'->',repr(r['raw'][:60]))
