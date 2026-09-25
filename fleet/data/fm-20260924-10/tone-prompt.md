# Tone system prompt — proposed replacement

Prepared 2026-09-25 at the captain's request: *"Tone transcription is not working as intended… the whole
mechanism or pipeline is working. The only thing that is lacking is the correct output. So prepare a system
prompt for a tone change."*

## What is wrong with the current one (from the code and from measured output)

Current tone line (`TransformService.swift:363-368`):

> You are a dictation editor. The user dictated Polish text. Rewrite it in a formal tone — keep its language
> exactly Polish, never translate it, and keep every fact, name and number exactly as dictated. Change the
> register and nothing else. Use a formal, professional tone.

Then: `Output ONLY the final Polish text, with no quotes, labels, or explanation.` and `/no_think`.

Four concrete defects, each of which the measured outputs show:

1. **It never says the model must not behave like an assistant.** The 1.5B returned
   `"Please send the report to the client today, and copy me on the reply."` → `"**Sure,** send the report to
   the client today and copy me on the reply."` — an acknowledgement the speaker never said, added by a model
   that thought it was replying to a request.
2. **"Change the register and nothing else" gives no definition of a register.** The same instruction list is
   one generic sentence per tone (`Use a casual, conversational tone.`), so the model has to guess what may
   change. Measured drift in both directions: the 8B returned an *already formal* sentence byte-for-byte
   (nothing changed), and it dropped a word in another case.
3. **Nothing forbids answering, completing or continuing the text**, and nothing forbids summarising or
   elaborating. The clean-up half of the prompt says these things; the tone half does not.
4. **No idempotence rule.** When the text is already in the requested register, the model either echoes it or
   invents a change. There is also no rule about fragments, lists or noise, which dictation produces constantly.

## The prompt (system message)

`{TONE}` is `formal` | `casual` | `neutral`; `{LANGUAGE}` is `Polish` | `English`.

```
You rewrite dictated text. You are not an assistant: never answer it, greet, acknowledge, thank, comment,
explain, summarise or continue it.

The user dictated {LANGUAGE} text. Rewrite it in a {TONE} register, in {LANGUAGE}. Nothing else may change.

What the register may change — only these:
- formal: write complete sentences, no contractions ("do not", not "don't"), no slang or filler, polite and
  professional word choice.
- casual: use contractions, everyday words, direct and relaxed phrasing.
- neutral: change as little as possible; fix only what is unclear or ragged.

What must stay exactly as dictated:
- every fact, name, number, date, place, product and technical term — never add, never drop, never reword a
  commitment into a softer or stronger one;
- who is speaking and to whom: first person stays first person, a question stays a question, an order stays
  an order;
- the order and the completeness of the information — never summarise, never elaborate, never finish a
  half-sentence with new content;
- the language: {LANGUAGE} in, {LANGUAGE} out. Never translate, not even one word. If a term has no
  {LANGUAGE} equivalent, keep it exactly as spoken.

Output rules:
- Output only the rewritten text. No quotes, no labels, no preamble, no closing remark, no markdown, no
  commentary, no explanation of what you changed.
- Keep the dictated line breaks: do not join separate lines, do not split one line.
- If the text is already in the {TONE} register, return it unchanged.
- If the text is a fragment, a list, or noise that carries no sentence, return it as it is.
```

Last line stays `/no_think` (Qwen3 keeps its reasoning block out of the answer; the app also strips a leaked
`<think>` block, which stays as the belt-and-braces).

## The user message

The transcript is currently sent as the bare user turn, which small instruct models read as "a request to
answer". Prefix it with one imperative line and a delimiter:

```
Rewrite this dictated text in a {TONE} register. Keep its language ({LANGUAGE}), the speaker, every fact and
every number exactly as dictated. Output only the rewritten text.

<<<TRANSCRIPT
{transcript}
TRANSCRIPT>>>
```

The delimiter matters for the same reason the system prompt does: dictated text often *is* an instruction
("send the report tomorrow"), and without a frame the model obliges instead of rewriting.

## What each part is for (so nothing is cargo cult)

| rule | the observed failure it prevents |
|---|---|
| "You are not an assistant: never answer, greet, acknowledge…" | `"…reply."` → `"Sure, …reply."` — an added acknowledgement |
| register defined by what may change, not by an adjective | echo when already formal; invented interjections when casual |
| "never reword a commitment into a softer or stronger one" | register work that changes what was promised |
| "first person stays first person, a question stays a question" | a dictation rewritten as an answer to it |
| "never summarise, never elaborate, never finish a half-sentence" | dictation fragments completed with invented content |
| "the language: in–out, never translate" | the old translation behaviour creeping back through tone |
| "return it unchanged if already in register" | the byte-for-byte echo being treated as success, or drift being invented |
| "keep the dictated line breaks" | paragraphs joined or split by the model's own idea of tidiness |
| the user-message frame + delimiters | the model answering the dictated instruction instead of rewriting it |

## Acceptance (to be measured, not asserted)

For each language (English on `qwen2.5-1.5b-instruct-q4_k_m`, Polish on `qwen3-8b-q4_k_m` when installed), each
register, on a fixed set of real dictation samples, all of:

1. **Language preserved byte-for-byte in the sense that matters**: no word of the output is in the other
   language (checked by the app's own `LanguageDetector` and by eye).
2. **No added or dropped content**: the output's content words are a subset-plus-register-markers of the
   input's — no new nouns, no new sentences beyond the register change, no missing clause.
3. **No assistant frame**: the output contains no acknowledgement, preamble, label, quote or explanation, and
   does not read as a reply ("Sure", "Here is", "Oczywiście", "Oto").
4. **Register actually moves** where the input is not already in that register, and **stays put** where it is
   (the idempotence case the crew found could not be judged).
5. **Fragments, lists and noise come back unchanged** rather than repaired into sentences.

Samples: the captain's own recordings via `recordings.sqlite`, plus fixed adversarial cases — an imperative
sentence, a question, a half-sentence, a list of names and numbers, a sentence already formal, and a sentence
with one Polish technical term inside English.

## Measured — the A/B that decided the design (2026-09-25)

Harness `/tmp/tone-ab.py`: `llama-server` with the app's sampling (temperature 0.2, top-k 40, top-p 0.95, min-p 0.05,
`chat_template_kwargs.enable_thinking = false`), seven adversarial cases, three prompt variants, two models.

### `qwen3-8b-q4_k_m` (the model that changes the answer)

| case | current prompt | proposed prompt |
|---|---|---|
| "send the report tomorrow" (formal) | unchanged, uncapitalised | **"Please send the report tomorrow."** |
| "can we move the meeting to next week" (formal) | "May we reschedule the meeting to next week?" | "May we reschedule the meeting to next week?" |
| "I think we should probably just ship it on friday if nothing breaks" | "We should probably proceed with shipping it on Friday, provided there are no issues." | **"I believe we should probably ship it on Friday if nothing breaks."** |
| "the invoice number is 423 and the amount is three thousand zloty" (casual) | unchanged | unchanged (already casual — correct) |
| "ok so the plan is first we test then we deploy and then we watch the logs" (formal) | "The plan is first to test, then to deploy, and then to monitor the logs." | "The plan is first to test, then to deploy, and then to watch the logs." |
| "um so basically I wanted to say that the the deployment is done" (neutral) | unchanged | unchanged (tone does not remove filler; the clean-up switch does) |

### `qwen2.5-1.5b-instruct-q4_k_m` (where the captain's report came from)

Measured failure modes, all absent on the 8B with the same prompts:

- **assistant frame added:** `"Please send the report to the client today, and copy me on the reply."` →
  `"Sure, send the report to the client today and make sure to copy me on the reply."`
- **preamble instead of a rewrite** (proposed prompt): `"Sure, here's the rewritten text in a casual register:\n\n…"`
- **dropped articles:** `"invoice number is 423, amount is three thousand zloty."`
- **invented noun:** `"…ship it on friday…"` → `"We should consider shipping the product on Friday…"`
- **chat collapse at temperature 0:** the run-on sentence came back as `"Understood."`

**Conclusions carried into `fm-20260924-11`:** run tone on the 8B for both languages when it is installed; adopt the
prompt and the framing; keep temperature at 0.2 (0.0 was worse on both models); add a deterministic guard for the
frame/stub/language-flip class, because the prompt alone did not survive the small model.
