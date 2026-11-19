# airbench 결과

`node tools/airbench/eval.mjs data` 출력입니다(합성 60fps 데이터셋, 2026-11-19).

```
Per light (motion scenarios: slow, flick6/4/3/2, two_hands). eventRecall = beam crossings caught; recall = frames; FP = false-positive frame rate incl. empty/idle

[bright]
variant                   eventRecall  frameRecall  latency(f)  FPrate
AI 기존                       76%          57%        0.04           1%
AI +저조도보정                   76%          57%        0.04           1%
AI +보정+스윕+유지                96%          97%        0.16           1%
AI 최종(+모션보조)               100%         100%        0.00           2%
빠른 기존                       87%          60%        0.17           0%
빠른 최종                       94%          68%        0.02           0%

[dim]
variant                   eventRecall  frameRecall  latency(f)  FPrate
AI 기존                        6%          17%        0.05           1%
AI +저조도보정                    9%          19%        0.50           1%
AI +보정+스윕+유지                15%          24%        0.86           1%
AI 최종(+모션보조)                83%          90%        0.12           2%
빠른 기존                        0%           0%        1.00           0%
빠른 최종                       98%          80%        0.33           0%

[dark]
variant                   eventRecall  frameRecall  latency(f)  FPrate
AI 기존                        0%           0%        0.00           0%
AI +저조도보정                    6%          16%        0.03           1%
AI +보정+스윕+유지                 8%          17%        0.27           1%
AI 최종(+모션보조)                33%          36%        0.59           1%
빠른 기존                        0%           0%        0.00           0%
빠른 최종                       68%          55%        0.66           0%

Per scenario eventRecall (bright / dim / dark):
slow      AI:100/100/0      AI:100/100/100    AI:100/100/100    AI:100/100/100    빠른:100/3/0        빠른:100/100/100    
flick6    AI:97/0/0         AI:97/8/0         AI:100/15/1       AI:100/100/68     빠른:100/0/0        빠른:100/100/96     
flick4    AI:63/0/0         AI:63/7/0         AI:100/7/0        AI:100/100/41     빠른:99/0/0         빠른:100/99/64      
flick3    AI:33/0/0         AI:33/1/0         AI:80/6/1         AI:100/99/28      빠른:77/0/0         빠른:100/92/47      
flick2    AI:67/0/0         AI:67/0/0         AI:100/23/7       AI:100/100/22     빠른:49/0/0         빠른:67/98/36       
two_hands AI:100/0/0        AI:100/0/0        AI:100/0/0        AI:100/41/5       빠른:100/0/0        빠른:100/100/85     
idle_mid  AI:100/100/0      AI:100/100/100    AI:100/100/100    AI:100/100/100    빠른:100/100/0      빠른:100/100/100    
empty     AI:fp0/fp0/fp0    AI:fp0/fp0/fp0    AI:fp0/fp0/fp0    AI:fp0/fp0/fp0    빠른:fp0/fp0/fp0    빠른:fp0/fp0/fp0    
```
