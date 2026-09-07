import json,sys
for f in sys.argv[1:]:
 es=json.load(open(f)); print(f)
 for a in (1,2):
  start=next(e for e in es if e['event']=='request_focus' and e['attempt']==a)
  end=next(e for e in es if e['event']=='request_blur' and e['attempt']==a)
  t=start['millisecondsSinceStart'];s=[e for e in es if t<=e['millisecondsSinceStart']<end['millisecondsSinceStart']]
  will=[e for e in s if e['event']=='UIKeyboardWillShowNotification'];did=[e for e in s if e['event']=='UIKeyboardDidShowNotification'];gaps=[e['milliseconds'] for e in s if e['event']=='frame_gap']
  print({'attempt':a,'firstWillShowMs':round(will[0]['millisecondsSinceStart']-t,1) if will else None,'finalDidShowMs':round(did[-1]['millisecondsSinceStart']-t,1) if did else None,'maxGapOver50Ms':round(max(gaps,default=0),1),'showNotifications':len(will),'bodyDelta':{k:did[-1]['bodyCounts'].get(k,0)-v for k,v in start['bodyCounts'].items()} if did else {}})
