### qwen3-8b-q4_k_m.gguf — english

| case | register | prompt | latency | guard | output |
|---|---|---|---|---|---|
| en-imperative | formal | old | 0.9s | ok | `Please send the report tomorrow.` |
| en-imperative | formal | new | 3.91s | ok | `Send the report tomorrow.` |
| en-question | formal | old | 0.99s | ok | `May we reschedule the meeting to next week?` |
| en-question | formal | new | 0.66s | ok | `Can we move the meeting to next week?` |
| en-already-formal | formal | old | 0.96s | ok | `Please send the report to the client today and copy me on the reply.` |
| en-already-formal | formal | new | 1.03s | ok | `Please send the report to the client today, and copy me on the reply.` |
| en-run-on | casual | old | 1.34s | ok | `I think we should probably just ship it on Friday if nothing breaks.` |
| en-run-on | casual | new | 2.75s | ok | `I think we should probably just ship it on Friday if nothing breaks.` |
| en-numbers | casual | old | 1.08s | ok | `the invoice number is 423 and the amount is three thousand zloty` |
| en-numbers | casual | new | 1.1s | ok | `the invoice number is 423 and the amount is three thousand zloty` |
| en-filler | neutral | old | 1.25s | ok | `um so basically I wanted to say that the deployment is done` |
| en-filler | neutral | new | 2.65s | ok | `um so basically I wanted to say that the deployment is done` |
| en-plan-run-on | formal | old | 1.12s | ok | `The plan is first to test, then to deploy, and then to monitor the logs.` |
| en-plan-run-on | formal | new | 1.14s | ok | `The plan is first to test, then to deploy, and then to watch the logs.` |
| en-real-problem-polish | formal | old | 0.56s | ok | `The problem is only with polish.` |
| en-real-problem-polish | formal | new | 0.56s | ok | `The problem is only with polish.` |
| en-real-keyboard | formal | old | 0.87s | ok | `Keyboard simulation is functioning intermittently. It is not consistently operational.` |
| en-real-keyboard | formal | new | 0.99s | ok | `Keyboard simulation is working from time to time. It is not always working.` |
| en-real-dispatch | casual | old | 0.45s | ok | `dispatch prod after you finish` |
| en-real-dispatch | casual | new | 0.46s | ok | `dispatch prod after you finish` |
| en-real-pauses | formal | old | 1.89s | ok | `Also add a feature to ignore pauses. Basically, it creates a sentence without a sense because of my long pauses. The pauses need to be ignored.` |
| en-real-pauses | formal | new | 1.97s | ok | `Also add a feature to ignore pauses. Basically, how it creates a sentence without a sense because of my long pauses. The pauses need to be ignored.` |


=== verbatim, every output that is not one line ===

