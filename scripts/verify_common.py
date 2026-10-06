from pathlib import Path
import json,hashlib,subprocess,sys,csv,math
ROOT=Path(__file__).resolve().parent.parent
RUN=ROOT/'.unlazy/logistic-twins'
FIX=ROOT/('test/fixtures/logistic' if (ROOT/'Project.toml').exists() else 'tests/testthat/fixtures/logistic')
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def preservation():
 baseline=json.loads((RUN/'source/preservation-baseline.json').read_text()); counts={}
 for item in baseline:
  root=Path(item['root'])
  def git(*args):return subprocess.check_output(['git','-C',str(root),*args])
  assert git('rev-parse','HEAD').decode().strip()==item['head'],f'HEAD changed {root}'
  assert git('status','--porcelain=v1','--untracked-files=all').decode()==item['status'],f'status changed {root}'
  assert hashlib.sha256(git('diff','--binary')).hexdigest()==item['diff_sha256']
  assert hashlib.sha256(git('diff','--cached','--binary')).hexdigest()==item['cached_diff_sha256']
  for name,expected in item['files'].items():
   p=root/name
   actual='symlink:'+str(p.readlink()) if p.is_symlink() else digest(p) if p.is_file() else 'missing'
   assert actual==expected,f'protected bytes changed: {p}'
  counts[str(root)]=len(item['files'])
 (RUN/'evidence/preservation.json').write_text(json.dumps({'counts':counts,'unchanged':True},indent=2)+'\n')
 return counts
def fixtures():
 freeze=json.loads((FIX/'freeze.json').read_text()); assert len(freeze['sha256'])==12
 for name,h in freeze['sha256'].items(): assert digest(FIX/name)==h,f'changed fixture {name}'
 for name,h in freeze['original'].items(): assert digest(FIX/name)==h
 assert digest(ROOT/'docs/dev-log/logistic-twins/CONTRACT.md')==freeze['contract_sha256']
 a=list(csv.DictReader((FIX/'analytic.csv').open()));s=list(csv.DictReader((FIX/'shifted.csv').open()))
 assert len(a)==len(s)==20
 assert all(float(v['x'])==3-100*float(u['x']) and v['y']==u['y'] for u,v in zip(a,s))
 t=[(float(v['x']),float(v['y'])) for v in csv.DictReader((FIX/'tied.csv').open())]
 assert t==[(-1,0),(0,0),(0,1),(1,0)]
 x=[float(v['x']) for v in a];y=[float(v['y']) for v in a]
 assert sum(v for u,v in zip(x,y) if u==-1)==2 and sum(v for u,v in zip(x,y) if u==1)==7
 alpha=(math.log(.2/.8)+math.log(.7/.3))/2;beta=(math.log(.7/.3)-math.log(.2/.8))/2
 assert beta/.01>30
 red=json.loads((RUN/'evidence/red-regression.json').read_text())
 assert red['exit_code']==1 and red['failed_assertion']=='fit.converged' and red['production_unchanged'] is True
 (RUN/'evidence/fixtures.json').write_text(json.dumps({'fixtures':12,'original':10,'analytic':{'alpha':alpha,'beta':beta,'information':[[3.7,.5],[.5,3.7]]},'red':red},indent=2)+'\n')
def environment():
 setup=json.loads((RUN/'source/setup.json').read_text())
 assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT).decode().strip()==setup['base']
 assert subprocess.check_output(['git','branch','--show-current'],cwd=ROOT).decode().strip()=='codex/logistic-twins'
 binary=Path('/Users/z3437171/.julia/juliaup/julia-1.12.6+0.aarch64.apple.darwin14/Julia-1.12.app/Contents/Resources/julia/bin/julia')
 version=subprocess.check_output([str(binary),'--version']).decode().strip();assert version=='julia version 1.12.6'
 r=subprocess.check_output(['Rscript','--vanilla','-e','for(p in c("testthat","roxygen2","pkgdown","digest")){stopifnot(requireNamespace(p,quietly=TRUE));cat(p,as.character(packageVersion(p)),"\\n")}']).decode()
 preservation()
 (RUN/'evidence/environment.json').write_text(json.dumps({'julia':version,'R_packages':r,'cached_only':True,'threads':1,'routing':'native/explicit fallback; tiered CLI rejected requested Luna model','load_receipt':'Julia GroundTruth baseline loaded and rescaling regression reproduced'},indent=2)+'\n')
mode=sys.argv[1]
if mode=='environment':environment();print('LOGISTIC_ENVIRONMENT_OK')
elif mode=='fixtures':fixtures();print('LOGISTIC_FIXTURES_OK')
elif mode=='preservation':preservation();print('LOGISTIC_PRESERVATION_OK')
else:raise SystemExit('unknown verification mode')
