#!/usr/bin/env python3
"""Vector-traces the 'Shahina Ahmed' lettering from her own logo (brand/source-logos/shahina-logo-black.png).
Output: brand/name_path.json  {d, w, h}  (path in a w x h box). Used by build_brand.py."""
import cv2, numpy as np, json, pathlib
here = pathlib.Path(__file__).parent
im = cv2.imread(str(here/"source-logos/shahina-logo-black.png")).astype(np.float32)
b,g,r = im[...,0],im[...,1],im[...,2]
mx = np.maximum(np.maximum(r,g),b); mn = np.minimum(np.minimum(r,g),b)
sat = (mx-mn)/(mx+1e-3)
white = np.clip((mn-60)/120,0,1) * np.clip(1-sat*2.2,0,1)      # bright & unsaturated
Y0,Y1 = 172,272
m = white[Y0:Y1,:]
S = 8
m = cv2.resize(m,None,fx=S,fy=S,interpolation=cv2.INTER_CUBIC)
m = cv2.GaussianBlur(m,(0,0),S*0.55)
bw = (m>0.5).astype(np.uint8)*255
# drop specks
n,lab,st,_ = cv2.connectedComponentsWithStats(bw)
for i in range(1,n):
    if st[i,cv2.CC_STAT_AREA] < 40*S*S/4: bw[lab==i]=0
ys,xs = np.nonzero(bw); x0,x1,y0,y1 = xs.min(),xs.max(),ys.min(),ys.max()
bw = bw[y0:y1+1,x0:x1+1]
cv2.imwrite(str(here/"name_mask.png"),bw)
cs,hier = cv2.findContours(bw,cv2.RETR_CCOMP,cv2.CHAIN_APPROX_NONE)
def smooth(c):
    p = c[:,0,:].astype(np.float64)
    k = 15
    pad = np.concatenate([p[-k:],p,p[:k]])
    ker = np.ones(k)/k
    q = np.stack([np.convolve(pad[:,i],ker,'same') for i in (0,1)],1)[k:-k]
    return q[::9] if len(q)>60 else q
parts=[]
for c in cs:
    if cv2.contourArea(c) < 30*S: continue
    q = smooth(c); n=len(q)
    d = f"M{(q[0]+q[1])[0]/2/S:.2f} {(q[0]+q[1])[1]/2/S:.2f}"
    for i in range(1,n+1):
        a,bq = q[i%n], q[(i+1)%n]
        mid = (a+bq)/2
        d += f"Q{a[0]/S:.2f} {a[1]/S:.2f} {mid[0]/S:.2f} {mid[1]/S:.2f}"
    parts.append(d+"Z")
out = {"d":"".join(parts),"w":bw.shape[1]/S,"h":bw.shape[0]/S}
(here/"name_path.json").write_text(json.dumps(out))
print(out["w"],out["h"],len(parts),"contours",len(out["d"]),"bytes")
