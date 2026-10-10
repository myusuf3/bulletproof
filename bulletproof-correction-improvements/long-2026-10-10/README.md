# Long-input stress set (2026-10-10)

9 documents built by joining clean single-paragraph s4 acceptable outputs (5 at ~1.5k chars, 4 at ~3k chars, under
LocalModelEngine's ~3.3k input cap), each with 6 typos injected at middle occurrences of common words.
Acceptable output: the clean document. Tests length robustness of the restorers, gates and latency, not topic
generalization (the text is corpus text). Never tune on it.
