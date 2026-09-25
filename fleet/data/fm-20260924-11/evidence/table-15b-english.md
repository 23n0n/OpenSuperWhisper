### qwen2.5-1.5b-instruct-q4_k_m.gguf — english

| case | register | prompt | latency | guard | output |
|---|---|---|---|---|---|
| en-imperative | formal | old | 0.16s | ok | `send the report tomorrow` |
| en-imperative | formal | new | 0.42s | ok | `send the report tomorrow` |
| en-question | formal | old | 0.16s | ok | `can we schedule the meeting for next week?` |
| en-question | formal | new | 0.16s | ok | `Can we schedule the meeting for next week?` |
| en-already-formal | formal | old | 0.24s | ok | `Please transmit the report to the client immediately, and forward a copy to me.` |
| en-already-formal | formal | new | 0.25s | ok | `Please send the report to the client today, and copy me on the reply.` |
| en-run-on | casual | old | 0.29s | ok | `I reckon we should just ship it on Friday if nothing breaks.` |
| en-run-on | casual | new | 0.54s | ok | `I reckon we should just ship it on Friday if nothing breaks.` |
| en-numbers | casual | old | 0.29s | ok | `The invoice number is 423, and the amount is three thousand zloty.` |
| en-numbers | casual | new | 0.25s | ok | `invoice number is 423, amount is three thousand zloty.` |
| en-filler | neutral | old | 0.27s | ok | `um so basically I wanted to say that the deployment is done` |
| en-filler | neutral | new | 0.47s | ok | `basically, the deployment is done` |
| en-plan-run-on | formal | old | 0.27s | ok | `OK, the plan is to first test, then deploy, and finally watch the logs.` |
| en-plan-run-on | formal | new | 0.32s | ok | `First, we will test. Subsequently, we will deploy, and finally, we will monitor the logs.` |
| en-real-problem-polish | formal | old | 0.16s | ok | `The issue pertains solely to the polish.` |
| en-real-problem-polish | formal | new | 0.14s | ok | `The problem lies solely with polish.` |
| en-real-keyboard | formal | old | 0.22s | ok | `The keyboard simulation function operates intermittently. It does not consistently function.` |
| en-real-keyboard | formal | new | 0.2s | ok | `Keyboard simulation is occasionally functioning. It is not consistently operational.` |
| en-real-dispatch | casual | old | 0.12s | ok | `dispatch prod after you're done` |
| en-real-dispatch | casual | new | 0.11s | ok | `dispatch prod after you finish` |
| en-real-pauses | formal | old | 0.45s | ok | `Also add a feature to ignore pauses. Essentially, this will create a sentence without a sense due to my long pauses. The pauses need to be ignored.` |
| en-real-pauses | formal | new | 0.45s | ok | `Also add a feature to ignore pauses. Essentially, the system creates a sentence without a sense due to my long pauses. The pauses need to be ignored.` |


=== verbatim, every output that is not one line ===

