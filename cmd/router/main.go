package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"strings"
	"text/tabwriter"

	"github.com/cwhight/llm-router/internal/benchmark"
	"github.com/cwhight/llm-router/internal/config"
	"github.com/cwhight/llm-router/internal/router"
)

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(1)
	}

	configPath := envOrDefault("CONFIG_FILE", "config.yaml")
	cfg, err := config.Load(configPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "load config: %v\n", err)
		os.Exit(1)
	}

	bench, err := benchmark.NewStore(cfg.Benchmarks.ResultsFile)
	if err != nil {
		fmt.Fprintf(os.Stderr, "load benchmarks: %v\n", err)
		os.Exit(1)
	}

	r := router.New(cfg, bench)

	switch os.Args[1] {
	case "route":
		cmdRoute(r, os.Args[2:])
	case "stats":
		cmdStats(r)
	case "health":
		cmdHealth(r)
	default:
		usage()
		os.Exit(1)
	}
}

func cmdRoute(r *router.Router, args []string) {
	var task, system, input, model, format string

	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "--task":
			i++; task = args[i]
		case "--system":
			i++; system = args[i]
		case "--input":
			i++; input = args[i]
		case "--input-file":
			i++
			data, err := os.ReadFile(args[i])
			if err != nil {
				fmt.Fprintf(os.Stderr, "read input file: %v\n", err)
				os.Exit(1)
			}
			input = string(data)
		case "--model":
			i++; model = args[i]
		case "--format":
			i++; format = args[i]
		}
	}

	if task == "" || input == "" {
		fmt.Fprintln(os.Stderr, "Usage: llm-router route --task <category> --input <text> [--system <prompt>] [--model <override>] [--format json]")
		os.Exit(1)
	}

	_ = model // TODO: model override

	result, err := r.Route(context.Background(), router.Task{
		Category: task,
		System:   system,
		Input:    input,
	})
	if err != nil {
		fmt.Fprintf(os.Stderr, "route error: %v\n", err)
		os.Exit(1)
	}

	if strings.EqualFold(format, "json") {
		out := map[string]any{
			"output":        result.Output,
			"model":         result.Model,
			"routed":        result.Routed,
			"input_tokens":  result.InputTokens,
			"output_tokens": result.OutputTokens,
			"latency_ms":    result.Latency.Milliseconds(),
			"cost_usd":      result.CostUSD,
		}
		json.NewEncoder(os.Stdout).Encode(out)
	} else {
		fmt.Print(result.Output)
		fmt.Fprintf(os.Stderr, "\n--- routed: %s | model: %s | tokens: %d+%d | latency: %s | cost: $%.6f ---\n",
			result.Routed, result.Model, result.InputTokens, result.OutputTokens, result.Latency, result.CostUSD)
	}
}

func cmdStats(r *router.Router) {
	stats := r.Stats()

	if len(stats) == 0 {
		fmt.Println("No benchmark data yet. Route some tasks first.")
		return
	}

	w := tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', 0)
	fmt.Fprintln(w, "CATEGORY\tMODEL\tCOUNT\tAVG QUALITY\tAVG LATENCY\tAVG COST\tTOTAL COST\tBEST")

	for cat, cs := range stats {
		for model, st := range cs.ModelStats {
			best := ""
			if model == cs.BestModel {
				best = "<--"
			}
			fmt.Fprintf(w, "%s\t%s\t%d\t%.1f\t%.2fs\t$%.6f\t$%.4f\t%s\n",
				cat, model, st.Count, st.AvgQuality, st.AvgLatency, st.AvgCost, st.TotalCost, best)
		}
	}
	w.Flush()
}

func cmdHealth(r *router.Router) {
	ctx := context.Background()
	if r.OllamaHealthy(ctx) {
		fmt.Println("ollama: healthy")
	} else {
		fmt.Println("ollama: unreachable")
	}
}

func usage() {
	fmt.Fprintln(os.Stderr, `llm-router — intelligent LLM task router

Commands:
  route   Route a task to the best model
  stats   Show benchmark statistics
  health  Check model availability

Examples:
  llm-router route --task summarise --input "long text here"
  llm-router route --task extract --input-file data.txt --format json
  llm-router stats
  llm-router health`)
}

func envOrDefault(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}
