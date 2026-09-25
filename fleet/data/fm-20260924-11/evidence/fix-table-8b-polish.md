### qwen3-8b-q4_k_m.gguf — polish

| case | register | prompt | latency | guard | output |
|---|---|---|---|---|---|
| pl-imperative | formal | old | 1.29s | ok | `Wyślij raport do klienta dzisiaj.` |
| pl-imperative | formal | new | 2.68s | ok | `Wyślij raport do klienta dzisiaj.` |
| pl-question | formal | old | 1.21s | ok | `Czy możemy przenieść spotkanie na przyszły tydzień?` |
| pl-question | formal | new | 1.18s | ok | `Czy możemy przenieść spotkanie na przyszły tydzień` |
| pl-already-formal | formal | old | 1.8s | ok | `Proszę o wysłanie raportu do klienta jeszcze dziś oraz o przesłanie mi kopii odpowiedzi.` |
| pl-already-formal | formal | new | 1.81s | ok | `Proszę o wysłanie raportu do klienta jeszcze dziś oraz o przesłanie mi kopii odpowiedzi.` |
| pl-run-on | casual | old | 2.36s | ok | `no więc myślę, że po prostu powinniśmy to wypuścić w piątek, jeśli nic się nie zepsuje` |
| pl-run-on | casual | new | 3.79s | ok | `no więc myślę, że po prostu powinniśmy to wypuścić w piątek, jeśli nic się nie zepsuje` |
| pl-numbers | casual | old | 1.3s | ok | `numer faktury to 423 a kwota to trzy tysiące złotych` |
| pl-numbers | casual | new | 1.41s | ok | `numer faktury to 423 a kwota to trzy tysiące złotych` |
| pl-filler | neutral | old | 1.77s | ok | `yyy no więc w sumie chciałem powiedzieć, że wdrożenie jest zrobione` |
| pl-filler | neutral | new | 3.21s | ok | `yyy no więc w sumie chciałem powiedzieć, że że wdrożenie jest zrobione` |
| pl-plan-run-on | formal | old | 1.7s | ok | `Najpierw testujemy, potem wdrażamy, a potem patrzymy w logi.` |
| pl-plan-run-on | formal | new | 1.74s | ok | `Najpierw testujemy, potem wdrażamy, a potem patrzymy w logi.` |
| pl-real-odzyskalem-formal | formal | old | 2.93s | ok | `Dobra wiadomość to taka, że odzyskałem swój polski. Udało mi się zrobić fork. Ben super whisper. Dałem drugi model. Jestem. Znowu po polsku.` |
| pl-real-odzyskalem-formal | formal | new | 2.97s | ok | `Dobra wiadomość jest taka, że odzyskałem swój polski. Udało mi się zrobić fork. Ben super whisper. Dałem drugi model. Jestem. Znowu po polsku.` |
| pl-real-odzyskalem-casual | casual | old | 3.02s | ok | `Dobra wiadomość to taka, że odzyskałem swój polski. Udało mi się zrobić fork. Ben super whisper. Dałem drugi model. Jestem. Znowu po polsku.` |
| pl-real-odzyskalem-casual | casual | new | 3.06s | ok | `Dobra wiadomość to taka, że odzyskałem swój polski. Udało mi się zrobić fork. Ben super whisper. Dałem drugi model. Jestem. Znowu po polsku.` |
| pl-real-odzyskalem-neutral | neutral | old | 3.04s | ok | `Dobra wiadomość jest taka, że odzyskałem swój polski. Udało mi się zrobić fork. Ben super whisper. Dałem drugi model. Jestem. Znowu po polsku.` |
| pl-real-odzyskalem-neutral | neutral | new | 3.02s | ok | `Dobra wiadomość jest taka, że odzyskałem swój polski. Udało mi się zrobić fork. Ben super whisper. Dałem drugi model. Jestem. Znowu po polsku.` |
| pl-real-ziameczku-formal | formal | old | 2.75s | ok | `Dobra, ziameczku, tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to, że przekląłeś po całości.` |
| pl-real-ziameczku-formal | formal | new | 2.89s | ok | `Dobra, ziameczku, tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to, że żeś pieprzył po całości.` |
| pl-real-ziameczku-casual | casual | old | 2.83s | ok | `Dobra ziameczku, tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to, że żeś pieprzył po całości.` |
| pl-real-ziameczku-casual | casual | new | 2.87s | ok | `Dobra ziameczku, tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to, że żeś pieprzył po całości.` |
| pl-real-ziameczku-neutral | neutral | old | 2.71s | ok | `Dobra ziameczku, tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to, że przeszkodziłeś po całości.` |
| pl-real-ziameczku-neutral | neutral | new | 2.72s | ok | `Dobra ziameczku tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to, że żeś pieprzył po całości.` |
| pl-real-jeszcze-raz-formal | formal | old | 1.99s | ok | `Jeszcze raz transkrypcja w języku polskim, jeszcze raz transkrypcja w języku polskim.` |
| pl-real-jeszcze-raz-formal | formal | new | 2.0s | ok | `Jeszcze raz transkrypcja w języku polskim, jeszcze raz transkrypcja w języku polskim.` |
| pl-real-jeszcze-raz-casual | casual | old | 1.98s | ok | `Jeszcze raz transkrypcja w języku polskim, jeszcze raz transkrypcja w języku polskim.` |
| pl-real-jeszcze-raz-casual | casual | new | 1.99s | ok | `Jeszcze raz transkrypcja w języku polskim, jeszcze raz transkrypcja w języku polskim.` |
| pl-real-jeszcze-raz-neutral | neutral | old | 1.94s | ok | `Jeszcze raz transkrypcja w języku polskim, jeszcze raz transkrypcja w języku polskim.` |
| pl-real-jeszcze-raz-neutral | neutral | new | 1.98s | ok | `Jeszcze raz transkrypcja w języku polskim, jeszcze raz transkrypcja w języku polskim.` |
| pl-real-zarzucic-formal | formal | old | 0.94s | ok | `Mogę coś zarzucić za jej w tle.` |
| pl-real-zarzucic-formal | formal | new | 0.94s | ok | `Mogę coś zarzucić za jej w tle.` |
| pl-real-zarzucic-casual | casual | old | 0.94s | ok | `Mogę coś zarzucić za jej w tle.` |
| pl-real-zarzucic-casual | casual | new | 0.94s | ok | `Mogę coś zarzucić za jej w tle.` |
| pl-real-zarzucic-neutral | neutral | old | 0.94s | ok | `Mogę coś zarzucić za jej w tle.` |
| pl-real-zarzucic-neutral | neutral | new | 0.96s | ok | `Mogę coś zarzucić za jej w tle.` |
| pl-real-nagrywam-formal | formal | old | 1.32s | ok | `Teraz nagrywam w języku polskim, sprawdzam, jak to działa.` |
| pl-real-nagrywam-formal | formal | new | 1.32s | ok | `Teraz nagrywam w języku polskim, sprawdzam, jak to działa.` |
| pl-real-nagrywam-casual | casual | old | 1.16s | ok | `Teraz nagrywam po polsku, sprawdzam jak to działa.` |
| pl-real-nagrywam-casual | casual | new | 1.11s | ok | `Teraz nagrywam po polsku, sprawdzam jak to działa.` |
| pl-real-nagrywam-neutral | neutral | old | 1.33s | ok | `Teraz nagrywam w języku polskim, sprawdzam, jak to działa.` |
| pl-real-nagrywam-neutral | neutral | new | 1.33s | ok | `Teraz nagrywam w języku polskim, sprawdzam, jak to działa.` |
| pl-real-podgrywam-formal | formal | old | 1.79s | ok | `Teraz podgrywam w języku polskim, teraz nagrywam w języku polskim.` |
| pl-real-podgrywam-formal | formal | new | 1.81s | ok | `Teraz podgrywam w języku polskim, teraz nagrywam w języku polskim.` |
| pl-real-podgrywam-casual | casual | old | 1.47s | ok | `Teraz podgrywam po polsku, teraz nagrywam po polsku.` |
| pl-real-podgrywam-casual | casual | new | 1.61s | ok | `Teraz podgrywam w polskim, teraz nagrywam w polskim.` |
| pl-real-podgrywam-neutral | neutral | old | 1.56s | ok | `Teraz gram w języku polskim, teraz nagrywam w języku polskim.` |
| pl-real-podgrywam-neutral | neutral | new | 1.84s | ok | `Teraz podgrywam w języku polskim, teraz nagrywam w języku polskim.` |
| pl-real-probuje-formal | formal | old | 0.69s | ok | `Teraz próbuję coś nagrać.` |
| pl-real-probuje-formal | formal | new | 0.69s | ok | `Teraz próbuję coś nagrać.` |
| pl-real-probuje-casual | casual | old | 0.69s | ok | `Teraz próbuję coś nagrać.` |
| pl-real-probuje-casual | casual | new | 0.69s | ok | `Teraz próbuję coś nagrać.` |
| pl-real-probuje-neutral | neutral | old | 0.67s | ok | `Teraz próbuję coś nagrać.` |
| pl-real-probuje-neutral | neutral | new | 0.69s | ok | `Teraz próbuję coś nagrać.` |


=== verbatim, every output that is not one line ===

