package config

import (
	"fmt"
	"os"
	"strings"

	"gopkg.in/yaml.v3"
)

type Config struct {
	Claude     ClaudeConfig     `yaml:"claude"`
	Ollama     OllamaConfig     `yaml:"ollama"`
	Routing    RoutingConfig    `yaml:"routing"`
	Benchmarks BenchmarkConfig  `yaml:"benchmarks"`
	Metrics    MetricsConfig    `yaml:"metrics"`
}

type ClaudeConfig struct {
	APIKey       string `yaml:"api_key"`
	DefaultModel string `yaml:"default_model"`
	OpusModel    string `yaml:"opus_model"`
	HaikuModel   string `yaml:"haiku_model"`
}

type OllamaConfig struct {
	Host   string            `yaml:"host"`
	Models map[string]string `yaml:"models"`
}

type RoutingConfig struct {
	QualityThreshold float64           `yaml:"quality_threshold"`
	Defaults         map[string]string `yaml:"defaults"`
	ClaudeOnly       []string          `yaml:"claude_only"`
}

type BenchmarkConfig struct {
	SampleRate      float64 `yaml:"sample_rate"`
	ResultsFile     string  `yaml:"results_file"`
	ReevalThreshold int     `yaml:"reeval_threshold"`
}

type MetricsConfig struct {
	Enabled bool   `yaml:"enabled"`
	Addr    string `yaml:"addr"`
}

func DefaultConfigPath() string {
	if v := os.Getenv("LLM_ROUTER_CONFIG"); v != "" {
		return v
	}
	home, _ := os.UserHomeDir()
	return home + "/.config/llm-router/config.yaml"
}

func DefaultBenchmarksPath() string {
	home, _ := os.UserHomeDir()
	return home + "/.config/llm-router/benchmarks/results.jsonl"
}

func DefaultRoutingLogPath() string {
	home, _ := os.UserHomeDir()
	return home + "/.config/llm-router/routing.log"
}

func Load(path string) (*Config, error) {
	if path == "" {
		path = DefaultConfigPath()
	}

	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read config: %w", err)
	}

	expanded := os.ExpandEnv(string(data))

	var cfg Config
	if err := yaml.Unmarshal([]byte(expanded), &cfg); err != nil {
		return nil, fmt.Errorf("parse config: %w", err)
	}

	if cfg.Claude.APIKey == "" {
		cfg.Claude.APIKey = os.Getenv("ANTHROPIC_API_KEY")
	}

	return &cfg, nil
}

func (c *Config) IsClaudeOnly(category string) bool {
	for _, co := range c.Routing.ClaudeOnly {
		if strings.EqualFold(co, category) {
			return true
		}
	}
	return false
}
