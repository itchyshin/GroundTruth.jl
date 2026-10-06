from pathlib import Path
import csv,json,math,copy,ast,hashlib,tempfile,sys
from statistics import NormalDist
ROOT=Path(__file__).resolve().parent.parent;RUN=ROOT/'.unlazy/logistic-twins'
J=ROOT.parent/'GroundTruth.jl';R=ROOT.parent/'groundtruth'
FIX=J/'test/fixtures/logistic'
DURABLE=ROOT/'docs/dev-log/logistic-twins/evidence'
RETAINED='--retained-evidence' in sys.argv
SOURCE=RUN/'source' if not RETAINED and (RUN/'source/audit-verify.py').is_file() else DURABLE
provenance=json.loads((DURABLE/'reference-provenance.json').read_text())
for filename,receipt in provenance.items():
 assert hashlib.sha256((SOURCE/filename).read_bytes()).hexdigest()==receipt['sha256'],f'reference bytes changed: {filename}'
# Execute only the unchanged scalar oracle functions from the frozen earlier audit.
# They do not import either production implementation or its standardization helpers.
source=(SOURCE/'audit-verify.py').read_text()
keep={'sigmoid','oracle','close','analytic','numeric','keyed','validate_pair'}
tree=ast.parse(source);tree.body=[n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name in keep]
ns={'math':math,'NormalDist':NormalDist};exec(compile(tree,'frozen-audit-scalar-oracle','exec'),ns)
oracle=ns['oracle'];validate=ns['validate_pair'];keyed=ns['keyed'];close=ns['close'];sigmoid=ns['sigmoid']
def data(name):return [(float(v['x']),float(v['y'])) for v in csv.DictReader((FIX/(name+'.csv')).open())]
def read(path):return list(csv.DictReader(path.open()))
def pair(rows,name):
 p={v['target']:v for v in rows if v['fixture']==name}
 assert len([v for v in rows if v['fixture']==name])==2 and set(p)=={'alpha','beta'}
 return p
def coefficients(p):return tuple(float(p[t]['estimate']) for t in ('alpha','beta'))
def covariance(o):
 return [[o['Ibb']/o['det'],-o['Iab']/o['det']],[-o['Iab']/o['det'],o['Iaa']/o['det']]]
def transform(C,T):return [[sum(T[i][a]*C[a][b]*T[j][b] for a in range(2) for b in range(2)) for j in range(2)] for i in range(2)]
finite=('retained','analytic','asymmetric','inverted','scaled','shifted','tied')
failure=('complete','quasi','all_zero','all_one','constant')
results={};worst={'coefficient':0.,'se':0.,'endpoint':0.,'mean_nll':0.};validated=0
for name,root in [('julia',J),('r',R)]:
 transport=root/'.unlazy/logistic-twins/evidence'/f'{name}-fits.csv'
 if RETAINED or not transport.is_file():transport=root/'docs/dev-log/logistic-twins/evidence'/f'{name}-fits.csv'
 if RETAINED:
  receipt=json.loads((DURABLE/'transport-provenance.json').read_text())[f'{name}-fits.csv']
  assert hashlib.sha256(transport.read_bytes()).hexdigest()==receipt['sha256'],f'retained output bytes changed: {name}'
 rows=read(transport);keyed(rows)
 assert {v['fixture'] for v in rows}==set(finite+failure),f'{name}: fixture coverage'
 assert len(rows)==24 and {v['engine'] for v in rows}=={name},f'{name}: transport identities'
 for fixture in finite:
  p=pair(rows,fixture);errors=validate(p,data(fixture),fixture=='analytic')
  assert not errors,f'{name}/{fixture}: {errors}'
  b=coefficients(p)
  if fixture=='tied':assert close(b[0],-math.log(3),1e-10,0) and close(b[1],0,1e-10,0)
  validated+=1
 for fixture in failure:
  p=pair(rows,fixture)
  assert all(v['status']!='ok' and not v['estimate'].strip() for v in p.values()),f'{name}/{fixture}: accepted no-finite-MLE'
  message=' '.join(v['message'] for v in p.values()).lower()
  expected={'complete':('complete','separation'),'quasi':('quasi','separation'),'all_zero':('zero','finite'),'all_one':('one','finite'),'constant':('constant','rank')}
  assert any(t in message for t in expected[fixture]),f'{name}/{fixture}: diagnosis not preserved'
 base=pair(rows,'analytic');baseb=coefficients(base);baseo=oracle(data('analytic'),*baseb)
 for fixture,T,back in [('scaled',[[1,0],[0,100]],lambda b:(b[0],b[1]*.01)),('shifted',[[1,.03],[0,-.01]],lambda b:(b[0]+3*b[1],-100*b[1]))]:
  p=pair(rows,fixture);b=coefficients(p);backb=back(b)
  assert all(close(u,v,1e-7,1e-7) for u,v in zip(backb,baseb))
  o=oracle(data(fixture),*b);expected=transform(covariance(baseo),T)
  assert all(close(covariance(o)[i][j],expected[i][j],1e-8,1e-7) for i in range(2) for j in range(2)),f'{name}/{fixture}: full covariance'
  assert abs(o['nll']/len(data(fixture))-baseo['nll']/20)<=1e-10
  assert max(abs(sigmoid(b[0]+b[1]*x)-sigmoid(baseb[0]+baseb[1]*u)) for (x,y),(u,v) in zip(data(fixture),data('analytic')))<=1e-7
 results[name]=rows
for fixture in finite:
 a=pair(results['julia'],fixture);b=pair(results['r'],fixture)
 for target in ('alpha','beta'):
  for field,category in [('estimate','coefficient'),('se','se'),('lower90','endpoint'),('upper90','endpoint'),('lower95','endpoint'),('upper95','endpoint')]:
   u,v=float(a[target][field]),float(b[target][field]);assert close(u,v,1e-7,1e-7),f'paired {fixture}/{target}/{field}'
   worst[category]=max(worst[category],abs(u-v))
  d=abs(float(a[target]['nll'])/len(data(fixture))-float(b[target]['nll'])/len(data(fixture)))
  assert d<=1e-10;worst['mean_nll']=max(worst['mean_nll'],d)
# Reuse retained external-engine references, with native versus rebuilt GLM inference distinct.
reference_counts={}
for filename in ('audit-r.csv','audit-glm-final.csv'):
 rows=read(SOURCE/filename)
 for fixture in ('retained','analytic','asymmetric','inverted','scaled'):
  p=pair(rows,fixture);errors=validate(p,data(fixture),fixture=='analytic');assert not errors,f'retained {filename}/{fixture}: {errors}'
  candidate=pair(results['julia'],fixture)
  for target in ('alpha','beta'):
   for field in ('estimate','se','lower90','upper90','lower95','upper95'):
    assert close(float(candidate[target][field]),float(p[target][field]),1e-7,1e-7)
 reference_counts[filename]=5
# Checker sensitivity controls operate on accepted positive data, never production helpers.
positive=pair(results['julia'],'analytic');controls={}
def rejected(label,p):
 try:errors=validate(p,data('analytic'),True)
 except (AssertionError,KeyError,ValueError):errors=['schema rejected']
 assert errors,f'checker admitted {label}';controls[label]='rejected'
v=copy.deepcopy(positive)
for t in v:v[t]['estimate']=str(-float(v[t]['estimate']))
rejected('sign-flipped coefficients',v)
v=copy.deepcopy(positive);v['alpha'],v['beta']=v['beta'],v['alpha'];rejected('swapped targets',v)
v=copy.deepcopy(positive);del v['beta'];rejected('missing target',v)
try:keyed(results['julia']+[results['julia'][0]])
except AssertionError:controls['duplicate target']='rejected'
else:raise AssertionError('checker admitted duplicate')
v=copy.deepcopy(positive)
for t in v:
 v[t]['se']=str(math.sqrt(.2))
 for level in (.9,.95):
  q=NormalDist().inv_cdf((1+level)/2);suffix=str(round(level*100));point=float(v[t]['estimate'])
  v[t]['lower'+suffix]=str(point-q*math.sqrt(.2));v[t]['upper'+suffix]=str(point+q*math.sqrt(.2))
rejected('initial-information intervals',v)
assert keyed(list(reversed(results['julia'])))==keyed(results['julia']);controls['row permutation']='passed'
freeze=json.loads((FIX/'freeze.json').read_text());raw=(FIX/'analytic.csv').read_bytes()
def valid_fixture_bytes(value):return hashlib.sha256(value).hexdigest()==freeze['sha256']['analytic.csv']
assert valid_fixture_bytes(raw) and not valid_fixture_bytes(raw+b'\n');controls['changed fixture bytes']='rejected'
native=read(SOURCE/'audit-glm.csv');native_errors={f:validate(pair(native,f),data(f),f=='analytic') for f in ('retained','analytic','asymmetric','inverted')}
assert any(native_errors.values()),'retained native GLM inference mismatch control no longer exposed'
report={'independent_scalar_oracle':'unchanged functions from hashed earlier audit; no production-helper import','accepted_fits_checked':validated,'paired_fixtures':7,'rejected_design_fixtures':5,'reference_checks':reference_counts,'worst_paired_absolute_differences':worst,'controls':controls,'retained_glm_native_interval_mismatches':native_errors,'limits':'one-predictor Bernoulli unit weights; numerical agreement, no calibration or GLMM; references reused, not newly refit'}
(RUN/'evidence').mkdir(parents=True,exist_ok=True)
(RUN/'evidence/science.json').write_text(json.dumps(report,indent=2,allow_nan=False)+'\n')
print('LOGISTIC_TWINS_SCIENCE_OK');print(json.dumps(report,indent=2))
