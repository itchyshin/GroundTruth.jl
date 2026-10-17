"""Independent acceptance of native captures. Reads evidence, never launches engines."""
import csv,hashlib,json,math,sys
from pathlib import Path
from statistics import NormalDist
ROOT=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT/'oracle'))
from independent_gaussian import read_data,dense_reference,BlockModel
REFERENCE=json.loads((ROOT/'oracle/reference-with-profiles.json').read_text())['results']
MANIFEST=json.loads((ROOT/'fixtures/manifest.json').read_text())

def near(a,b,tol):return abs(a-b)<=tol*(1+abs(b))
def number(x):
    if x in ('','NA','missing','nothing','null',None):return math.nan
    return float(x)

def validate(path, allow_unbound=False):
    path=Path(path)
    if not allow_unbound:
        sidecar=json.loads(path.with_suffix('.json').read_text())
        assert sidecar['fixture_manifest_sha256']==hashlib.sha256((ROOT/'fixtures/manifest.json').read_bytes()).hexdigest(),'fixture manifest identity'
        assert sidecar.get('complete') is True,'incomplete native capture'
        assert sidecar['csv_sha256']==hashlib.sha256(path.read_bytes()).hexdigest(),'capture CSV identity'
        repo=path.parents[3]
        if sidecar['schema']=='groundtruth-r-inference-capture-v1':
            files=sorted(repo.glob('R/*.R'))
            payload='\n'.join(str(f.relative_to(repo))+'\t'+hashlib.sha256(f.read_bytes()).hexdigest() for f in files)
        elif sidecar['schema']=='groundtruth-julia-inference-capture-v1':
            files=sorted([*repo.glob('src/*.jl'),*repo.glob('adapters/lmm/*.jl')])
            payload='\n'.join(str(f.relative_to(repo))+'\0'+hashlib.sha256(f.read_bytes()).hexdigest() for f in files)
        else:raise AssertionError('unknown native capture schema')
        assert sidecar['source_sha256']==hashlib.sha256(payload.encode()).hexdigest(),'native capture source is stale'
        if sidecar['schema']=='groundtruth-julia-inference-capture-v1':
            assert sidecar['harness_sha256']==hashlib.sha256((repo/'scripts/inference-julia-capture.jl').read_bytes()).hexdigest(),'capture harness is stale'
    with path.open(newline='') as f:rows=list(csv.DictReader(f))
    required={'fixture','criterion','interval_method','target','level','estimate','sigma2','tau2','objective','cov11','cov12','cov22','lower','upper','state','base_status','engine_version'}
    assert rows and required<=rows[0].keys(), 'native capture schema'
    numerical_issues=[]
    def verify(condition,detail):
        if not condition:numerical_issues.append(detail)
    seen=set();findings=[];profile_endpoints=[];counts={'rows':len(rows),'rows_with_accepted_points':0,'finite_intervals':0,'typed_nonfinite':0,'interval_unavailable_after_accepted_point':0,'failed_point_rows':0,'state_counts':{}}
    for row in rows:
        name=row['fixture']; criterion=row['criterion']; method=row['interval_method']; target=row['target'].lstrip(':');level=number(row['level'])
        key=name,criterion,method,target,level
        if not allow_unbound and sidecar['schema']=='groundtruth-julia-inference-capture-v1':
            expected_route='adapter_direct' if method=='normal' else 'adapter_isolated' if name=='balanced_interior' else 'helper_inprocess_fixture_validation'
            assert row.get('execution_route')==expected_route,('execution route',key)
        assert key not in seen,('duplicate native capture key',key)
        seen.add(key)
        assert name in REFERENCE and criterion in ('ML','REML') and method in ('normal','profile') and target in ('alpha','beta') and level in (.9,.95),key
        assert not(criterion=='REML' and method=='profile'),key
        state=row['state'].lstrip(':')
        assert state in ('finite','unbounded','incomplete','error','timeout','invalid'),key
        counts['state_counts'][state]=counts['state_counts'].get(state,0)+1
        if state!='finite':counts['typed_nonfinite']+=1
        point=number(row['estimate']);s2=number(row['sigma2']);t2=number(row['tau2'])
        if not math.isfinite(point):
            assert state!='finite',key
            counts['failed_point_rows']+=1
            findings.append({'key':key,'kind':'base fit unavailable','status':row['base_status']})
            continue
        assert math.isfinite(s2) and s2>0 and math.isfinite(t2) and t2>=0,key
        counts['rows_with_accepted_points']+=1
        data=read_data(ROOT/'fixtures'/f'{name}.csv');reference=REFERENCE[name]['fits'][criterion]
        is_stress=name=='near_residual_collapse'
        unidentified=name=='two_group_group_x' and criterion=='REML'
        if not is_stress:
            own=dense_reference(data,s2,t2,criterion=criterion)
            verify(near(number(row['objective']), own['nll'], 1e-08), ('objective/convention', key, row['objective'], own['nll']))
            for column,ij in [('cov11',(0,0)),('cov12',(0,1)),('cov22',(1,1))]:
                verify(near(number(row[column]), own['covariance'][ij[0]][ij[1]], 1e-08), ('final covariance', key, column))
            j=0 if target=='alpha' else 1
            verify(near(point, reference['coefficients'][j], 1e-06), ('coefficient', key))
            verify(near(s2, reference['sigma2'], 1e-05), ('variance', key, 'sigma2', s2, reference['sigma2']))
            if not unidentified:
                verify(near(t2, reference['tau2'], 1e-05), ('variance', key, 'tau2', t2, reference['tau2']))
        lower=number(row['lower']);upper=number(row['upper'])
        if state!='finite':
            counts['interval_unavailable_after_accepted_point']+=1
            findings.append({'key':key,'kind':'typed interval unavailable','state':state})
            continue
        assert math.isfinite(lower) and math.isfinite(upper) and lower<=upper,key
        counts['finite_intervals']+=1
        j=0 if target=='alpha' else 1
        if is_stress:continue
        if method=='normal':
            se=math.sqrt(own['covariance'][j][j]);q=NormalDist().inv_cdf((1+level)/2)
            for bound,expected in [(lower,point-q*se),(upper,point+q*se)]:
                verify(near(bound, expected, 1e-06), ('normal endpoint', key, bound, expected))
            if not unidentified:
                ref=reference['normal_intervals'][f'{target}:{level}']
                verify(all((near(a, b, 1e-06) for a, b in zip([lower, upper], ref))), ('normal endpoint MLE reference', key, [{'observed':a,'expected':b,'absolute_error':abs(a-b),'limit':1e-6*(1+abs(b))} for a,b in zip([lower,upper],ref)]))
        else:
            model=BlockModel(data);base=REFERENCE[name]['fits']['ML']['nll']
            q=NormalDist().inv_cdf((1+level)/2)
            roots=REFERENCE[name]['fits']['ML']['profile_intervals'][f'{target}:{level}']
            for sign,bound,ref in zip((-1,1),(lower,upper),roots):
                constrained=model.optimize(constraint=(j,bound))['nll']
                lr=2*(constrained-base)
                verify(lr >= -1e-08, ('negative independent LR', key, lr))
                root=sign*math.sqrt(max(0,lr))
                verify(abs(root - sign * q) <= 0.02, ('profile LR residual', key, bound, root, sign * q))
                verify(abs(bound - ref['endpoint']) <= 0.01 * max(1, math.sqrt(reference['covariance'][j][j])), ('profile endpoint distance', key))
                profile_endpoints.append({'key':key,'bound':'lower' if sign<0 else 'upper',
                    'native_endpoint':bound,'independent_endpoint':ref['endpoint'],
                    'independent_signed_root_lr':root,'cutoff':sign*q,
                    'independent_root_lr_residual':abs(root-sign*q),
                    'endpoint_distance':abs(bound-ref['endpoint']),
                    'root_lr_tolerance':.02,
                    'endpoint_distance_tolerance':.01*max(1,math.sqrt(reference['covariance'][j][j])),
                    'reported_native_curve_residual':number(row.get('root_lr_residual')) if math.isfinite(number(row.get('root_lr_residual'))) else None})
    expected=set()
    for fixture in MANIFEST['fixtures']:
        if fixture.get('invalid'):continue
        name=Path(fixture['file']).stem
        strategies=[('ML','normal'),('REML','normal')]+([('ML','profile')] if fixture['profile_validation'] else [])
        for criterion,method in strategies:
            for target in ('alpha','beta'):
                for level in (.9,.95):expected.add((name,criterion,method,target,level))
    assert counts['rows_with_accepted_points']+counts['failed_point_rows']==counts['rows']
    assert counts['finite_intervals']+counts['typed_nonfinite']==counts['rows']
    assert seen==expected,('missing/extra fixture attempts',expected-seen,seen-expected)
    counts['accepted_strategy_fit_cells']=len({(r['fixture'],r['criterion'],r['interval_method']) for r in rows if math.isfinite(number(r['estimate']))})
    counts['unique_accepted_estimation_cells']=len({(r['fixture'],r['criterion']) for r in rows if math.isfinite(number(r['estimate']))})
    required_success=[r for r in rows if r['fixture']=='balanced_interior']
    assert len(required_success)==12 and all(r['state'].lstrip(':')=='finite' for r in required_success), 'balanced interior must demonstrate all three strategies with finite intervals'
    if allow_unbound and numerical_issues:raise AssertionError(('numerical failures',numerical_issues))
    return {'accepted':not numerical_issues,'numerical_issues':numerical_issues,'finite_states_are_native_reports':True,'path':str(path),'capture_sha256':hashlib.sha256(Path(path).read_bytes()).hexdigest(),'counts':counts,'findings':findings,'profile_endpoints':profile_endpoints,'execution_routes':sorted(set(r.get('execution_route','native_R_adapter') for r in rows))}

if __name__=='__main__':
    args=sys.argv[1:];receipt=None
    if '--receipt' in args:
        i=args.index('--receipt');receipt=Path(args[i+1]);del args[i:i+2]
    results=[validate(Path(p)) for p in args]
    assert results,'capture path required'
    rendered=json.dumps(results,indent=2,allow_nan=False)
    if receipt is not None:receipt.write_text(rendered+'\n')
    summaries=[{k:v for k,v in r.items() if k!='profile_endpoints'} | {'profile_bounds_checked':len(r['profile_endpoints'])} for r in results]
    print(json.dumps(summaries,indent=2,allow_nan=False))
    if all(r['accepted'] for r in results):print('INFERENCE_NATIVE_CAPTURES_AUDITED')
    else:
        print('INFERENCE_NATIVE_CAPTURES_FAILED');raise SystemExit(1)
