package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"time"

	"github.com/joho/godotenv"
	"github.com/theprimeagen/vim-with-me/examples/v2/td"
	"github.com/theprimeagen/vim-with-me/pkg/testies"
	"github.com/theprimeagen/vim-with-me/pkg/v2/assert"
	"github.com/theprimeagen/vim-with-me/pkg/v2/chat"
	"github.com/theprimeagen/vim-with-me/pkg/v2/cmd"
)

func getDebug(name string) (*testies.DebugFile, error) {
    if name == "" {
        return testies.EmptyDebugFile(), nil
    }
    return testies.NewDebugFile(name)
}

func occurrencesToPositions(occ []chat.Occurrence, gs *td.GameState) []td.Position {
    out := []td.Position{}
    for i := range gs.AllowedTowers {
        if len(occ) <= i {
            break
        }
        pos, err := td.PositionFromString(occ[i].Msg)
        if err != nil {
            continue
        }
        out = append(out, pos)
    }

    return out
}

func main() {

    testies.SetupLogger()

	godotenv.Load()

	debugFile := ""
	flag.StringVar(&debugFile, "debug", "", "runs the file like the program instead of running doom")

	systemPromptFile := "THEPRIMEAGEN"
	flag.StringVar(&systemPromptFile, "system", "THEPRIMEAGEN", "the system prompt to use")

	viz := false
	flag.BoolVar(&viz, "viz", false, "displays the game")


	seed := 1337
	flag.IntVar(&seed, "seed", 69420, "the seed value for the game")
	flag.Parse()

	args := flag.Args()
    assert.Assert(len(args) >= 2, "you must provide path to exec and json file")
	name := args[0]
	json := args[1]

    debug, err := getDebug(debugFile)
    if err != nil {
        log.Fatalf("could not open up debug file: %v\n", err)
    }
    defer debug.Close()

    //systemPrompt, err := os.ReadFile(systemPromptFile)
    if err != nil {
        log.Fatalf("could not open system prompt: %+v\n", err)
    }

	ctx := context.Background()
	twitchChat, err := chat.NewTwitchChat(ctx)
	assert.NoError(err, "twitch cannot initialize")
	chtAgg := chat.
		NewChatAggregator().
		WithFilter(td.TDFilter(24, 80));

    cmdParser := td.NewCmdErrParser(debug)

    prog := cmd.NewCmder(name, ctx).
        AddVArg(json).
        AddKVArg("--seed", fmt.Sprintf("%d", seed)).
        WithErrFn(cmdParser.Parse).
        WithOutFn(func(b []byte) (int, error) {
            if viz {
                fmt.Printf("%s\n", string(b))
            }
            return len(b), nil
        })

    cmdr := td.TDCommander {
        Cmdr: prog,
        Debug: debug,
    }

    go prog.Run()
	go chtAgg.Pipe(twitchChat)

    //ai := td.NewStatefulOpenAIChat(os.Getenv("OPENAI_API_KEY"), string(systemPrompt), ctx)
    //fetch := td.NewFetchPosition(ai, debug)
    stats := td.Stats{}
    round := 0
    fmt.Printf("won,round,prompt file,seed,ai total towers,ai guesses,ai bad parses\n")

    defer func() {
        fmt.Println("\x1b[?25h")
    }()

    box := td.NewBoxPos(24)

    outer:
    for {
        debug.WriteStrLine(fmt.Sprintf("------------- waiting on game round: %d -----------------", round))
        select {
        case <-ctx.Done():
            break outer;
        case gs := <- cmdParser.Gs:
            debug.WriteStrLine(fmt.Sprintf("ai-placement response: \"%s\"", gs.String()))
            round = int(gs.Round)

            if gs.Finished {
                if gs.Winner == '1' {
                    fmt.Printf("1,%d,%s,%d,%s\n", round, systemPromptFile, seed, stats.String())
                } else {
                    fmt.Printf("2,%d,%s,%d,%s\n", round, systemPromptFile, seed, stats.String())
                }
                break outer
            }

            if gs.Playing {
                continue
            }

            _ = chtAgg.Reset()
            innerCtx, cancel := context.WithCancel(ctx)
            go func() {
                outer:
                for {
                    select {
                    case <-time.NewTimer(time.Second).C:
                        occs := chtAgg.Peak()
                        one := occurrencesToPositions(occs, &gs)
                        cmdr.WritePositions(one, '2')
                    case <-innerCtx.Done():
                        break outer
                    }
                }
            }()

            duration := time.Second * 20
            t := time.NewTimer(duration)
            cmdr.Countdown(duration)

            //positions, fetchStats := fetch.Fetch(&gs)
            //stats.Add(fetchStats)

            //cmdr.WritePositions(positions, '2')
            out := []td.Position{}
            for range gs.AllowedTowers {
                out = append(out, box.NextPos())
            }
            cmdr.WritePositions(out, '1')

            <-t.C
            cancel()
            one := occurrencesToPositions(chtAgg.Peak(), &gs)
            cmdr.WritePositions(one, '2')
            cmdr.PlayRound()
        }
    }
}

