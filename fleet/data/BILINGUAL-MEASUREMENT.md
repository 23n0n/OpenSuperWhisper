# Bilingual dictation measurement — what it settles, and the two minutes it needs from the captain

**Why.** The translator is gone and the app must deliver Polish as Polish and English as English. That is one
behaviour with two halves, and only real speech through the real app settles it: the transcript's language, the
sense surviving, and no word of the other language appearing. Everything else on this subject is inference.

**What to record.** The *same* content twice, once spoken in Polish and once in English. Keep it short and include the
three things a model most often mangles: a proper noun, a number, and a question.

| # | Polish | English |
|---|---|---|
| 1 | "Wysłałem raport do Anny w poniedziałek, ale nie dostałem odpowiedzi." | "I sent the report to Anna on Monday, but I did not get an answer." |
| 2 | "Budżet na przyszły kwartał to 12 tysięcy, prawda?" | "The budget for next quarter is 12 thousand, right?" |
| 3 | "Nie mogę dzisiaj przyjść na spotkanie, przepraszam." | "I cannot come to the meeting today, sorry." |

Record each one **twice**: once with tone off (plain dictation) and once with tone on, so the measurement covers both
paths. Four recordings in Polish, four in English — eight short clips, about two minutes of speech.

**How.** Just use the app the way you always do. Recordings and their stored text land in
`~/Library/Application Support/ru.starmel.OpenSuperWhisper/` (`recordings/` and `recordings.sqlite`); nothing extra
needs to be exported.

**Then this side runs the comparison**, reusing the app's own engine rather than a lookalike: the pause task's
`CaptainRecordingPauseBoundaryTests` already decodes the captain's own recordings through the app's engine path with
`TEST_RUNNER_OSW_TEST_CAPTAIN_RECORDINGS` and dumps evidence to a file, so that harness is the tool — no new one.

**The table it must produce,** per clip: expected text, transcript, detected language, output language, whether any
word arrived from the other language, whether a fact/number/proper noun moved, and — for the tone-on clips — whether
the guard rejected the rewrite and what the notice said. Numbers, not adjectives; anything that comes out against the
hypothesis stays in.
