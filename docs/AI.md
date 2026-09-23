# Shadow — the chess engine

Shadow is written in GDScript and runs entirely on worker threads, so the board never freezes while it thinks.

## Design

- **Board** (`scripts/ai/shadow_board.gd`): a 0x88 board in a `PackedInt32Array`, moves packed into single integers, piece lists with the king in slot 0, and incremental Zobrist keys (the same keys `ChessEngine.hash_key` uses) plus incremental PeSTO midgame/endgame sums. Make/unmake uses an undo stack; nothing is allocated per node.
- **Search** (`scripts/ai/shadow_search.gd`): iterative deepening with aspiration windows, principal-variation search, a fixed-size transposition table in packed arrays, null-move pruning, late-move reductions, futility and late-move pruning, check extensions, killer and history move ordering with MVV-LVA captures, and a quiescence search with delta pruning. Repetition and fifty-move draws use the real game history, which each job replays from `start_fen`.
- **Evaluation**: tapered PeSTO piece-square tables plus bishop pair, pawn structure (doubled, isolated, passed pawns by rank), rooks on open and half-open files, a king pawn-shield term, and tempo.
- **Opening book** (`data/opening_book.txt`): hand-written mainlines across the open games, Sicilian, French, Caro-Kann, Pirc, Scandinavian, Alekhine, Queen's Gambit, Slav, Indian defences, Dutch, English, Réti, and London. Moves are weighted by how often they appear; every line is replayed for legality by the test suite.

## Levels

| Level | Nominal Elo | Depth cap | Time | Character |
|---|---|---|---|---|
| Beginner | 600 | 2 | 0.2 s | Picks from a wide band of moves and sometimes hangs material |
| Casual | 1000 | 3 | 0.5 s | Sees simple threats, plays loosely |
| Club | 1400 | 4 | 0.7 s | Principled, punishes loose pieces |
| Advanced | 1700 | 6 | 1.2 s | Rarely lets a tactic slip |
| Expert | 1900 | — | 2.0 s | Full search, no deliberate mistakes |
| Master | 2100 | — | 3.0 s | Full strength |

Weaker levels keep exact scores for every root move within a margin of the best and choose among them with a seeded softmax; Beginner occasionally takes a clearly worse (but not suicidal) move. Expert and Master are deterministic apart from book choices. When the clock runs low, Shadow budgets its time from what is left on its clock plus the increment.

Measured on this project's reference machine (three middlegame positions, book off, `tools/bench_ai.gd`):

| Level | Average depth | Nodes/second | Time per move |
|---|---|---|---|
| Beginner | 2 | ~51k | 44 ms |
| Casual | 3 | ~44k | 0.25 s |
| Club | 4 | ~35k | 0.3 s |
| Advanced | 5.3 | ~35k | 0.7 s |
| Expert | 7 | ~33k | 1.2 s |
| Master | 7.7 | ~34k | 1.9 s |

## Using it

```gdscript
ChessAI.warmup()                        # once, on the main thread
var job := ChessAI.SearchJob.new()
job.start_fen = engine.start_fen
job.moves_uci = moves                   # full game so far, for repetition
job.level = "club"                      # or "analysis" with job.time_ms
var task := WorkerThreadPool.add_task(job.run, true)
# … poll WorkerThreadPool.is_task_completed(task), then wait_for_task_completion(task)
print(job.best_uci, job.score_white_cp, job.mate_in, job.depth, job.pv)
```

Set `job.cancelled = true` to stop a search early; it notices within a few milliseconds. The same job type powers Shadow's moves, the evaluation bar and principal variation in analysis, and hints.

## Puzzles

`data/puzzles.json` holds 36 original checkmate puzzles (12 mate-in-1, 16 mate-in-2, 8 mate-in-3) built on classic patterns — back rank, smothered, Anastasia, Arabian, Boden, Légal, Damiano, epaulette, and more. `ChessPuzzles` checks answers with an exact mate search, so any move that still forces mate in time is accepted, and the defender always plays the reply that delays mate longest. The test suite proves every puzzle: legal solution line, checkmate at the end, a correct first move, and no shorter mate.
