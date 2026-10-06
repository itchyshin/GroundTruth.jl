from pathlib import Path
import csv,json,hashlib,math,sys,subprocess,copy
from statistics import NormalDist
A=Path(__file__).resolve().parent; ROOT=A.parent.parent
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read_json(p):return json.loads(p.read_text())
def emit(name,obj): (A/'report'/name).write_text(json.dumps(obj,indent=2,allow_nan=False)+'\n')
def data(name):
    fn='analytic' if name.startswith('analytic_limit') else name
    return [(float(v['x']),float(v['y'])) for v in csv.DictReader((A/'fixtures'/f'{fn}.csv').open())]
def sigmoid(z):return 1/(1+math.exp(-z)) if z>=0 else math.exp(z)/(1+math.exp(z))
def oracle(ds,alpha,beta):
    nll=sa=sb=iaa=iab=ibb=0.
    for x,y in ds:
        eta=alpha+beta*x;p=sigmoid(eta);w=p*(1-p)
        nll+=max(eta,0)-y*eta+math.log1p(math.exp(-abs(eta)))
        sa+=y-p;sb+=x*(y-p);iaa+=w;iab+=x*w;ibb+=x*x*w
    det=iaa*ibb-iab*iab
    se=(math.sqrt(ibb/det),math.sqrt(iaa/det)) if det>0 else (math.nan,math.nan)
    return {'nll':nll,'score_alpha':sa,'score_beta':sb,'Iaa':iaa,'Iab':iab,'Ibb':ibb,'se':se,'det':det}
def close(x,y,atol=1e-7,rtol=1e-7):return math.isfinite(x) and math.isfinite(y) and abs(x-y)<=atol+rtol*abs(y)
def analytic():
    l0=math.log(.2/.8);l1=math.log(.7/.3)
    return ((l0+l1)/2,(l1-l0)/2)
def numeric(v):return float(v) if v not in ('',None) else math.nan
def keyed(rows):
    out={}
    for row in rows:
        key=(row['fixture'],row['engine'],row['target'])
        if key in out:raise AssertionError(f'duplicate target {key}')
        assert row['target'] in ('alpha','beta'),f'unknown target {key}'
        out[key]=row
    for f,e,_ in out:
        assert (f,e,'alpha') in out and (f,e,'beta') in out,f'missing target {(f,e)}'
    return out
def validate_pair(pair,ds,analytic_target=False):
    assert set(pair)=={'alpha','beta'},'missing target'
    errs=[]
    if any(pair[t]['status']!='ok' for t in pair):return ['fit rejected']
    b=tuple(numeric(pair[t]['estimate']) for t in ('alpha','beta'))
    if not all(math.isfinite(v) for v in b):return ['nonfinite coefficients']
    o=oracle(ds,*b)
    if o['det']<=0:errs.append('information not positive definite')
    if max(abs(o['score_alpha']),abs(o['score_beta']))>1e-7:errs.append('score exceeds frozen tolerance')
    for j,t in enumerate(('alpha','beta')):
        row=pair[t];se=numeric(row['se'])
        if not close(se,o['se'][j]):errs.append(f'{t}: final-information SE mismatch')
        for level in (.9,.95):
            q=NormalDist().inv_cdf((1+level)/2);suffix=str(round(level*100))
            for key,expected in [('lower'+suffix,b[j]-q*o['se'][j]),('upper'+suffix,b[j]+q*o['se'][j])]:
                if not close(numeric(row[key]),expected):errs.append(f'{t}: {key} mismatch')
        for key in ('Iaa','Iab','Ibb'):
            if not close(numeric(row[key]),o[key],1e-8,1e-7):errs.append(f'{t}: {key} mismatch')
        if not close(numeric(row['nll'])/len(ds),o['nll']/len(ds),1e-10,0):errs.append(f'{t}: normalized NLL mismatch')
        for key in ('score_alpha','score_beta'):
            if not close(numeric(row[key]),o[key],1e-8,1e-7):errs.append(f'{t}: {key} identity mismatch')
        if analytic_target:
            exact=analytic();eo=oracle(ds,*exact)
            if not close(b[j],exact[j],1e-10,0):errs.append(f'{t}: analytic coefficient mismatch')
            if not close(se,eo['se'][j],1e-10,0):errs.append(f'{t}: analytic SE mismatch')
            for level in (.9,.95):
                q=NormalDist().inv_cdf((1+level)/2);s=str(round(level*100))
                for k,v in [('lower'+s,exact[j]-q*eo['se'][j]),('upper'+s,exact[j]+q*eo['se'][j])]:
                    if not close(numeric(row[k]),v,1e-9,0):errs.append(f'{t}: analytic {k} mismatch')
    return errs
def all_rows():
    rows=[]
    for p in [A/'contract/custom.csv',A/'reference/glm.csv',A/'reference/glm-final.csv',A/'reference/r.csv']:
        with p.open() as f:rows+=list(csv.DictReader(f))
    return rows
def design_status(ds):
    xs=[x for x,y in ds]
    if len(set(xs))<2:return 'rank_deficient'
    zero=[x for x,y in ds if y==0];one=[x for x,y in ds if y==1]
    if not zero or not one:return 'no_finite_mle'
    # In this exact intercept+one-numeric-predictor design, disjoint or
    # touching convex hulls imply complete/quasi separation. Overlap plus
    # full rank ensures a unique finite MLE for these individual Bernoulli rows.
    if max(zero)<=min(one) or max(one)<=min(zero):return 'no_finite_mle'
    return 'finite_mle'
def recovery_acceptance(fixture,pair):
    ds=data(fixture);design=design_status(ds)
    if design!='finite_mle':return False,design
    if any(pair[t]['status']!='ok' for t in ('alpha','beta')):return False,'engine_rejected'
    b=tuple(numeric(pair[t]['estimate']) for t in ('alpha','beta'))
    if not all(math.isfinite(v) for v in b):return False,'invalid_point'
    o=oracle(ds,*b)
    if o['det']<=0 or max(abs(o['score_alpha']),abs(o['score_beta']))>1e-7:return False,'point_contract_failed'
    return True,'finite_mle_point_contract'
def check_acceptance_record(record,pair):
    expected,diagnosis=recovery_acceptance(record['fixture'],pair)
    return record['accepted_for_recovery'] is expected and record['acceptance_diagnosis']==diagnosis
def preservation():
    base=read_json(A/'baseline.json'); counts={};volatile=[];tool_cache_additions=[]
    allowed=('audit/logistic/','.unlazy/logistic-audit/')
    for label,b in base.items():
        if label not in ('isolated','canonical'):continue
        r=Path(b['root'])
        for name,h in b['files'].items():
            assert (r/name).is_file(),f'original missing: {label}/{name}'
            actual=digest(r/name)
            if actual!=h:
                # This chat's Graft connector owns a runtime-only, empty-index cache.
                # Enumerate the exception; never overwrite it or claim byte identity.
                assert label=='canonical' and name=='graft/.cache/stats.json',f'original changed: {label}/{name}'
                stats=read_json(r/name)
                assert stats['nodeCount']==0 and stats['edgeCount']==0 and stats['syncedAt'] is None
                session=r/'graft/.cache/session/01a10c36-a1fb-7811-b688-3933538e79bf.json'
                assert read_json(session)['lastQuery'].startswith('PLEASE IMPLEMENT THIS PLAN:')
                volatile.append({'file':str(r/name),'baseline_sha256':h,'current_sha256':actual,'disposition':'auto-generated empty Graft cache changed during this chat; left untouched; not scientific work'})
        assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=r,text=True).strip()==b['head'],'HEAD changed'
        assert digest(r/'.git/index')==b['index_sha256'],'index changed'
        names=set(subprocess.check_output(['git','ls-files','-z','--cached','--others','--exclude-standard'],cwd=r).decode().split('\0'))-{''}
        added=names-set(b['files'])
        for name in sorted(added.copy()):
            if name.startswith('graft/.cache/session/') and name.endswith('.json'):
                q=read_json(r/name)
                assert 'logistic audit' in q.get('lastQuery','').lower() or 'logistic mle audit' in q.get('lastQuery','').lower(),f'unowned runtime session {name}'
                tool_cache_additions.append({'file':str(r/name),'sha256':digest(r/name),'disposition':'runtime-generated session metadata for this audit; untouched'})
                added.remove(name)
            elif name=='graft/.cache/telemetry-repo-id.json':
                assert set(read_json(r/name))=={'repoId'}
                tool_cache_additions.append({'file':str(r/name),'sha256':digest(r/name),'disposition':'runtime-generated repository identifier; untouched'})
                added.remove(name)
        if label=='canonical':assert not added,f'canonical additions {added}'
        else:
            assert all(n.startswith(allowed) or n=='docs/dev-log/after-task/2026-10-05-logistic-audit.md' for n in added),f'out-of-scope additions {added}'
        counts[label]=len(b['files'])
    emit('preservation.json',{'baseline_counts':counts,'volatile_cache_exceptions':volatile,'tool_cache_additions':tool_cache_additions});print('LOGISTIC_PRESERVATION_OK',counts,'runtime_cache_exceptions=',len(volatile),'runtime_cache_additions=',len(tool_cache_additions))
def fixtures():
    hashes=read_json(A/'fixtures/hashes.json')
    assert len(hashes)==10
    for name,h in hashes.items():assert digest(A/'fixtures'/name)==h,name
    assert digest(A/'fixtures/retained.csv')==digest(ROOT/'results/extensions/logistic-rep1-data.csv')
    ds=data('analytic');a,b=analytic();o=oracle(ds,a,b)
    assert max(abs(o['score_alpha']),abs(o['score_beta']))<1e-13
    assert close(o['Iaa'],3.7,1e-13,0) and close(o['Iab'],.5,1e-13,0) and close(o['Ibb'],3.7,1e-13,0)
    for (x,y),(sx,sy) in zip(ds,data('scaled')):assert x*.01==sx and y==sy
    # Numeric derivatives are independently checked at a non-optimum parameter.
    h=1e-5;c=(.2,-.35);q=oracle(ds,*c)
    for j,key in enumerate(('score_alpha','score_beta')):
        plus=list(c);minus=list(c);plus[j]+=h;minus[j]-=h
        derivative=(oracle(ds,*plus)['nll']-oracle(ds,*minus)['nll'])/(2*h)
        assert abs(derivative+q[key])<1e-7
        for k,sk in enumerate(('score_alpha','score_beta')):
            derivative=(oracle(ds,*plus)[sk]-oracle(ds,*minus)[sk])/(2*h)
            ik=[['Iaa','Iab'],['Iab','Ibb']][j][k]
            assert abs(derivative+q[ik])<1e-8
    emit('fixtures.json',{'hashes':hashes,'analytic_alpha':a,'analytic_beta':b,'analytic_information':[[3.7,.5],[.5,3.7]],'fixed_point_derivatives':'passed'})
    print('LOGISTIC_FIXTURES_OK')
def controls():
    a,b=analytic();o=oracle(data('analytic'),a,b);rows=[]
    for j,t in enumerate(('alpha','beta')):
        v={'fixture':'analytic','engine':'control','target':t,'status':'ok','estimate':(a,b)[j],'se':o['se'][j],**{k:o[k] for k in ['nll','score_alpha','score_beta','Iaa','Iab','Ibb']}}
        for level in (.9,.95):
            q=NormalDist().inv_cdf((1+level)/2);s=str(round(level*100));v['lower'+s]=v['estimate']-q*v['se'];v['upper'+s]=v['estimate']+q*v['se']
        rows.append(v)
    def check(rs):
        ks=keyed(rs);return validate_pair({t:ks[('analytic','control',t)] for t in ('alpha','beta')},data('analytic'),True)
    assert not check(rows);assert not check(rows[::-1]);results={'valid':'pass','row_permutation':'pass'}
    for name in ('sign_flip','target_swap','initial_information','missing','duplicate'):
        rs=copy.deepcopy(rows)
        if name=='sign_flip':rs[1]['estimate']*=-1
        elif name=='target_swap':rs[0]['target']='beta';rs[1]['target']='alpha'
        elif name=='initial_information':
            for v in rs:
                v['se']=math.sqrt(.2)
                for l in (.9,.95):
                    q=NormalDist().inv_cdf((1+l)/2);s=str(round(l*100));v['lower'+s]=v['estimate']-q*v['se'];v['upper'+s]=v['estimate']+q*v['se']
        elif name=='missing':rs.pop()
        else:rs.append(copy.deepcopy(rs[0]))
        try:rejected=bool(check(rs))
        except AssertionError:rejected=True
        assert rejected,f'checker accepted {name}';results[name]='rejected'
    valid={t:rows[j] for j,t in enumerate(('alpha','beta'))}
    assert check_acceptance_record({'fixture':'analytic','accepted_for_recovery':True,'acceptance_diagnosis':'finite_mle_point_contract'},valid)
    # Use the same acceptance checker on a known no-finite-MLE positive
    # control and a deliberately incorrect accepted flag.
    assert not check_acceptance_record({'fixture':'complete','accepted_for_recovery':True,'acceptance_diagnosis':'finite_mle_point_contract'},valid)
    assert check_acceptance_record({'fixture':'complete','accepted_for_recovery':False,'acceptance_diagnosis':'no_finite_mle'},valid)
    results['false_acceptance_of_separated_fit']='rejected';results['separated_fit_excluded']='pass'
    emit('controls.json',results);print('LOGISTIC_CONTROLS_OK')
def seal():
    paths=['contract/run.jl','contract/accounting.jl','reference/run_glm.jl','reference/run_r.R','reference/rebuild_final.py','contract/custom.csv','contract/accounting.txt','reference/glm.csv','reference/glm-final.csv','reference/r.csv','contract/fixedpoint.csv','reference/glm-fixedpoint.csv','reference/r-fixedpoint.csv','contract.json','fixtures/hashes.json']
    record={n:digest(A/n) for n in paths}
    emit('run-seal.json',record);print('LOGISTIC_RUN_SEALED')
def references():
    sealed=read_json(A/'report/run-seal.json')
    for name,h in sealed.items():assert digest(A/name)==h,f'evidence stale: {name}'
    ks=keyed(all_rows());cfg=read_json(A/'contract.json');out=[];fixed=[]
    for path,engine in [('contract/fixedpoint.csv','custom'),('reference/glm-fixedpoint.csv','glm'),('reference/r-fixedpoint.csv','r')]:
        entries=list(csv.DictReader((A/path).open()))
        assert len(entries)==5
        for v in entries:
            assert v['engine']==engine
            o=oracle(data(v['fixture']),.2,-.35)
            for k in ['nll','score_alpha','score_beta','Iaa','Iab','Ibb']:
                assert close(numeric(v[k]),o[k],1e-10,1e-12),f'fixed-point discrepancy {engine}/{v["fixture"]}/{k}'
            fixed.append({'fixture':v['fixture'],'engine':engine,'result':'independent fixed-point identities matched'})
    for f in cfg['ordinary']+cfg['stress']:
        for e in ('custom','glm','r'):
            pair={t:ks[(f,e,t)] for t in ('alpha','beta')};statuses={v['status'] for v in pair.values()};assert len(statuses)==1
            status=next(iter(statuses));errs=validate_pair(pair,data(f),f=='analytic') if f in cfg['ordinary'] else []
            reason='ordinary fixture' if f in cfg['ordinary'] else ('finite MLE with coordinate-rescaled slope' if f=='scaled' else ('rank-deficient design' if f=='constant' else 'no finite MLE by fixture design'))
            if status!='ok':
                assert all(v['estimate']=='' and v['lower95']=='' for v in pair.values()),'failure leaked accepted estimate'
                assert any(v['message'] for v in pair.values()),'failure missing diagnostic'
            accepted,diagnosis=recovery_acceptance(f,pair)
            disposition='reproduced defect; fix plan required' if errs or (f=='scaled' and status!='ok') else ('expected engine limitation; capped iterate excluded from recovery' if diagnosis=='no_finite_mle' and status=='ok' else 'recorded and reviewed')
            record={'fixture':f,'engine':e,'status':status,'accepted_for_recovery':accepted,'acceptance_diagnosis':diagnosis,'ordinary_checks':errs,'interpretation':reason,'disposition':disposition}
            assert check_acceptance_record(record,pair)
            if f in ('complete','quasi','all_zero','all_one','constant'):assert not accepted,f'invalid stress acceptance {f}/{e}'
            out.append(record)
    final_outcomes=[]
    for f in cfg['ordinary']:
        pair={t:ks[(f,'glm_final',t)] for t in ('alpha','beta')}
        errors=validate_pair(pair,data(f),f=='analytic')
        final_outcomes.append({'fixture':f,'engine':'glm_final','errors':errors,'disposition':'explicit final-information reference agreement' if not errors else 'reproduced discrepancy; fix plan required'})
    agreement=[]
    for f in cfg['ordinary']:
        for left,right in [('custom','glm_final'),('custom','r'),('glm_final','r')]:
            errs=[]
            for t in ('alpha','beta'):
                v=ks[(f,left,t)];w=ks[(f,right,t)]
                for k in ('estimate','se','lower90','upper90','lower95','upper95'):
                    if not close(numeric(v[k]),numeric(w[k])):errs.append(f'{t}:{k}')
                if not close(numeric(v['nll'])/len(data(f)),numeric(w['nll'])/len(data(f)),1e-10,0):errs.append(f'{t}:mean_nll')
            agreement.append({'fixture':f,'left':left,'right':right,'differences':errs,'disposition':'reproduced discrepancy; fix plan required' if errs else 'agreement within frozen tolerances'})
    # Scale invariance of the reference engines, expressed on original units.
    scales=[]
    for e in ('glm','r'):
        errs=[]
        for t in ('alpha','beta'):
            ordinary=numeric(ks[('analytic',e,t)]['estimate']);scaled=numeric(ks[('scaled',e,t)]['estimate'])*(0.01 if t=='beta' else 1.)
            if not close(scaled,ordinary,1e-10,0):errs.append(t)
        scales.append({'engine':e,'errors':errs,'disposition':'recorded scale comparison'})
    limits=[]
    for e in ('custom','glm','r'):
        for f in (['analytic_limit0','analytic_limit1'] if e=='custom' else ['analytic_limit1']):
            pair={t:ks[(f,e,t)] for t in ('alpha','beta')}
            assert all(v['status']!='ok' and v['estimate']=='' for v in pair.values()),f'forced limit unexpectedly accepted {f}/{e}'
            limits.append({'fixture':f,'engine':e,'status':pair['alpha']['status'],'message':pair['alpha']['message']})
    defects=[v for v in out if v['ordinary_checks'] or (v['fixture']=='scaled' and v['engine']=='custom' and v['status']!='ok')]
    accepted_rows=[]
    for record in out:
        for t in ('alpha','beta'):
            raw=ks[(record['fixture'],record['engine'],t)]
            accepted_rows.append({'fixture':record['fixture'],'engine':record['engine'],'raw_status':record['status'],'accepted_for_recovery':record['accepted_for_recovery'],'diagnosis':record['acceptance_diagnosis'],'target':t,'estimate':raw['estimate'] if record['accepted_for_recovery'] else ''})
    with (A/'report/accepted-results.csv').open('w',newline='') as h:
        w=csv.DictWriter(h,fieldnames=list(accepted_rows[0]));w.writeheader();w.writerows(accepted_rows)
    assert sum(v['accepted_for_recovery'] for v in out)==14
    emit('references.json',{'outcomes':out,'final_information_outcomes':final_outcomes,'agreement':agreement,'scale_checks':scales,'fixed_point_checks':fixed,'iteration_limits':limits,'defects':defects,'recovery_acceptance_counts':{'attempted':len(out),'accepted':sum(v['accepted_for_recovery'] for v in out),'rejected':sum(not v['accepted_for_recovery'] for v in out),'no_finite_mle_engine_returns':sum(v['status']=='ok' and v['acceptance_diagnosis']=='no_finite_mle' for v in out)},'science_verdict':'bounded final-information agreement with reproduced native-covariance and solver limitations; all no-finite-MLE designs excluded from recovery' if not any(v['differences'] for v in agreement) and not any(v['errors'] for v in final_outcomes) else 'numerical discrepancies reproduced'})
    print('LOGISTIC_REFERENCES_AUDITED',len(out),'engine-fixture outcomes;',len(agreement),'ordinary comparisons;',len(defects),'defect outcomes')
def environment():
    j='/Users/z3437171/.julia/juliaup/julia-1.12.6+0.aarch64.apple.darwin14/Julia-1.12.app/Contents/Resources/julia/bin/julia'
    out=subprocess.check_output([j,'--startup-file=no','--compiled-modules=no','--pkgimages=no','--project='+str(ROOT),'-e','using GroundTruth, GLM; println("JULIA_VERSION=",VERSION); println("GLM_VERSION=",pkgversion(GLM))'],cwd=ROOT,text=True,timeout=120)
    assert 'JULIA_VERSION=1.12.6' in out and 'GLM_VERSION=1.9.5' in out,out
    rout=subprocess.check_output(['Rscript','--vanilla','-e','cat(R.version.string,"\\n")'],text=True,timeout=30)
    preservation();emit('environment.json',{'julia_glm':out.strip(),'R':rout.strip(),'threads':1,'settings':read_json(A/'contract.json')['settings']})
    print('LOGISTIC_ENVIRONMENT_OK')
def accounting():
    s=(A/'contract/accounting.txt').read_text();assert 'LOGISTIC_ACCOUNTING_OK' in s
    for t in ('alpha','beta'):assert t in s
    for v in ('attempted=4','successful=3','usable_intervals=2','coverage=0.5','covered_per_attempt=0.25'):assert s.count(v)==2,(v,s)
    print('LOGISTIC_ACCOUNTING_OK')
if __name__=='__main__':
    mode=sys.argv[1];assert mode in ('preservation','fixtures','controls','seal','references','environment','accounting')
    globals()[mode]()
