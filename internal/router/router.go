package router

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/cwhight/llm-router/internal/benchmark"
	"github.com/cwhight/llm-router/internal/claude"
	"github.com/cwhight/llm-router/internal/config"
	"github.com/cwhight/llm-router/internal/ollama"
)

type Task struct {
	Category string
	System   string
	Input    string
}

type Result struct {
	Output       string
	Model        string
	InputTokens  int
	OutputTokens int
	Latency      time.Duration
	CostUSD      float64
	Routed       string // "ollama" or "claude"
}

type Router struct {
	cfg    *config.Config
	ollama *ollama.Client
	claude *claude.Client
	bench  *benchmark.Store
}

func New(cfg *config.Config, bench *benchmark.Store) *Router {
	return &Router{
		cfg:    cfg,
		ollama: ollama.NewClient(cfg.Ollama.Host),
		claude: claude.NewClient(cfg.Claude.APIKey),
		bench:  bench,
	}
}

func (r *Router) Route(ctx context.Context, task Task) (*Result, error) {
	model := r.selectModel(task.Category)

	var result *Result
	var err error

	if strings.HasPrefix(model, "ollama:") {
		result, err = r.routeOllama(ctx, model, task)
	} else {
		result, err = r.routeClaude(ctx, model, task)
	}

	if err != nil {
		if strings.HasPrefix(model, "ollama:") {
			fmt.Printf("[router] ollama failed, falling back to claude: %v\n", err)
			model = "claude:" + r.cfg.Claude.DefaultModel
			result, err = r.routeClaude(ctx, model, task)
			if err != nil {
				return nil, fmt.Errorf("claude fallback: %w", err)
			}
		} else {
			return nil, err
		}
	}

	_ = r.bench.Record(benchmark.Result{
		Category:     task.Category,
		Model:        result.Model,
		InputTokens:  result.InputTokens,
		OutputTokens: result.OutputTokens,
		Latency:      result.Latency.Seconds(),
		Quality:      8.0, // default passing score; override with scored samples when available
		CostUSD:      result.CostUSD,
	})

	return result, nil
}

func (r *Router) selectModel(category string) string {
	if r.cfg.IsClaudeOnly(category) {
		return "claude:" + r.cfg.Claude.OpusModel
	}

	if recommended := r.bench.RecommendModel(category, r.cfg.Routing.QualityThreshold); recommended != "" {
		return recommended
	}

	if def, ok := r.cfg.Routing.Defaults[category]; ok {
		return def
	}

	return "claude:" + r.cfg.Claude.DefaultModel
}

func (r *Router) routeOllama(ctx context.Context, model string, task Task) (*Result, error) {
	ollamaModel := r.resolveOllamaModel(model)

	res, err := r.ollama.Generate(ctx, ollamaModel, task.System, task.Input)
	if err != nil {
		return nil, err
	}

	return &Result{
		Output:       res.Output,
		Model:        model,
		InputTokens:  res.InputTokens,
		OutputTokens: res.OutputTokens,
		Latency:      res.Latency,
		CostUSD:      0,
		Routed:       "ollama",
	}, nil
}

func (r *Router) routeClaude(ctx context.Context, model string, task Task) (*Result, error) {
	claudeModel := r.resolveClaudeModel(model)

	res, err := r.claude.Generate(ctx, claudeModel, task.System, task.Input)
	if err != nil {
		return nil, err
	}

	cost := estimateCost(claudeModel, res.InputTokens, res.OutputTokens)

	return &Result{
		Output:       res.Output,
		Model:        model,
		InputTokens:  res.InputTokens,
		OutputTokens: res.OutputTokens,
		Latency:      res.Latency,
		CostUSD:      cost,
		Routed:       "claude",
	}, nil
}

func (r *Router) resolveOllamaModel(model string) string {
	parts := strings.SplitN(model, ":", 2)
	if len(parts) < 2 {
		return r.cfg.Ollama.Models["small"]
	}
	key := parts[1]
	if resolved, ok := r.cfg.Ollama.Models[key]; ok {
		return resolved
	}
	return key
}

func (r *Router) resolveClaudeModel(model string) string {
	parts := strings.SplitN(model, ":", 2)
	if len(parts) < 2 {
		return r.cfg.Claude.DefaultModel
	}
	switch parts[1] {
	case "default":
		return r.cfg.Claude.DefaultModel
	case "opus":
		return r.cfg.Claude.OpusModel
	default:
		return parts[1]
	}
}

func estimateCost(model string, inputTokens, outputTokens int) float64 {
	var inputRate, outputRate float64
	switch {
	case strings.Contains(model, "opus"):
		inputRate = 15.0 / 1_000_000
		outputRate = 75.0 / 1_000_000
	case strings.Contains(model, "sonnet"):
		inputRate = 3.0 / 1_000_000
		outputRate = 15.0 / 1_000_000
	case strings.Contains(model, "haiku"):
		inputRate = 0.80 / 1_000_000
		outputRate = 4.0 / 1_000_000
	default:
		inputRate = 3.0 / 1_000_000
		outputRate = 15.0 / 1_000_000
	}
	return float64(inputTokens)*inputRate + float64(outputTokens)*outputRate
}

func (r *Router) OllamaHealthy(ctx context.Context) bool {
	return r.ollama.Healthy(ctx)
}

func (r *Router) Stats() map[string]*benchmark.CategoryStats {
	return r.bench.AllStats()
}
