"""Sensitivity controls for the native-capture checker, using no native engine."""
import csv,copy,json,tempfile,sys
from pathlib import Path
from validate_captures import ROOT,REFERENCE,MANIFEST,validate
from independent_gaussian import read_data,dense_reference
from statistics import NormalDist
import math
columns=['fixture','criterion','interval_method','target','level','estimate','sigma2','tau2','objective','cov11','cov12','cov22','lower','upper','state','base_status','engine_version']
rows=[]
for fixture in MANIFEST['fixtures']:
    if fixture.get('invalid'):continue
    name=Path(fixture['file']).stem
    for criterion,method in [('ML','normal'),('REML','normal')]+([('ML','profile')] if fixture['profile_validation'] else []):
        fit=REFERENCE[name]['fits'][criterion]
        for j,target in enumerate(('alpha','beta')):
            for level in (.9,.95):
                bounds=fit['normal_intervals'][f'{target}:{level}'] if method=='normal' else [v['endpoint'] for v in fit['profile_intervals'][f'{target}:{level}']]
                rows.append(dict(zip(columns,[name,criterion,method,target,level,fit['coefficients'][j],fit['sigma2'],fit['tau2'],fit['nll'],fit['covariance'][0][0],fit['covariance'][0][1],fit['covariance'][1][1],*bounds,'finite','independent-reference-control','not-a-native-fit'])))
def write(path,data):
    with path.open('w',newline='') as f:
        w=csv.DictWriter(f,fieldnames=columns);w.writeheader();w.writerows(data)
with tempfile.TemporaryDirectory(prefix='capture-checker-',dir=ROOT) as tmp:
    p=Path(tmp)/'control.csv';write(p,rows);validate(p,allow_unbound=True)
    mutations={}
    for label,col,change in [('wrong_sign','estimate',lambda v:-v),('variance_as_sd','sigma2',lambda v:v**.5),('double_divided_objective','objective',lambda v:v/2),('initial_covariance','cov11',lambda v:2*v),('wrong_endpoint','upper',lambda v:v+1)]:
        z=copy.deepcopy(rows);z[0][col]=change(z[0][col]);mutations[label]=z
    z=copy.deepcopy(rows);z[0]['target']='beta';mutations['swapped_target']=z
    mutations['missing_target']=copy.deepcopy(rows[1:])
    mutations['duplicate_target']=copy.deepcopy(rows+[rows[0]])
    z=copy.deepcopy(rows)
    for r in z:
        if r['criterion']=='REML':r['criterion']='ML'
    mutations['ML_masquerading_as_REML']=z
    z=copy.deepcopy(rows)
    for r in z:
        if r['fixture']=='two_group_group_x' and r['criterion']=='REML':
            r['sigma2']*=2
            own=dense_reference(read_data(ROOT/'fixtures/two_group_group_x.csv'),r['sigma2'],r['tau2'],criterion='REML')
            r['objective']=own['nll'];r['cov11']=own['covariance'][0][0];r['cov12']=own['covariance'][0][1];r['cov22']=own['covariance'][1][1]
            j=0 if r['target']=='alpha' else 1
            q=NormalDist().inv_cdf((1+r['level'])/2);se=math.sqrt(own['covariance'][j][j])
            r['lower']=r['estimate']-q*se;r['upper']=r['estimate']+q*se
    mutations['wrong_G2_REML_sigma2_self_consistent']=z
    for name,z in mutations.items():
        write(p,z)
        try:validate(p,allow_unbound=True)
        except (AssertionError,ValueError,KeyError):pass
        else:raise AssertionError('checker accepted mutant '+name)
    write(p,list(reversed(rows)));validate(p,allow_unbound=True)
print('INFERENCE_CAPTURE_CONTROLS_OK',len(mutations),'rejected; harmless row reversal passed')
