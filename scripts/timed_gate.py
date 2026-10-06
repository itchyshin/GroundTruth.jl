from pathlib import Path
import json,subprocess,sys,time,fcntl,os
root=Path(__file__).resolve().parent.parent
base=root.parent
budget=base/'numerical-budget.json'
with (base/'numerical.lock').open('w') as lock:
 fcntl.flock(lock,fcntl.LOCK_EX)
 value=json.loads(budget.read_text());remaining=value['limit_seconds']-value['charged_seconds']
 if remaining<=0:raise SystemExit('numerical allowance exhausted; stop and report')
 started=time.monotonic();key=root.name+'-'+Path(sys.argv[1]).name+'-'+Path(sys.argv[-1]).name
 env=os.environ.copy();env.update(OPENBLAS_NUM_THREADS='1',OMP_NUM_THREADS='1',JULIA_NUM_THREADS='1',JULIA_NUM_PRECOMPILE_TASKS='1')
 try:
  p=subprocess.run(sys.argv[1:],cwd=root,env=env,timeout=min(remaining,120),stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
  code=p.returncode;output=p.stdout
 except subprocess.TimeoutExpired as e:
  code=124;output=(e.stdout or b'').decode(errors='replace') if isinstance(e.stdout,bytes) else (e.stdout or '')
  output+='\nNUMERICAL_TIMEOUT_STOP_AND_REPORT\n'
 elapsed=time.monotonic()-started;value['charged_seconds']+=elapsed
 value['runs'].append({'key':key,'command':sys.argv[1:],'cwd':str(root),'elapsed_seconds':elapsed,'exit_code':code})
 budget.write_text(json.dumps(value,indent=2)+'\n')
 run=root/'.unlazy/logistic-twins/evidence';run.mkdir(parents=True,exist_ok=True)
 (run/(key+'.log')).write_text(output)
 (run/'numerical-timing.json').write_text(json.dumps(value,indent=2)+'\n')
 print(output,end='');print('NUMERICAL_SECONDS',round(elapsed,3),'CHARGED_TOTAL',round(value['charged_seconds'],3))
 raise SystemExit(code)
